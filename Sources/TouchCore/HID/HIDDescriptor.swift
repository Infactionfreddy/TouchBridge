import Foundation

public enum HIDReportKind: Sendable, Equatable {
    case input, output, feature
}

/// A collection in the descriptor. `index` is unique per descriptor, in order of appearance.
public struct HIDCollection: Hashable, Sendable {
    public var index: Int
    public var usage: HIDUsage
    /// 0 physical, 1 application, 2 logical, 3 report, 4 named array, 5 usage switch, 6 usage modifier
    public var type: UInt8

    public init(index: Int, usage: HIDUsage, type: UInt8) {
        self.index = index
        self.usage = usage
        self.type = type
    }
}

/// One report field (one element of a Report Count group).
public struct HIDField: Equatable, Sendable {
    public var kind: HIDReportKind
    /// 0 when the descriptor does not use report IDs.
    public var reportID: UInt8
    public var usage: HIDUsage
    /// Bit offset inside the report payload, report ID byte excluded.
    public var bitOffset: Int
    public var bitSize: Int
    public var logicalMin: Int
    public var logicalMax: Int
    public var isConstant: Bool
    /// Enclosing collections, outermost first.
    public var collections: [HIDCollection]

    public init(kind: HIDReportKind, reportID: UInt8, usage: HIDUsage, bitOffset: Int, bitSize: Int,
                logicalMin: Int, logicalMax: Int, isConstant: Bool, collections: [HIDCollection]) {
        self.kind = kind
        self.reportID = reportID
        self.usage = usage
        self.bitOffset = bitOffset
        self.bitSize = bitSize
        self.logicalMin = logicalMin
        self.logicalMax = logicalMax
        self.isConstant = isConstant
        self.collections = collections
    }
}

public struct HIDDescriptor: Equatable, Sendable {
    public var fields: [HIDField]
    public var usesReportIDs: Bool

    public init(fields: [HIDField], usesReportIDs: Bool) {
        self.fields = fields
        self.usesReportIDs = usesReportIDs
    }
}

public enum HIDDescriptorError: Error, Equatable {
    case truncatedItem(offset: Int)
    case longItemUnsupported(offset: Int)
    case unsupportedGlobalItem(tag: UInt8, offset: Int)
    case unbalancedCollection(offset: Int)
}

/// Parses the short-item subset of the HID 1.11 report descriptor format that touch screens use.
/// Supported: Input/Output/Feature/Collection/End Collection; Usage Page, Logical Min/Max,
/// Report Size/ID/Count; Usage, Usage Minimum/Maximum. Physical range and units are skipped.
/// Push/Pop and long items are rejected.
public struct HIDDescriptorParser: Sendable {
    public init() {}

    private struct Globals {
        var usagePage: UInt16 = 0
        var logicalMin = 0
        var logicalMax = 0
        var reportSize = 0
        var reportID: UInt8 = 0
        var reportCount = 0
    }

    private struct Locals {
        var usages: [HIDUsage] = []
        var usageMin: HIDUsage?
    }

    private struct OffsetKey: Hashable {
        var kind: HIDReportKind
        var reportID: UInt8
    }

