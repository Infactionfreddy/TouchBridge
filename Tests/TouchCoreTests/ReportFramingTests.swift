import Testing
@testable import TouchCore

@Suite struct ReportFramingTests {
    @Test func stripsLeadingReportID() throws {
        let layout = try Fixtures.elanLayout()
        let raw = [UInt8(1)] + ElanReport.payload(contacts: [.init(id: 1, x: 5, y: 5, down: true)], count: 1)
        #expect(ReportFraming.payload(from: raw, reportID: 1, layout: layout)?.count == 55)
        #expect(ReportFraming.payload(from: raw, reportID: 1, layout: layout)?.first == 0x41)
    }

    @Test func keepsPayloadWithoutReportID() throws {
        let layout = try Fixtures.elanLayout()
        let raw = ElanReport.payload(contacts: [.init(id: 1, x: 5, y: 5, down: true)], count: 1)   // first byte 0x41 ≠ 1
        #expect(ReportFraming.payload(from: raw, reportID: 1, layout: layout) == raw)
    }

    @Test func rejectsShortReports() throws {
        let layout = try Fixtures.elanLayout()
        #expect(ReportFraming.payload(from: [UInt8](repeating: 0, count: 10), reportID: 1, layout: layout) == nil)
    }

    @Test func layoutWithoutIDsNeverStrips() throws {
        let layout = try TouchScreenLayout(descriptor: HIDDescriptorParser().parse(SyntheticDescriptors.twoFingerNoReportID))
        let raw: [UInt8] = [0x00, 0x23, 0x01, 0x45, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01]
        #expect(ReportFraming.payload(from: raw, reportID: 0, layout: layout) == raw)
    }
}
