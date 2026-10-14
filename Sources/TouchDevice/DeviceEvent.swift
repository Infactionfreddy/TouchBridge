import Foundation
import TouchCore

/// IORegistry entry ID of the HID device; stable while the device stays attached.
public typealias DeviceID = UInt64

public struct DeviceInfo: Equatable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var manufacturer: String
    public var product: String
    public var serial: String
    public var descriptor: [UInt8]
    public var maxInputReportSize: Int

    public init(vendorID: Int, productID: Int, manufacturer: String, product: String, serial: String,
                descriptor: [UInt8], maxInputReportSize: Int) {
        self.vendorID = vendorID
        self.productID = productID
        self.manufacturer = manufacturer
        self.product = product
        self.serial = serial
        self.descriptor = descriptor
        self.maxInputReportSize = maxInputReportSize
    }
}

public enum DeviceOpenMode: Sendable, Equatable {
    case exclusive, shared
}

public enum DeviceEvent: Sendable {
    case attached(id: DeviceID, info: DeviceInfo, mode: DeviceOpenMode)
    case openFailed(id: DeviceID, info: DeviceInfo, status: Int32)
    /// `raw` is the report exactly as IOKit delivered it (report ID byte included when the device uses IDs).
    case report(id: DeviceID, reportID: UInt8, raw: [UInt8], timestamp: UInt64)
    case detached(id: DeviceID)
}
