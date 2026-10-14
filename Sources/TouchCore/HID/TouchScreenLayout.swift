import Foundation

/// The fields of one finger (one Finger logical collection) inside the touch report.
public struct FingerSlot: Equatable, Sendable {
    public var contactID: HIDField?
    public var tipSwitch: HIDField
    public var x: HIDField
    public var y: HIDField
    public var inRange: HIDField?
    public var confidence: HIDField?
}

/// Where the touch data lives inside the device's input report.
public struct TouchScreenLayout: Equatable, Sendable {
    public enum LayoutError: Error, Equatable {
        case noTouchScreenCollection
        case missingContactCount
        case noFingerSlots
        case slotIncomplete(index: Int)
    }

    public var reportID: UInt8
    public var usesReportIDs: Bool
    public var slots: [FingerSlot]
    public var contactCount: HIDField
    public var scanTime: HIDField?
    public var logicalMaxX: Int
    public var logicalMaxY: Int
    /// Bytes of the input report payload, report ID byte excluded.
    public var payloadByteCount: Int

    public init(descriptor: HIDDescriptor) throws {
        let touchFields = descriptor.fields.filter { field in
            field.kind == .input
                && field.collections.contains { $0.usage == .touchScreen && $0.type == 1 }
        }
        guard !touchFields.isEmpty else { throw LayoutError.noTouchScreenCollection }
        guard let count = touchFields.first(where: { $0.usage == .contactCount }) else {
            throw LayoutError.missingContactCount
        }
        let reportFields = touchFields.filter { $0.reportID == count.reportID }

        var groups: [Int: [HIDField]] = [:]
        var order: [Int] = []
        for field in reportFields {
            guard let finger = field.collections.last(where: { $0.usage == .finger }) else { continue }
            if groups[finger.index] == nil { order.append(finger.index) }
            groups[finger.index, default: []].append(field)
        }
        guard !order.isEmpty else { throw LayoutError.noFingerSlots }

        var slots: [FingerSlot] = []
        for (index, collectionIndex) in order.enumerated() {
            let group = groups[collectionIndex] ?? []
            guard let tip = group.first(where: { $0.usage == .tipSwitch }),
                  let x = group.first(where: { $0.usage == .x }),
                  let y = group.first(where: { $0.usage == .y }) else {
                throw LayoutError.slotIncomplete(index: index)
            }
            slots.append(FingerSlot(
                contactID: group.first { $0.usage == .contactIdentifier },
                tipSwitch: tip, x: x, y: y,
                inRange: group.first { $0.usage == .inRange },
                confidence: group.first { $0.usage == .confidence }
            ))
        }

        let lastBit = reportFields.map { $0.bitOffset + $0.bitSize }.max() ?? 0
        self.reportID = count.reportID
        self.usesReportIDs = descriptor.usesReportIDs
        self.slots = slots
        self.contactCount = count
        self.scanTime = reportFields.first { $0.usage == .scanTime }
        self.logicalMaxX = slots[0].x.logicalMax
        self.logicalMaxY = slots[0].y.logicalMax
        self.payloadByteCount = (lastBit + 7) / 8
    }
}
