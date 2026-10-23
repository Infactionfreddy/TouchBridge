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
        s.defaultProfile.config.tapMaxMovement = 11
        var safariConfig = GestureConfigOverrides()
        safariConfig.longPressDuration = 1
        s.upsert(GestureProfile(bundleID: "com.apple.Safari", displayName: "Safari",
                                bindings: [.threeFingerSwipeLeft: GestureBinding(action: .keystroke(key: KeyCommand(keyCode: 33, command: true)))],
                                config: safariConfig))
        s.calibrations["20231224X1"] = Calibration(orientation: 90, scaleX: 1, scaleY: 1, offsetX: 0.01, offsetY: 0)
        s.launchAtLogin = true
        try store.save(s)
        #expect(store.load() == s)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(!text.contains("\"gesture\" :"))
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path + ".v1"))
    }

    @Test func partialFileGetsDefaults() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{\"enabled\": false}".utf8).write(to: store.fileURL)
        let s = store.load()
        #expect(s.enabled == false)
        #expect(s.naturalScrolling == true)
        #expect(s.defaultProfile == GestureProfile())
        #expect(s.appProfiles.isEmpty)
        #expect(s.displaySelection == .auto)
    }

    @Test func brokenFileIsSetAsideAndDefaultsReturned() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.fileURL)
        #expect(store.load() == Settings())
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(store.load() == Settings())
        let broken = URL(fileURLWithPath: store.fileURL.path + ".broken")
        #expect(FileManager.default.fileExists(atPath: broken.path))
        #expect(try String(contentsOf: broken, encoding: .utf8) == "{not json")
    }

    @Test func newerSchemaVersionIsNormalizedOnSave() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{\"schemaVersion\": 7, \"enabled\": false}".utf8).write(to: store.fileURL)
        let loaded = store.load()
        #expect(loaded.enabled == false)
        #expect(loaded.schemaVersion == 2)
        try store.save(loaded)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 2"))
        let backup = URL(fileURLWithPath: store.fileURL.path + ".v7")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "{\"schemaVersion\": 7, \"enabled\": false}")
    }

    @Test func legacySchemaOneFileIsMigratedAndBackedUp() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let legacy = """
        {"schemaVersion":1,"enabled":true,"naturalScrolling":false,
         "gesture":{"longPressDuration":0.9,"tapMaxMovement":12},
         "calibrations":{"X":{"orientation":90}},"launchAtLogin":true}
        """
        try Data(legacy.utf8).write(to: store.fileURL)
        let s = store.load()
        #expect(s.schemaVersion == 2)
        #expect(s.naturalScrolling == false)
        #expect(s.launchAtLogin == true)
        #expect(s.calibrations["X"]?.orientation == 90)
        let effective = s.effectiveProfile(for: nil)
        #expect(effective.config.longPressDuration == 0.9)
        #expect(effective.config.tapMaxMovement == 12)
        #expect(effective.config.swipeDistance == GestureConfig().swipeDistance)
        #expect(effective.binding(.twoFingerDrag).naturalScrolling == false)
        let backup = store.fileURL.path + ".v1"
        #expect(FileManager.default.fileExists(atPath: backup))
        #expect(try String(contentsOf: URL(fileURLWithPath: backup), encoding: .utf8) == legacy)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(!text.contains("\n  \"naturalScrolling\""))   // no top-level legacy key (top-level keys are indented by two spaces)
        #expect(!text.contains("\n  \"gesture\""))
        #expect(store.load() == s)   // second load is stable
    }

    @Test func fileWithoutSchemaVersionIsTreatedAsLegacy() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{\"enabled\": false, \"naturalScrolling\": false}".utf8).write(to: store.fileURL)
        let s = store.load()
        #expect(s.enabled == false)
        #expect(s.naturalScrolling == false)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path + ".v1"))
    }

    @Test func duplicateProfilesCollapse() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let json = """
        {"schemaVersion":2,"appProfiles":[
          {"bundleID":"com.apple.Safari","displayName":"Safari","bindings":{},"config":{}},
          {"bundleID":"com.apple.Safari","displayName":"Safari copy","bindings":{},"config":{}},
          {"displayName":"No bundle id","bindings":{},"config":{}}]}
        """
        try Data(json.utf8).write(to: store.fileURL)
        let s = store.load()
        #expect(s.appProfiles.map(\.displayName) == ["Safari"])
        try store.save(s)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(text.components(separatedBy: "com.apple.Safari").count == 2)
    }

    @Test func upsertReplacesAndSortsAndRemoveDeletes() {
        var s = Settings()
        s.upsert(GestureProfile(bundleID: "com.b.App", displayName: "Zed"))
        s.upsert(GestureProfile(bundleID: "com.a.App", displayName: "alpha"))
        #expect(s.appProfiles.map(\.displayName) == ["alpha", "Zed"])
        s.upsert(GestureProfile(bundleID: "com.b.App", displayName: "Beta"))
        #expect(s.appProfiles.map(\.displayName) == ["alpha", "Beta"])
        #expect(s.profile(id: "com.a.App")?.displayName == "alpha")
        #expect(s.profile(id: GestureProfile.defaultID) == s.defaultProfile)
        var renamed = s.defaultProfile
        renamed.displayName = "Mine"
        s.upsert(renamed)
        #expect(s.defaultProfile.displayName == "Mine")
        s.removeProfile(bundleID: "com.a.App")
        #expect(s.appProfiles.map(\.id) == ["com.b.App"])
    }

    @Test func defaultDirectoryIsApplicationSupport() {
        let url = SettingsStore.defaultDirectory()
        #expect(url.path.hasSuffix("/Library/Application Support/TouchBridge"))
    }
}
