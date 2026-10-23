import Foundation

/// A fully resolved profile: every gesture kind has a binding and the config is complete.
public struct EffectiveProfile: Equatable, Sendable {
    public var profileID: String
    public var profileName: String
    public var config: GestureConfig
    public var bindings: [GestureKind: GestureBinding]

    public init(profileID: String, profileName: String, config: GestureConfig, bindings: [GestureKind: GestureBinding]) {
        self.profileID = profileID
        self.profileName = profileName
        self.config = config
        self.bindings = bindings
    }

    public func binding(_ kind: GestureKind) -> GestureBinding {
        bindings[kind] ?? .builtIn(for: kind)
    }

    /// The milestone 1/2 default set with default tuning.
    public static let builtIn = ProfileResolver.effective(for: nil, defaultProfile: GestureProfile(), appProfiles: [])
}

/// Resolves built-in defaults ⟵ default profile ⟵ app profile. Pure and deterministic.
public enum ProfileResolver {
    public static func effective(for bundleID: String?, defaultProfile: GestureProfile, appProfiles: [GestureProfile]) -> EffectiveProfile {
        var bindings: [GestureKind: GestureBinding] = [:]
        for kind in GestureKind.allCases {
            bindings[kind] = defaultProfile.bindings[kind] ?? .builtIn(for: kind)
        }
        var config = defaultProfile.config.apply(to: GestureConfig())
        var id = GestureProfile.defaultID
        var name = defaultProfile.displayName
        if let bundleID, let app = appProfiles.first(where: { $0.bundleID == bundleID }) {
            for (kind, binding) in app.bindings { bindings[kind] = binding }
            config = app.config.apply(to: config)
            id = app.id
            name = app.displayName
        }
        return EffectiveProfile(profileID: id, profileName: name, config: config, bindings: bindings)
    }
}
