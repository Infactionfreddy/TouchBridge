import Testing
@testable import TouchInject

@Suite struct SmokeTests {
    @Test func moduleLinks() {
        _ = TouchInjectPlaceholder.self
    }
}
