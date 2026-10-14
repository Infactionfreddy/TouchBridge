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

    private let logger = Logger(subsystem: "org.touchbridge", category: "pipeline")
    private let registry = PipelineRegistry()
    private let displays = DisplayResolver()
    private var deviceManager: DeviceManager?
    private var settings: Settings
    private var wakeObserver: NSObjectProtocol?

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        guard deviceManager == nil else { return }
        displays.startObserving { [weak self] in self?.remapAll() }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.restart() }
            }
        }
        let registry = self.registry
        // The sink runs on the HID thread: reports go straight to the pipeline's queue, everything else to the main actor.
        let manager = DeviceManager(preferExclusive: true) { [weak self] event in
            if case .report(let id, let reportID, let raw, let timestamp) = event {
                registry.pipeline(for: id)?.handle(reportID: reportID, raw: raw, timestamp: timestamp)
                return
            }
            Task { @MainActor in self?.handle(event) }
        }
        deviceManager = manager
        manager.start()
        logger.info("controller started")
    }

    func restart() {
        logger.info("restarting after wake")
        deviceManager?.stop()
        deviceManager = nil
        for pipeline in registry.removeAll() { pipeline.shutdown() }
        onStatus?(.none)
        // Devices re-enumerate after wake; reopen them a moment later.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.start()
        }
    }

    func updateSettings(_ settings: Settings) {
        self.settings = settings
        for pipeline in registry.all { pipeline.updateSettings(settings) }
        remapAll()
    }

    func availableDisplays() -> [DisplayResolver.DisplayDescription] {
        displays.allDisplays()
    }

    // MARK: - Device events (main actor)

    private func handle(_ event: DeviceEvent) {
        switch event {
        case .attached(let id, let info, let mode):
            do {
                let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(info.descriptor))
                let pipeline = DevicePipeline(id: id, info: info, layout: layout,
                                              mapping: mapping(for: info, layout: layout), settings: settings)
                pipeline.onContacts = { [weak self] contacts in
                    Task { @MainActor in self?.onContacts?(id, contacts) }
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
                logger.error("descriptor of \(info.product, privacy: .public) unusable: \(String(describing: error), privacy: .public)")
                onStatus?(.openFailed(name: "\(info.product) (descriptor)"))
            }
        case .openFailed(_, let info, let status):
            logger.error("open failed 0x\(String(status, radix: 16), privacy: .public)")
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
