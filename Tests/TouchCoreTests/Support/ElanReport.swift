enum ElanReport {
    struct Slot {
        var id: Int
        var x: Int
        var y: Int
        var down: Bool
    }

    /// Builds the 55-byte payload of Elan report 1 (report ID byte excluded).
    /// Slot layout: byte 0 = contact id (bits 0-5) | tip (bit 6); x LE u16; y LE u16.
    static func payload(contacts: [Slot], count: Int, scanTime: UInt32 = 0) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 55)
        for (i, c) in contacts.prefix(10).enumerated() {
            let base = i * 5
            p[base] = UInt8(c.id & 0x3F) | (c.down ? 0x40 : 0)
            p[base + 1] = UInt8(c.x & 0xFF)
            p[base + 2] = UInt8((c.x >> 8) & 0xFF)
            p[base + 3] = UInt8(c.y & 0xFF)
            p[base + 4] = UInt8((c.y >> 8) & 0xFF)
        }
        p[50] = UInt8(scanTime & 0xFF)
        p[51] = UInt8((scanTime >> 8) & 0xFF)
        p[52] = UInt8((scanTime >> 16) & 0xFF)
        p[53] = UInt8((scanTime >> 24) & 0xFF)
        p[54] = UInt8(count)
        return p
    }
}
