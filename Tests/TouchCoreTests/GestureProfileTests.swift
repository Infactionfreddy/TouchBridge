import Testing
import Foundation
@testable import TouchCore

@Suite struct GestureProfileTests {
    @Test func overridesApplyFieldByFieldAndClamp() {
        var o = GestureConfigOverrides()
        #expect(o.isEmpty)
        o.longPressDuration = 1.0
        o.stuckTimeout = -1          // clamped to 0
        o.momentumDecayPerFrame = 5  // clamped to 0.999
        let applied = o.apply(to: GestureConfig())
        #expect(applied.longPressDuration == 1.0)
        #expect(applied.stuckTimeout == 0)
        #expect(applied.momentumDecayPerFrame == 0.999)
        #expect(applied.tapMaxMovement == GestureConfig().tapMaxMovement)
        var full = GestureConfig()
        full.swipeDistance = 90
        #expect(GestureConfigOverrides(full: full).apply(to: GestureConfig()) == full)
        #expect(!GestureConfigOverrides(full: full).isEmpty)
    }

    @Test func clampedMatchesDecodeLimits() throws {
        var c = GestureConfig()
        c.rotateThreshold = 400
        c.velocityWindow = .nan
        let clamped = c.clamped()
        #expect(clamped.rotateThreshold == 180)
        #expect(clamped.velocityWindow == GestureConfig().velocityWindow)
        let decoded = try JSONDecoder().decode(GestureConfig.self, from: Data("{\"rotateThreshold\": 400}".utf8))
        #expect(decoded.rotateThreshold == 180)
    }

    @Test func fieldDescriptorsCoverEveryTunable() {
        #expect(GestureConfigField.all.count == 14)
        #expect(GestureConfigField.all.map(\.label).contains("Long press duration"))
        var o = GestureConfigOverrides()
        for field in GestureConfigField.all { o[keyPath: field.override] = 1 }
        #expect(!o.isEmpty)
        let config = o.apply(to: GestureConfig())
        for field in GestureConfigField.all where field.label != "Momentum decay per frame" {
            #expect(config[keyPath: field.value] == 1, Comment(rawValue: field.label))
        }
        #expect(config.momentumDecayPerFrame == 0.999)
    }

    @Test func profileRoundTripsThroughJSON() throws {
        var overrides = GestureConfigOverrides()
        overrides.tapMaxDuration = 0.4
        let profile = GestureProfile(bundleID: "com.apple.Safari", displayName: "Safari",
                                     bindings: [.twoFingerTap: GestureBinding(action: .mouseClick(button: .middle, count: 1)),
                                                .threeFingerSwipeLeft: GestureBinding(action: .keystroke(key: KeyCommand(keyCode: 33, command: true)))],
                                     config: overrides)
        let data = try JSONEncoder().encode(profile)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"twoFingerTap\":{"))
        #expect(!json.contains("stuckTimeout"))
        #expect(try JSONDecoder().decode(GestureProfile.self, from: data) == profile)
        #expect(profile.id == "com.apple.Safari")
        #expect(GestureProfile().id == GestureProfile.defaultID)
    }

    @Test func unknownKindsAreDroppedAndUnknownActionsFallBack() throws {
        let json = """
        {"bundleID":"com.example.App","displayName":"App",
         "bindings":{"tap":{"enabled":true,"action":{"none":{}}},
                     "sixFingerWiggle":{"enabled":true,"action":{"none":{}}},
                     "press":{"action":{"warp":{"to":"moon"}}}},
         "config":{"longPressDuration":0.7,"gravity":9.81}}
        """
        let profile = try JSONDecoder().decode(GestureProfile.self, from: Data(json.utf8))
        #expect(profile.bindings == [.tap: GestureBinding(action: .none), .press: GestureBinding(action: .passThrough)])
        #expect(profile.config.longPressDuration == 0.7)
        let reencoded = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        #expect(!reencoded.contains("sixFingerWiggle"))
    }

    @Test func profileWithoutNameOrBindingsDecodes() throws {
        let profile = try JSONDecoder().decode(GestureProfile.self, from: Data("{\"bundleID\":\"com.example.App\"}".utf8))
        #expect(profile.displayName == "com.example.App")
        #expect(profile.bindings.isEmpty)
        #expect(profile.config.isEmpty)
    }
}
