import Foundation

public enum DisplaySelection: Codable, Equatable, Sendable {
    case auto
    case display(uuid: String)
}

/// Schema 2: general options plus the default gesture profile and one profile per application.
public struct Settings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    /// Always the current version; a file's version is not carried over, so a save writes the version that
    /// matches the payload. Schema 1 (`gesture`, `naturalScrolling` at the top level) is migrated in `init(from:)`.
    public var schemaVersion: Int = Settings.currentSchemaVersion
    public var enabled: Bool = true
    public var displaySelection: DisplaySelection = .auto
    /// Keyed by device serial number.
    public var calibrations: [String: Calibration] = [:]
    public var launchAtLogin: Bool = false
    public var defaultProfile: GestureProfile = GestureProfile()
    /// Unique bundle IDs, sorted by display name.
    public var appProfiles: [GestureProfile] = []

    public init() {}

    /// Scroll direction of the default profile's two-finger drag (the menu toggle).
    public var naturalScrolling: Bool {
        get { defaultProfile.bindings[.twoFingerDrag]?.naturalScrolling ?? GestureBinding.builtIn(for: .twoFingerDrag).naturalScrolling ?? true }
        set {
            var binding = defaultProfile.bindings[.twoFingerDrag] ?? .builtIn(for: .twoFingerDrag)
            binding.naturalScrolling = newValue
            defaultProfile.bindings[.twoFingerDrag] = binding
        }
    }

    public func effectiveProfile(for bundleID: String?) -> EffectiveProfile {
        ProfileResolver.effective(for: bundleID, defaultProfile: defaultProfile, appProfiles: appProfiles)
    }

    public func profile(id: String) -> GestureProfile? {
        id == GestureProfile.defaultID ? defaultProfile : appProfiles.first { $0.id == id }
    }

    /// Inserts or replaces by bundle ID (nil replaces the default profile) and keeps the list sorted by name.
    public mutating func upsert(_ profile: GestureProfile) {
        guard let bundleID = profile.bundleID else {
            defaultProfile = profile
            return
        }
        appProfiles.removeAll { $0.bundleID == bundleID }
        appProfiles.append(profile)
        appProfiles.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public mutating func removeProfile(bundleID: String) {
        appProfiles.removeAll { $0.bundleID == bundleID }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, enabled, displaySelection, calibrations, launchAtLogin, defaultProfile, appProfiles
        case gesture, naturalScrolling   // schema 1 only
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        displaySelection = try c.decodeIfPresent(DisplaySelection.self, forKey: .displaySelection) ?? d.displaySelection
        calibrations = try c.decodeIfPresent([String: Calibration].self, forKey: .calibrations) ?? d.calibrations
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        defaultProfile = try c.decodeIfPresent(GestureProfile.self, forKey: .defaultProfile) ?? d.defaultProfile
        defaultProfile.bundleID = nil
        var seen = Set<String>()
        appProfiles = (try c.decodeIfPresent([GestureProfile].self, forKey: .appProfiles) ?? []).filter { profile in
            guard let bundleID = profile.bundleID else { return false }
            return seen.insert(bundleID).inserted
        }
        // Schema 1: the flat gesture config and the natural-scrolling flag become the default profile.
        if let legacy = try c.decodeIfPresent(GestureConfig.self, forKey: .gesture) {
            defaultProfile.config = GestureConfigOverrides(full: legacy)
        }
        if let legacyNatural = try c.decodeIfPresent(Bool.self, forKey: .naturalScrolling) {
            naturalScrolling = legacyNatural
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(displaySelection, forKey: .displaySelection)
        try c.encode(calibrations, forKey: .calibrations)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(defaultProfile, forKey: .defaultProfile)
        try c.encode(appProfiles, forKey: .appProfiles)
    }
}
