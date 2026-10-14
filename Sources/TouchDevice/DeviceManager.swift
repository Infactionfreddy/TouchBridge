import Foundation
import IOKit
import IOKit.hid
import os
import TouchCore

/// Finds HID touch screens (usage page 0x0D, usage 0x04), opens them exclusively and delivers raw input reports.
/// Runs its own thread with a CFRunLoop; `sink` is called on that thread.
public final class DeviceManager: @unchecked Sendable {
    public typealias Sink = @Sendable (DeviceEvent) -> Void

    private final class Entry {
        let device: IOHIDDevice
        let buffer: UnsafeMutablePointer<UInt8>
        let bufferSize: Int
        let id: DeviceID
        weak var manager: DeviceManager?

        init(device: IOHIDDevice, bufferSize: Int, id: DeviceID, manager: DeviceManager) {
            self.device = device
            self.bufferSize = bufferSize
            self.buffer = .allocate(capacity: bufferSize)
            self.buffer.initialize(repeating: 0, count: bufferSize)
            self.id = id
            self.manager = manager
        }

        deinit { buffer.deallocate() }
    }

    private let sink: Sink
    private let preferExclusive: Bool
    private let logger = Logger(subsystem: "org.touchbridge", category: "device")
    /// Guards all lifecycle state below.
    private let lock = NSLock()
    private var running = false
    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var finished: DispatchSemaphore?
    private var entries: [DeviceID: Entry] = [:]

    public init(preferExclusive: Bool = true, sink: @escaping Sink) {
        self.preferExclusive = preferExclusive
        self.sink = sink
    }

    /// Starts the HID thread and returns once the manager is scheduled. Calling it while running is a no-op.
    public func start() {
        let ready = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            lock.withLock {
                self.manager = manager
                self.runLoop = CFRunLoopGetCurrent()
            }
            let matching: [String: Any] = [
                kIOHIDPrimaryUsagePageKey: Int(HIDUsage.touchScreen.page),
                kIOHIDPrimaryUsageKey: Int(HIDUsage.touchScreen.id),
            ]
            IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
                guard let context else { return }
                Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
            }, context)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
                guard let context else { return }
                Unmanaged<DeviceManager>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
            }, context)
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            // IOHIDManagerOpen is deliberately not called: devices are opened one by one so that each can be seized.
            self.logger.info("HID manager scheduled")
            ready.signal()
            CFRunLoopRun()
            lock.withLock {
                self.manager = nil
                self.runLoop = nil
            }
            self.logger.info("HID thread finished")
            finished.signal()
        }
        thread.name = "org.touchbridge.hid"
        thread.qualityOfService = .userInteractive
        let shouldStart = lock.withLock {
            if running { return false }
            running = true
            self.thread = thread
            self.finished = finished
            return true
        }
        guard shouldStart else { return }
        thread.start()
        ready.wait()
    }

    /// Synchronous: returns after the HID thread has exited; no sink call happens after it returns.
    /// Must not be called from the sink (it runs on the HID thread).
    public func stop() {
        let state = lock.withLock { running ? (runLoop, manager, finished) : nil }
        guard let (runLoop, manager, finished) = state, let runLoop, let manager, let finished else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            let current = lock.withLock { () -> [Entry] in
                let all = Array(entries.values)
                entries.removeAll()
                return all
            }
            for entry in current { tearDown(entry) }
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
        finished.wait()
        lock.withLock {
            running = false
            thread = nil
            self.finished = nil
        }
    }

    private func tearDown(_ entry: Entry) {
        IOHIDDeviceRegisterInputReportCallback(entry.device, entry.buffer, entry.bufferSize, nil, nil)
        IOHIDDeviceClose(entry.device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    // MARK: - Callbacks (HID thread)

    private func deviceMatched(_ device: IOHIDDevice) {
        guard let id = Self.registryID(of: device) else {
            logger.error("could not resolve the registry ID of a matched device; ignoring it")
            return
        }
        let info = Self.info(of: device)
        var seizeStatus: IOReturn = kIOReturnSuccess
        var status: IOReturn = kIOReturnUnsupported
        var mode = DeviceOpenMode.exclusive
        if preferExclusive {
            status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            seizeStatus = status
            if status != kIOReturnSuccess {
                if status == kIOReturnNotPermitted {
                    logger.error("input monitoring not granted")
                }
                logger.error("exclusive open of \(info.product, privacy: .public) failed: 0x\(String(UInt32(bitPattern: status), radix: 16), privacy: .public); falling back to shared")
            }
        }
        if status != kIOReturnSuccess {
            mode = .shared(seizeStatus: preferExclusive ? seizeStatus : kIOReturnUnsupported)
            status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        guard status == kIOReturnSuccess else {
            logger.error("open of \(info.product, privacy: .public) failed: 0x\(String(UInt32(bitPattern: status), radix: 16), privacy: .public)")
            sink(.openFailed(id: id, info: info, status: status))
            return
        }
        let entry = Entry(device: device, bufferSize: max(info.maxInputReportSize, 64), id: id, manager: self)
        let old = lock.withLock { entries.updateValue(entry, forKey: id) }
        if let old { tearDown(old) }
        let context = Unmanaged.passUnretained(entry).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, entry.buffer, entry.bufferSize, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let entry = Unmanaged<Entry>.fromOpaque(context).takeUnretainedValue()
            entry.manager?.deliver(entry: entry, reportID: UInt8(truncatingIfNeeded: reportID), report: report, length: length)
        }, context)
        logger.info("attached \(info.product, privacy: .public) serial \(info.serial, privacy: .public) mode \(mode.isExclusive ? "exclusive" : "shared", privacy: .public)")
        sink(.attached(id: id, info: info, mode: mode))
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        guard let id = Self.registryID(of: device) else { return }
        let entry = lock.withLock { entries.removeValue(forKey: id) }
        guard let entry else { return }
        tearDown(entry)
        logger.info("detached device \(id, privacy: .public)")
        sink(.detached(id: id))
    }

    private func deliver(entry: Entry, reportID: UInt8, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard length > 0 else { return }
        let timestamp = DispatchTime.now().uptimeNanoseconds
        let raw = Array(UnsafeBufferPointer(start: report, count: length))
        sink(.report(id: entry.id, reportID: reportID, raw: raw, timestamp: timestamp))
    }

    // MARK: - Properties

    private static func registryID(of device: IOHIDDevice) -> DeviceID? {
        var id: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        guard service != IO_OBJECT_NULL,
              IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { return nil }
        return id
    }

    private static func info(of device: IOHIDDevice) -> DeviceInfo {
        func int(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        func string(_ key: String) -> String {
            IOHIDDeviceGetProperty(device, key as CFString) as? String ?? ""
        }
        let descriptor = (IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data).map { [UInt8]($0) } ?? []
        return DeviceInfo(
            vendorID: int(kIOHIDVendorIDKey),
            productID: int(kIOHIDProductIDKey),
            manufacturer: string(kIOHIDManufacturerKey),
            product: string(kIOHIDProductKey),
            serial: string(kIOHIDSerialNumberKey),
            descriptor: descriptor,
            maxInputReportSize: int(kIOHIDMaxInputReportSizeKey)
        )
    }
}
