import Testing
@testable import TouchCore

@Suite struct FixtureTests {
    @Test func elanDescriptorLoads() throws {
        let bytes = try Fixtures.elanDescriptorBytes()
        #expect(bytes.count == 849)
        #expect(bytes.first == 0x05)
        #expect(bytes.last == 0xC0)
    }
}
