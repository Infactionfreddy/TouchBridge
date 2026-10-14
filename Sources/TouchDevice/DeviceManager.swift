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
    private let lock = NSLock()
    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var entries: [DeviceID: Entry] = [:]

    public init(preferExclusive: Bool = true, sink: @escaping Sink) {
        self.preferExclusive = preferExclusive
        self.sink = sink
    }

    public func start() {
        let thread = Thread { [self] in
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = manager
            self.runLoop = CFRunLoopGetCurrent()
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
            CFRunLoopRun()
            self.logger.info("HID thread finished")
        }
        thread.name = "org.touchbridge.hid"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    public func stop() {
        guard let runLoop, let manager else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in
            let current = lock.withLock { entries }
            for (_, entry) in current {
                IOHIDDeviceRegisterInputReportCallback(entry.device, entry.buffer, entry.bufferSize, nil, nil)
                IOHIDDeviceClose(entry.device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            lock.withLock { entries.removeAll() }
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
        self.runLoop = nil
        self.manager = nil
    }

    // MARK: - Callbacks (HID thread)

    private func deviceMatched(_ device: IOHIDDevice) {
        let id = Self.registryID(of: device)
        let info = Self.info(of: device)
        var mode = DeviceOpenMode.exclusive
        var status: IOReturn = kIOReturnUnsupported
        if preferExclusive {
            status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if status != kIOReturnSuccess {
                logger.error("exclusive open of \(info.product, privacy: .public) failed: 0x\(String(UInt32(bitPattern: status), radix: 16), privacy: .public); falling back to shared")
            }
        }
        if status != kIOReturnSuccess {
            mode = .shared
            status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        guard status == kIOReturnSuccess else {
            logger.error("open of \(info.product, privacy: .public) failed: 0x\(String(UInt32(bitPattern: status), radix: 16), privacy: .public)")
            sink(.openFailed(id: id, info: info, status: status))
            return
        }
        let entry = Entry(device: device, bufferSize: max(info.maxInputReportSize, 64), id: id, manager: self)
        lock.withLock { entries[id] = entry }
        let context = Unmanaged.passUnretained(entry).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, entry.buffer, entry.bufferSize, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let entry = Unmanaged<Entry>.fromOpaque(context).takeUnretainedValue()
            entry.manager?.deliver(entry: entry, reportID: UInt8(truncatingIfNeeded: reportID), report: report, length: length)
        }, context)
        logger.info("attached \(info.product, privacy: .public) serial \(info.serial, privacy: .public) mode \(mode == .exclusive ? "exclusive" : "shared", privacy: .public)")
        sink(.attached(id: id, info: info, mode: mode))
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let id = Self.registryID(of: device)
        let entry = lock.withLock { entries.removeValue(forKey: id) }
        guard let entry else { return }
        IOHIDDeviceRegisterInputReportCallback(entry.device, entry.buffer, entry.bufferSize, nil, nil)
        IOHIDDeviceClose(entry.device, IOOptionBits(kIOHIDOptionsTypeNone))
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

    private static func registryID(of device: IOHIDDevice) -> DeviceID {
        var id: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        if service != IO_OBJECT_NULL {
            IORegistryEntryGetRegistryEntryID(service, &id)
        }
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
