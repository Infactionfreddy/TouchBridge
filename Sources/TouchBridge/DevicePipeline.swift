import Foundation
import CoreGraphics
import os
import TouchCore
import TouchDevice
import TouchInject

/// The processing chain of one touch screen. Everything after `handle` runs on `queue`.
final class DevicePipeline: @unchecked Sendable {
    let id: DeviceID
    let info: DeviceInfo
    let layout: TouchScreenLayout
    let queue: DispatchQueue
    var onContacts: (@Sendable ([Contact]) -> Void)?
    /// Called (on the pipeline queue) for `Command.openFile`; the app layer opens the file on the main actor.
    var onOpenFile: (@Sendable (String) -> Void)?

    private let logger = Logger(subsystem: "org.touchbridge", category: "pipeline")
    private var decoder: ReportDecoder
    private var mapper: DisplayMapper
    private var tracker: TouchTracker
    private var engine: GestureEngine
    private var router: ActionRouter
    private let injector: EventInjector
    private var tickTimer: DispatchSourceTimer?
    private var enabled: Bool
    private var lastContactsPublish: UInt64 = 0

    init(id: DeviceID, info: DeviceInfo, layout: TouchScreenLayout, mapping: MappingConfig, profile: EffectiveProfile, enabled: Bool) {
        self.id = id
        self.info = info
        self.layout = layout
        queue = DispatchQueue(label: "org.touchbridge.pipeline.\(id)", qos: .userInteractive)
        decoder = ReportDecoder(layout: layout)
        mapper = DisplayMapper(config: mapping)
        tracker = TouchTracker(stuckTimeout: UInt64(profile.config.stuckTimeout * 1_000_000_000))
        engine = GestureEngine(config: profile.config)
        router = ActionRouter(profile: profile)
        injector = EventInjector(queue: queue, momentum: MomentumGenerator(
            decayPerFrame: profile.config.momentumDecayPerFrame,
            stopVelocity: profile.config.momentumStopVelocity))
        self.enabled = enabled
    }

    // MARK: - Input (any thread)

    func handle(reportID: UInt8, raw: [UInt8], timestamp: UInt64) {
        queue.async { self.process(reportID: reportID, raw: raw, timestamp: timestamp) }
    }

    /// Applies a new display mapping and ends open gestures. A mapping equal to the current one is ignored,
    /// so saving unrelated settings does not cut off a gesture.
    func updateMapping(_ mapping: MappingConfig) {
        queue.async {
            guard self.mapper.config != mapping else { return }
            self.mapper = DisplayMapper(config: mapping)
            self.finishGestures()
        }
    }

    /// Applies the effective profile of the frontmost app and the touch-enabled flag. A running gesture keeps
    /// the routing decision made at its start (`ActionRouter(profile:continuing:)`); new thresholds apply from
    /// the next decision on.
    func apply(profile: EffectiveProfile, enabled: Bool) {
        queue.async {
            self.engine.config = profile.config
            self.router = ActionRouter(profile: profile, continuing: self.router)
            self.tracker.stuckTimeout = UInt64(profile.config.stuckTimeout * 1_000_000_000)
            self.injector.momentum = MomentumGenerator(decayPerFrame: profile.config.momentumDecayPerFrame,
                                                       stopVelocity: profile.config.momentumStopVelocity)
            if self.enabled && !enabled { self.finishGestures() }
            self.enabled = enabled
        }
    }

    func cancelGestures() {
        queue.async { self.finishGestures() }
    }

    /// Synchronous: ends gestures, releases buttons, stops timers. Call before dropping the pipeline.
    func shutdown() {
        queue.sync {
            self.finishGestures()
            self.tickTimer?.cancel()
            self.tickTimer = nil
        }
    }

    // MARK: - Processing (queue)

    private func process(reportID: UInt8, raw: [UInt8], timestamp: UInt64) {
        guard reportID == layout.reportID,
              let payload = ReportFraming.payload(from: raw, reportID: reportID, layout: layout),
              let frame = decoder.decode(payload: payload, timestamp: timestamp) else { return }
        let screen = mapper.map(frame)
        publishContacts(screen)
        _ = tracker.process(screen)
        guard enabled else { return }
        run(engine.update(touches: tracker.touches, timestamp: timestamp))
        updateTickTimer()
    }

    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        let expired = tracker.tick(now)
        if !expired.isEmpty { logger.info("ended \(expired.count) stuck contact(s)") }
        // Stuck contacts expire even while touch is off, but the engine must not be fed then.
        guard enabled else { updateTickTimer(); return }
        if !expired.isEmpty { run(engine.update(touches: tracker.touches, timestamp: now)) }
        run(engine.tick(now))
        updateTickTimer()
    }

    /// The 20 ms tick runs only while contacts are active or a gesture is open.
    private func updateTickTimer() {
        let needed = !tracker.touches.isEmpty || !engine.isIdle
        if needed, tickTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20), leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in self?.tick() }
            tickTimer = timer
            timer.resume()
        } else if !needed, let timer = tickTimer {
            timer.cancel()
            tickTimer = nil
        }
    }

    /// Ends the open gesture (button up, scroll/magnify/rotate ended), then stops momentum and releases a held button.
    private func finishGestures() {
        run(engine.reset())
        injector.releaseAll()
    }

    private func run(_ actions: [Action]) {
        guard !actions.isEmpty else { return }
        let context = RouterContext(frontmostBundleID: router.profile.profileID)
        for action in actions {
            logger.debug("action \(String(describing: action), privacy: .public)")
            for command in router.route(action, context: context) {
                if case .openFile(let path) = command {
                    onOpenFile?(path)
                } else {
                    injector.perform(command)
                }
            }
        }
    }

    /// Publishes the down contacts for the UI at most every 33 ms, and always when the last finger lifts.
    private func publishContacts(_ screen: ScreenFrame) {
        guard let onContacts else { return }
        let down = screen.contacts.filter(\.down)
        if down.isEmpty || screen.timestamp &- lastContactsPublish > 33_000_000 {
            lastContactsPublish = screen.timestamp
            onContacts(down)
        }
    }
}
