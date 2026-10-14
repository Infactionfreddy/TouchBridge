import Testing
@testable import TouchCore

@Suite struct ReportDecoderTests {
    @Test func decodesTwoContacts() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let payload = ElanReport.payload(contacts: [
            .init(id: 0, x: 1000, y: 500, down: true),
            .init(id: 1, x: 2000, y: 800, down: true),
        ], count: 2, scanTime: 42)
        let frame = decoder.decode(payload: payload, timestamp: 5)
        #expect(frame == TouchFrame(timestamp: 5, contacts: [
            RawContact(id: 0, x: 1000, y: 500, down: true),
            RawContact(id: 1, x: 2000, y: 800, down: true),
        ]))
    }

    @Test func zeroCountIsEmptyFrame() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let frame = decoder.decode(payload: ElanReport.payload(contacts: [], count: 0), timestamp: 1)
        #expect(frame == TouchFrame(timestamp: 1, contacts: []))
    }

    @Test func liftIsReportedWithDownFalse() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let payload = ElanReport.payload(contacts: [.init(id: 3, x: 10, y: 20, down: false)], count: 1)
        #expect(decoder.decode(payload: payload, timestamp: 1)?.contacts == [RawContact(id: 3, x: 10, y: 20, down: false)])
    }

    @Test func decodesTenContacts() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let slots = (0..<10).map { ElanReport.Slot(id: $0, x: $0 * 100, y: $0 * 50, down: true) }
        let frame = decoder.decode(payload: ElanReport.payload(contacts: slots, count: 10), timestamp: 1)
        #expect(frame?.contacts.count == 10)
        #expect(frame?.contacts[9] == RawContact(id: 9, x: 900, y: 450, down: true))
    }

    @Test func shortPayloadIsIgnored() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        #expect(decoder.decode(payload: [UInt8](repeating: 0, count: 10), timestamp: 1) == nil)
    }

    @Test func hybridReportsAreMerged() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let first = (0..<10).map { ElanReport.Slot(id: $0, x: $0, y: 0, down: true) }
        let second = [ElanReport.Slot(id: 10, x: 10, y: 0, down: true), ElanReport.Slot(id: 11, x: 11, y: 0, down: true)]
        #expect(decoder.decode(payload: ElanReport.payload(contacts: first, count: 12), timestamp: 1) == nil)
        let frame = decoder.decode(payload: ElanReport.payload(contacts: second, count: 0), timestamp: 2)
        #expect(frame?.timestamp == 2)
        #expect(frame?.contacts.count == 12)
        #expect(frame?.contacts.map(\.id) == Array(0..<12))
    }

    @Test func staleHybridPendingIsDiscardedByNewCount() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let first = (0..<10).map { ElanReport.Slot(id: $0, x: $0, y: 0, down: true) }
        #expect(decoder.decode(payload: ElanReport.payload(contacts: first, count: 12), timestamp: 1) == nil)
        let fresh = decoder.decode(payload: ElanReport.payload(contacts: [.init(id: 4, x: 7, y: 8, down: true)], count: 1), timestamp: 2)
        #expect(fresh == TouchFrame(timestamp: 2, contacts: [RawContact(id: 4, x: 7, y: 8, down: true)]))
    }

    @Test func decodesLayoutWithoutReportIDs() throws {
        let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(SyntheticDescriptors.twoFingerNoReportID))
        var decoder = ReportDecoder(layout: layout)
        // finger 0: tip 1, id 5 → byte0 = 0b0000_1011 = 0x0B; x = 0x0123, y = 0x0045
        // finger 1: tip 0, id 0 → 0x00; x = 0, y = 0; count = 1
        let payload: [UInt8] = [0x0B, 0x23, 0x01, 0x45, 0x00,
                                0x00, 0x00, 0x00, 0x00, 0x00,
                                0x01]
        let frame = decoder.decode(payload: payload, timestamp: 9)
        #expect(frame == TouchFrame(timestamp: 9, contacts: [RawContact(id: 5, x: 0x123, y: 0x45, down: true)]))
    }

    @Test func oversizedCountIsDroppedAndDoesNotLatch() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let tenSlots = (0..<10).map { ElanReport.Slot(id: $0, x: $0, y: 0, down: true) }
        #expect(decoder.decode(payload: ElanReport.payload(contacts: tenSlots, count: 255), timestamp: 1) == nil)
        #expect(decoder.decode(payload: ElanReport.payload(contacts: [], count: 0), timestamp: 2) == TouchFrame(timestamp: 2, contacts: []))
    }

    @Test func staleHybridGroupIsDroppedOnTimeout() throws {
        var decoder = ReportDecoder(layout: try Fixtures.elanLayout())
        let tenSlots = (0..<10).map { ElanReport.Slot(id: $0, x: $0, y: 0, down: true) }
        #expect(decoder.decode(payload: ElanReport.payload(contacts: tenSlots, count: 12), timestamp: 1_000_000) == nil)
        #expect(decoder.decode(payload: ElanReport.payload(contacts: [], count: 0), timestamp: 201_000_000) == TouchFrame(timestamp: 201_000_000, contacts: []))
    }
}