    public func parse(_ bytes: [UInt8]) throws -> HIDDescriptor {
        var globals = Globals()
        var locals = Locals()
        var stack: [HIDCollection] = []
        var nextCollectionIndex = 0
        var fields: [HIDField] = []
        var offsets: [OffsetKey: Int] = [:]
        var usesReportIDs = false
        var i = 0

        while i < bytes.count {
            let prefix = bytes[i]
            if prefix == 0xFE { throw HIDDescriptorError.longItemUnsupported(offset: i) }
            let sizeCode = Int(prefix & 0x03)
            let size = sizeCode == 3 ? 4 : sizeCode
            let type = (prefix >> 2) & 0x03
            let tag = prefix >> 4
            guard i + 1 + size <= bytes.count else { throw HIDDescriptorError.truncatedItem(offset: i) }

            var raw: UInt32 = 0
            for b in 0..<size { raw |= UInt32(bytes[i + 1 + b]) << (8 * b) }
            let signed: Int
            switch size {
            case 1: signed = Int(Int8(truncatingIfNeeded: raw))
            case 2: signed = Int(Int16(truncatingIfNeeded: raw))
            case 4: signed = Int(Int32(truncatingIfNeeded: raw))
            default: signed = 0
            }

            switch type {
            case 1: // global
                switch tag {
                case 0x0: globals.usagePage = UInt16(raw & 0xFFFF)
                case 0x1: globals.logicalMin = signed
                case 0x2:
                    // A non-negative minimum lets the maximum be read unsigned (e.g. 25 FF = 255).
                    globals.logicalMax = (globals.logicalMin >= 0 && signed < 0) ? Int(raw) : signed
                case 0x3, 0x4, 0x5, 0x6: break // physical min/max, unit exponent, unit
                case 0x7: globals.reportSize = Int(raw)
                case 0x8:
                    globals.reportID = UInt8(raw & 0xFF)
                    usesReportIDs = true
                case 0x9: globals.reportCount = Int(raw)
                default: throw HIDDescriptorError.unsupportedGlobalItem(tag: tag, offset: i)
                }
            case 2: // local
                switch tag {
                case 0x0: locals.usages.append(Self.usage(raw, size: size, page: globals.usagePage))
                case 0x1: locals.usageMin = Self.usage(raw, size: size, page: globals.usagePage)
                case 0x2:
                    let max = Self.usage(raw, size: size, page: globals.usagePage)
                    if let min = locals.usageMin, min.id <= max.id {
                        for id in min.id...max.id { locals.usages.append(HIDUsage(page: min.page, id: id)) }
                    }
                    locals.usageMin = nil
                default: break // designators, strings, delimiters
                }
            case 0: // main
                switch tag {
                case 0xA:
                    let usage = locals.usages.first ?? HIDUsage(page: globals.usagePage, id: 0)
                    stack.append(HIDCollection(index: nextCollectionIndex, usage: usage, type: UInt8(raw & 0xFF)))
                    nextCollectionIndex += 1
                    locals = Locals()
                case 0xC:
                    guard !stack.isEmpty else { throw HIDDescriptorError.unbalancedCollection(offset: i) }
                    stack.removeLast()
                    locals = Locals()
                case 0x8, 0x9, 0xB:
                    let kind: HIDReportKind = tag == 0x8 ? .input : (tag == 0x9 ? .output : .feature)
                    let key = OffsetKey(kind: kind, reportID: globals.reportID)
                    var offset = offsets[key, default: 0]
                    let isConstant = (raw & 0x1) != 0
                    for n in 0..<globals.reportCount {
                        let usage: HIDUsage
                        if locals.usages.isEmpty {
                            usage = HIDUsage(page: globals.usagePage, id: 0)
                        } else {
                            usage = locals.usages[min(n, locals.usages.count - 1)]
                        }
                        fields.append(HIDField(kind: kind, reportID: globals.reportID, usage: usage,
                                               bitOffset: offset, bitSize: globals.reportSize,
                                               logicalMin: globals.logicalMin, logicalMax: globals.logicalMax,
                                               isConstant: isConstant, collections: stack))
                        offset += globals.reportSize
                    }
                    offsets[key] = offset
                    locals = Locals()
                default: break
                }
            default: break // reserved
            }
            i += 1 + size
        }
        guard stack.isEmpty else { throw HIDDescriptorError.unbalancedCollection(offset: bytes.count) }
        return HIDDescriptor(fields: fields, usesReportIDs: usesReportIDs)
    }

    /// A 4-byte usage item carries the page in its upper 16 bits (extended usage).
    private static func usage(_ raw: UInt32, size: Int, page: UInt16) -> HIDUsage {
        if size == 4 {
            return HIDUsage(page: UInt16(raw >> 16), id: UInt16(raw & 0xFFFF))
        }
        return HIDUsage(page: page, id: UInt16(raw & 0xFFFF))
    }
}
