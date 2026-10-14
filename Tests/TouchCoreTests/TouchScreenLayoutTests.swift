import Testing
@testable import TouchCore

@Suite struct TouchScreenLayoutTests {
    @Test func elanLayoutHasTenSlots() throws {
        let layout = try Fixtures.elanLayout()
        #expect(layout.reportID == 1)
        #expect(layout.usesReportIDs)
        #expect(layout.slots.count == 10)
        #expect(layout.slots[0].contactID?.bitOffset == 0)
        #expect(layout.slots[0].tipSwitch.bitOffset == 6)
        #expect(layout.slots[0].x.bitOffset == 8)
        #expect(layout.slots[0].y.bitOffset == 24)
        #expect(layout.slots[9].x.bitOffset == 9 * 40 + 8)
        #expect(layout.slots[0].inRange == nil)
        #expect(layout.contactCount.bitOffset == 432)
        #expect(layout.scanTime?.bitOffset == 400)
        #expect(layout.logicalMaxX == 2976)
        #expect(layout.logicalMaxY == 1680)
        #expect(layout.payloadByteCount == 55)
    }

    @Test func syntheticLayoutWithoutReportIDs() throws {
        let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(SyntheticDescriptors.twoFingerNoReportID))
        #expect(layout.reportID == 0)
        #expect(!layout.usesReportIDs)
        #expect(layout.slots.count == 2)
        #expect(layout.slots[0].tipSwitch.bitOffset == 0)
        #expect(layout.slots[0].contactID?.bitOffset == 1)
        #expect(layout.slots[1].tipSwitch.bitOffset == 40)
        #expect(layout.contactCount.bitOffset == 80)
        #expect(layout.scanTime == nil)
        #expect(layout.logicalMaxX == 1023)
        #expect(layout.payloadByteCount == 11)
    }

    @Test func errors() throws {
        let parser = HIDDescriptorParser()
        #expect(throws: TouchScreenLayout.LayoutError.noTouchScreenCollection) {
            try TouchScreenLayout(descriptor: parser.parse(SyntheticDescriptors.mouseOnly))
        }
        #expect(throws: TouchScreenLayout.LayoutError.missingContactCount) {
            try TouchScreenLayout(descriptor: parser.parse(SyntheticDescriptors.fingerWithoutContactCount))
        }
        #expect(throws: TouchScreenLayout.LayoutError.slotIncomplete(index: 0)) {
            try TouchScreenLayout(descriptor: parser.parse(SyntheticDescriptors.fingerWithoutY))
        }
    }
}
