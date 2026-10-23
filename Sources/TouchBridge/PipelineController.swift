import AppKit
import IOKit
import os
import TouchCore
import TouchDevice

/// Thread-safe lookup of pipelines by device, used from the HID thread for the hot path.
private final class PipelineRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var pipelines: [DeviceID: DevicePipeline] = [:]

    func pipeline(for id: DeviceID) -> DevicePipeline? { lock.withLock { pipelines[id] } }
    func set(_ pipeline: DevicePipeline, for id: DeviceID) { lock.withLock { pipelines[id] = pipeline } }
    func remove(_ id: DeviceID) -> DevicePipeline? { lock.withLock { pipelines.removeValue(forKey: id) } }
    func removeAll() -> [DevicePipeline] { lock.withLock { let all = Array(pipelines.values); pipelines.removeAll(); return all } }
    var all: [DevicePipeline] { lock.withLock { Array(pipelines.values) } }
}

/// Owns the DeviceManager and one DevicePipeline per attached touch screen.
@MainActor
final class PipelineController {
    var onStatus: ((AppState.DeviceStatus) -> Void)?
    var onContacts: ((DeviceID, [Contact]) -> Void)?
    /// Reports the frontmost bundle ID and the profile that now applies (for the settings window header).
    var onActiveProfile: ((String?, EffectiveProfile) -> Void)?

    private let logger = Logger(subsystem: "org.touchbridge", category: "pipeline")
    private let registry = PipelineRegistry()
    private let displays = DisplayResolver()
    private let frontmost = FrontmostAppObserver()
    private static let ownBundleID = Bundle.main.bundleIdentifier ?? "org.touchbridge.TouchBridge"
    private var deviceManager: DeviceManager?
    private var settings: Settings
    private(set) var isPaused = false
    private var wakeObserver: NSObjectProtocol?

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        isPaused = false
        guard deviceManager == nil else { return }
        displays.startObserving { [weak self] in self?.remapAll() }
        frontmost.onChange = { [weak self] _ in self?.applyProfile() }
        frontmost.start()
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.restart() }
            }
        }
        let registry = self.registry
        // The sink runs on the HID thread: reports go straight to the pipeline's queue, everything else to the main actor.
        // Control events use the main queue rather than separate Tasks so attach/detach keep their order (FIFO).
        let manager = DeviceManager(preferExclusive: true) { [weak self] event in
            if case .report(let id, let reportID, let raw, let timestamp) = event {
                registry.pipeline(for: id)?.handle(reportID: reportID, raw: raw, timestamp: timestamp)
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
        deviceManager = manager
        manager.start()
        logger.info("controller started")
    }

    /// Stops the device manager and all pipelines and stays stopped (also across wake) until `start()`.
    func pause() {
        stopAll()
        isPaused = true
    }

    private func stopAll() {
        deviceManager?.stop()
        deviceManager = nil
        for pipeline in registry.removeAll() { pipeline.shutdown() }
        onStatus?(.none)
    }

    func restart() {
        guard !isPaused else { return }
        logger.info("restarting after wake")
        stopAll()
        // Devices re-enumerate after wake; reopen them a moment later.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !self.isPaused else { return }
            self.start()
        }
    }

    func updateSettings(_ settings: Settings) {
        self.settings = settings
        applyProfile()
        remapAll()
    }

    /// The effective profile for the frontmost application. TouchBridge itself and an unknown frontmost app use
    /// the default profile, so configuring never locks the user out.
    var activeProfile: EffectiveProfile {
        let id = frontmost.bundleID
        let lookup = (id == nil || id == Self.ownBundleID) ? nil : id
        return settings.effectiveProfile(for: lookup)
    }

    private func applyProfile() {
        let profile = activeProfile
        for pipeline in registry.all { pipeline.apply(profile: profile, enabled: settings.enabled) }
        onActiveProfile?(frontmost.bundleID, profile)
    }

    private func open(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            logger.error("open file: \(path, privacy: .public) does not exist")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func availableDisplays() -> [DisplayResolver.DisplayDescription] {
        displays.allDisplays()
    }

    // MARK: - Device events (main actor)

    private func handle(_ event: DeviceEvent) {
        switch event {
        case .attached(let id, let info, let mode):
            // A re-matched device can be attached again without a detach: end the old pipeline's gestures first,
            // also when the new descriptor turns out to be unusable.
            registry.remove(id)?.shutdown()
            do {
                let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(info.descriptor))
                let pipeline = DevicePipeline(id: id, info: info, layout: layout,
                                              mapping: mapping(for: info, layout: layout),
                                              profile: activeProfile, enabled: settings.enabled)
                pipeline.onContacts = { [weak self] contacts in
                    Task { @MainActor in self?.onContacts?(id, contacts) }
                }
                pipeline.onOpenFile = { [weak self] path in
                    Task { @MainActor in self?.open(path) }
                }
                registry.set(pipeline, for: id)
                let problem: String?
                switch mode {
                case .exclusive: problem = nil
                case .shared(let seizeStatus):
                    problem = seizeStatus == kIOReturnNotPermitted
                        ? "Input Monitoring missing"
                        : "exclusive access failed (0x\(String(UInt32(bitPattern: seizeStatus), radix: 16)))"
                }
                onStatus?(.attached(name: info.product, exclusive: mode.isExclusive, problem: problem))
                logger.info("pipeline ready for \(info.product, privacy: .public) (\(layout.slots.count) slots)")
            } catch {
                let hex = info.descriptor.map { String(format: "%02x", $0) }.joined()
                logger.error("descriptor of \(info.product, privacy: .public) unusable: \(String(describing: error), privacy: .public); bytes: \(hex, privacy: .public)")
                // The device is seized but useless to us: hand it back so macOS's single-touch driver works again.
                deviceManager?.release(id)
                onStatus?(.openFailed(name: "\(info.product) (descriptor)"))
            }
        case .openFailed(let id, let info, let status):
            // The manager closed an earlier entry for this ID before the failed open, so its pipeline gets no reports.
            registry.remove(id)?.shutdown()
            logger.error("open of \(info.product, privacy: .public) failed: 0x\(String(UInt32(bitPattern: status), radix: 16), privacy: .public)")
            onStatus?(.openFailed(name: info.product))
        case .detached(let id):
            registry.remove(id)?.shutdown()
            if registry.all.isEmpty { onStatus?(.none) }
        case .report:
            break
        }
    }

    private func mapping(for info: DeviceInfo, layout: TouchScreenLayout) -> MappingConfig {
        let display = displays.resolve(settings.displaySelection)
        let frame = display?.frame ?? CGDisplayBounds(CGMainDisplayID())
        let calibration = settings.calibrations[info.serial] ?? Calibration(orientation: display?.rotation ?? 0)
        return MappingConfig(logicalMaxX: layout.logicalMaxX, logicalMaxY: layout.logicalMaxY,
                             displayFrame: frame, calibration: calibration)
    }

    private func remapAll() {
        for pipeline in registry.all {
            pipeline.updateMapping(mapping(for: pipeline.info, layout: pipeline.layout))
        }
    }
}
