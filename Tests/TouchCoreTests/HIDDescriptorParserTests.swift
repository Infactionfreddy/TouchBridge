import Testing
@testable import TouchCore

@Suite struct HIDDescriptorParserTests {
    @Test func parsesElanInputFieldsOfReportOne() throws {
        let d = try HIDDescriptorParser().parse(try Fixtures.elanDescriptorBytes())
        #expect(d.usesReportIDs)
        let report1 = d.fields.filter { $0.kind == .input && $0.reportID == 1 }
        #expect(report1.count == 52)   // 10 × (id, tip, pad, x, y) + scan time + contact count

        let first = report1[0]
        #expect(first.usage == .contactIdentifier)
        #expect(first.bitOffset == 0)
        #expect(first.bitSize == 6)
        #expect(first.logicalMax == 63)

        let tip = report1[1]
        #expect(tip.usage == .tipSwitch)
        #expect(tip.bitOffset == 6)
        #expect(tip.bitSize == 1)

        let pad = report1[2]
        #expect(pad.isConstant)
        #expect(pad.bitOffset == 7)

        let x = report1[3]
        #expect(x.usage == .x)
        #expect(x.bitOffset == 8)
        #expect(x.bitSize == 16)
        #expect(x.logicalMax == 2976)

        let y = report1[4]
        #expect(y.usage == .y)
        #expect(y.bitOffset == 24)
        #expect(y.logicalMax == 1680)

        let secondFingerID = report1[5]
        #expect(secondFingerID.usage == .contactIdentifier)
        #expect(secondFingerID.bitOffset == 40)

        let scan = report1[50]
        #expect(scan.usage == .scanTime)
        #expect(scan.bitOffset == 400)
        #expect(scan.bitSize == 32)
        #expect(scan.logicalMax == 0x7FFF_FFFF)

        let count = report1[51]
        #expect(count.usage == .contactCount)
        #expect(count.bitOffset == 432)
        #expect(count.bitSize == 8)
        #expect(count.logicalMax == 127)
    }

    @Test func fingerCollectionsAreDistinct() throws {
        let d = try HIDDescriptorParser().parse(try Fixtures.elanDescriptorBytes())
        let tips = d.fields.filter { $0.kind == .input && $0.reportID == 1 && $0.usage == .tipSwitch }
        let fingerIndices = tips.compactMap { $0.collections.last(where: { $0.usage == .finger })?.index }
        #expect(fingerIndices.count == 10)
        #expect(Set(fingerIndices).count == 10)
        #expect(tips.allSatisfy { $0.collections.first?.usage == .touchScreen })
    }

    @Test func parsesFeatureAndOtherReports() throws {
        let d = try HIDDescriptorParser().parse(try Fixtures.elanDescriptorBytes())
        let max = d.fields.first { $0.kind == .feature && $0.reportID == 2 }
        #expect(max?.usage == .contactCountMaximum)
        #expect(max?.logicalMax == 10)
        let blob = d.fields.filter { $0.kind == .feature && $0.reportID == 3 }
        #expect(blob.count == 256)
        let mouseButtons = d.fields.filter { $0.kind == .input && $0.reportID == 7 && $0.usage.page == 0x09 && !$0.isConstant }
        #expect(mouseButtons.map(\.usage.id) == [1, 2, 3])
        let wheel = d.fields.first { $0.kind == .input && $0.reportID == 7 && $0.usage == HIDUsage(page: 0x01, id: 0x38) }
        #expect(wheel?.logicalMin == -127)
        #expect(wheel?.logicalMax == 127)
    }

    @Test func descriptorWithoutReportIDsStartsAtOffsetZero() throws {
        // Usage Page Generic Desktop, Usage Mouse, Collection App, Usage X, Usage Y,
        // Logical Min -127, Logical Max 127, Report Size 8, Report Count 2, Input (Data,Var,Rel), End
        let bytes: [UInt8] = [0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x09, 0x30, 0x09, 0x31,
                              0x15, 0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x02, 0x81, 0x06, 0xC0]
        let d = try HIDDescriptorParser().parse(bytes)
        #expect(!d.usesReportIDs)
        #expect(d.fields.count == 2)
        #expect(d.fields[0].usage == .x)
        #expect(d.fields[0].bitOffset == 0)
        #expect(d.fields[1].usage == .y)
        #expect(d.fields[1].bitOffset == 8)
        #expect(d.fields[0].reportID == 0)
    }

    @Test func unsignedLogicalMaxWhenMinIsNonNegative() throws {
        // Logical Min 0, Logical Max 0xFF encoded in one byte: must read as 255, not -1
        let bytes: [UInt8] = [0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x09, 0x30,
                              0x15, 0x00, 0x25, 0xFF, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02, 0xC0]
        let d = try HIDDescriptorParser().parse(bytes)
        #expect(d.fields[0].logicalMax == 255)
    }

    @Test func rejectsLongItemsAndPushPop() {
        #expect(throws: HIDDescriptorError.longItemUnsupported(offset: 0)) {
            try HIDDescriptorParser().parse([0xFE, 0x00, 0x00])
        }
        #expect(throws: HIDDescriptorError.unsupportedGlobalItem(tag: 0xA, offset: 0)) {
            try HIDDescriptorParser().parse([0xA4])   // Push
        }
    }

    @Test func rejectsUnbalancedCollections() {
        #expect(throws: HIDDescriptorError.unbalancedCollection(offset: 0)) {
            try HIDDescriptorParser().parse([0xC0])
        }
        #expect(throws: HIDDescriptorError.unbalancedCollection(offset: 2)) {
            try HIDDescriptorParser().parse([0xA1, 0x01])
        }
    }

    @Test func rejectsTruncatedItem() {
        #expect(throws: HIDDescriptorError.truncatedItem(offset: 0)) {
            try HIDDescriptorParser().parse([0x26, 0xA0])   // 2-byte item, only one data byte
        }
    }

    @Test func rejectsHugeReportCount() {
        // Report Count 0xFFFFFFFF (item at offset 10) would expand into billions of fields.
        let bytes: [UInt8] = [0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x09, 0x30, 0x75, 0x08, 0x97, 0xFF, 0xFF, 0xFF, 0xFF,
                              0x81, 0x02, 0xC0]
        #expect(throws: HIDDescriptorError.limitExceeded(offset: 10)) {
            try HIDDescriptorParser().parse(bytes)
        }
    }

    @Test func rejectsHugeReportSize() {
        #expect(throws: HIDDescriptorError.limitExceeded(offset: 0)) {
            try HIDDescriptorParser().parse([0x77, 0xFF, 0xFF, 0xFF, 0xFF])   // Report Size 0xFFFFFFFF
        }
    }

    @Test func rejectsHugeUsageRange() {
        #expect(throws: HIDDescriptorError.limitExceeded(offset: 2)) {
            try HIDDescriptorParser().parse([0x19, 0x00, 0x2A, 0xFF, 0xFF])   // Usage Min 0 .. Usage Max 0xFFFF
        }
    }
}
