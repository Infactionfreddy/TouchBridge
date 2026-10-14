import Testing
import Foundation
@testable import TouchCore

@Suite struct SettingsStoreTests {
    func temporaryStore() throws -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TouchBridgeTests-\(UUID().uuidString)")
        return SettingsStore(directory: dir)
    }

    @Test func missingFileYieldsDefaultsWithoutCreatingIt() throws {
        let store = try temporaryStore()
        #expect(store.load() == Settings())
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test func roundTrip() throws {
        let store = try temporaryStore()
        var s = Settings()
        s.enabled = false
        s.displaySelection = .display(uuid: "ABC-123")
        s.naturalScrolling = false
        s.gesture.tapMaxMovement = 11
        s.calibrations["20231224X1"] = Calibration(orientation: 90, scaleX: 1, scaleY: 1, offsetX: 0.01, offsetY: 0)
        s.launchAtLogin = true
        try store.save(s)
        #expect(store.load() == s)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 1"))
    }

    @Test func partialFileGetsDefaults() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{\"enabled\": false}".utf8).write(to: store.fileURL)
        let s = store.load()
        #expect(s.enabled == false)
        #expect(s.naturalScrolling == true)
        #expect(s.gesture == GestureConfig())
        #expect(s.displaySelection == .auto)
    }

    @Test func brokenFileIsSetAsideAndDefaultsReturned() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)
        #expect(store.load() == Settings())
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path + ".broken"))
    }

    @Test func defaultDirectoryIsApplicationSupport() {
        let url = SettingsStore.defaultDirectory()
        #expect(url.path.hasSuffix("/Library/Application Support/TouchBridge"))
    }
}
