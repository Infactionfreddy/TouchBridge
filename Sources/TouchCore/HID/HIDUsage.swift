import Foundation

/// A HID usage: usage page plus usage ID (USB HID Usage Tables).
public struct HIDUsage: Hashable, Sendable {
    public var page: UInt16
    public var id: UInt16

    public init(page: UInt16, id: UInt16) {
        self.page = page
        self.id = id
    }

    public static let genericDesktopPage: UInt16 = 0x01
    public static let digitizerPage: UInt16 = 0x0D

    public static let x = HIDUsage(page: 0x01, id: 0x30)
    public static let y = HIDUsage(page: 0x01, id: 0x31)

    public static let touchScreen = HIDUsage(page: 0x0D, id: 0x04)
    public static let finger = HIDUsage(page: 0x0D, id: 0x22)
    public static let inRange = HIDUsage(page: 0x0D, id: 0x32)
    public static let tipSwitch = HIDUsage(page: 0x0D, id: 0x42)
    public static let confidence = HIDUsage(page: 0x0D, id: 0x47)
    public static let contactIdentifier = HIDUsage(page: 0x0D, id: 0x51)
    public static let contactCount = HIDUsage(page: 0x0D, id: 0x54)
    public static let contactCountMaximum = HIDUsage(page: 0x0D, id: 0x55)
    public static let scanTime = HIDUsage(page: 0x0D, id: 0x56)
}
