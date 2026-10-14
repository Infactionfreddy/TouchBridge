import Foundation

/// One contact as reported by the device, in digitizer units.
public struct RawContact: Equatable, Sendable {
    public var id: Int
    public var x: Int
    public var y: Int
    public var down: Bool

    public init(id: Int, x: Int, y: Int, down: Bool) {
        self.id = id
        self.x = x
        self.y = y
        self.down = down
    }
}

/// All contacts of one report (or of one merged hybrid-mode group).
public struct TouchFrame: Equatable, Sendable {
    /// Monotonic nanoseconds.
    public var timestamp: UInt64
    public var contacts: [RawContact]

    public init(timestamp: UInt64, contacts: [RawContact]) {
        self.timestamp = timestamp
        self.contacts = contacts
    }
}

/// Turns raw touch report payloads into `TouchFrame`s.
/// Parallel mode: every report carries all contacts and `contactCount` > 0 (or 0 when all lifted).
/// Hybrid mode: the first report carries `contactCount` = total and the first slots; follow-up reports
/// carry `contactCount` = 0 and the remaining slots until the total is reached.
public struct ReportDecoder: Sendable {
    public let layout: TouchScreenLayout
    private var pending: [RawContact] = []
    private var expected = 0

    public init(layout: TouchScreenLayout) {
        self.layout = layout
    }

    /// `payload` excludes the report ID byte. Returns nil for short payloads and incomplete hybrid groups.
    public mutating func decode(payload: [UInt8], timestamp: UInt64) -> TouchFrame? {
        guard payload.count >= layout.payloadByteCount else { return nil }
        let reported = Int(Self.value(of: layout.contactCount, in: payload))
        if reported > 0 {
            pending = []
            expected = reported
        } else if expected == 0 {
            return TouchFrame(timestamp: timestamp, contacts: [])
        }

        let remaining = expected - pending.count
        for slot in layout.slots.prefix(max(remaining, 0)) {
            let id = slot.contactID.map { Int(Self.value(of: $0, in: payload)) } ?? pending.count
            pending.append(RawContact(
                id: id,
                x: Int(Self.value(of: slot.x, in: payload)),
                y: Int(Self.value(of: slot.y, in: payload)),
                down: Self.value(of: slot.tipSwitch, in: payload) != 0
            ))
        }

        if pending.count >= expected {
            let frame = TouchFrame(timestamp: timestamp, contacts: pending)
            pending = []
            expected = 0
            return frame
        }
        return nil
    }

    /// Little-endian bit field extraction.
    static func value(of field: HIDField, in bytes: [UInt8]) -> UInt32 {
        var value: UInt32 = 0
        for bit in 0..<field.bitSize {
            let absolute = field.bitOffset + bit
            let byte = bytes[absolute / 8]
            let b = (byte >> UInt8(absolute % 8)) & 1
            value |= UInt32(b) << UInt32(bit)
        }
        return value
    }
}
