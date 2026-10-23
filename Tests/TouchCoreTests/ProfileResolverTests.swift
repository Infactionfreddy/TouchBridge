import Testing
@testable import TouchCore

@Suite struct ProfileResolverTests {
    var defaultProfile: GestureProfile {
        var config = GestureConfigOverrides()
        config.longPressDuration = 0.8
        return GestureProfile(bindings: [.twoFingerTap: GestureBinding(action: .mouseClick(button: .middle, count: 1))], config: config)
    }
    var safari: GestureProfile {
        var config = GestureConfigOverrides()
        config.tapMaxDuration = 0.4
        return GestureProfile(bundleID: "com.apple.Safari", displayName: "Safari",
                              bindings: [.threeFingerSwipeLeft: GestureBinding(action: .keystroke(key: KeyCommand(keyCode: 33, command: true)))],
                              config: config)
    }

    @Test func appProfileOverridesDefaultWhichOverridesBuiltIn() {
        let e = ProfileResolver.effective(for: "com.apple.Safari", defaultProfile: defaultProfile, appProfiles: [safari])
        #expect(e.profileID == "com.apple.Safari")
        #expect(e.profileName == "Safari")
        #expect(e.binding(.twoFingerTap).action == .mouseClick(button: .middle, count: 1))     // from the default profile
        #expect(e.binding(.threeFingerSwipeLeft).action == .keystroke(key: KeyCommand(keyCode: 33, command: true)))
        #expect(e.binding(.threeFingerSwipeRight).action == .systemAction(action: .spaceLeft))   // built in
        #expect(e.config.longPressDuration == 0.8)
        #expect(e.config.tapMaxDuration == 0.4)
        #expect(e.config.swipeDistance == GestureConfig().swipeDistance)
        #expect(e.bindings.count == GestureKind.allCases.count)
    }

    @Test func nilAndUnknownBundleIDsUseTheDefaultProfile() {
        let forNil = ProfileResolver.effective(for: nil, defaultProfile: defaultProfile, appProfiles: [safari])
        let forUnknown = ProfileResolver.effective(for: "com.example.Unknown", defaultProfile: defaultProfile, appProfiles: [safari])
        #expect(forNil == forUnknown)
        #expect(forNil.profileID == GestureProfile.defaultID)
        #expect(forNil.binding(.threeFingerSwipeLeft).action == .systemAction(action: .spaceRight))
        #expect(forNil.config.tapMaxDuration == GestureConfig().tapMaxDuration)
    }

    @Test func emptyAppProfileEqualsTheDefaultProfileExceptForItsName() {
        let empty = GestureProfile(bundleID: "com.example.Empty", displayName: "Empty")
        let e = ProfileResolver.effective(for: "com.example.Empty", defaultProfile: defaultProfile, appProfiles: [empty])
        let d = ProfileResolver.effective(for: nil, defaultProfile: defaultProfile, appProfiles: [])
        #expect(e.bindings == d.bindings)
        #expect(e.config == d.config)
        #expect(e.profileName == "Empty")
    }

    @Test func overridesAreClamped() {
        var config = GestureConfigOverrides()
        config.stuckTimeout = -1
        config.momentumDecayPerFrame = 5
        let app = GestureProfile(bundleID: "com.example.App", displayName: "App", config: config)
        let e = ProfileResolver.effective(for: "com.example.App", defaultProfile: GestureProfile(), appProfiles: [app])
        #expect(e.config.stuckTimeout == 0)
        #expect(e.config.momentumDecayPerFrame == 0.999)
    }

    @Test func builtInEffectiveProfileIsTheDefaultSet() {
        let e = EffectiveProfile.builtIn
        #expect(e.config == GestureConfig())
        #expect(e.binding(.threeFingerSwipeUp).action == .systemAction(action: .missionControl))
        #expect(e.binding(.twoFingerDrag) == GestureBinding(action: .passThrough, naturalScrolling: true, momentum: true))
        #expect(e.binding(.fiveFingerTap).action == .none)
    }
}
