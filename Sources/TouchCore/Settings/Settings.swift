import Foundation

public enum DisplaySelection: Codable, Equatable, Sendable {
    case auto
    case display(uuid: String)
}

public struct Settings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    /// Always the current version; a file's version is not carried over, so a save writes the version that matches the payload. Migrations are added when a newer version exists.
    public var schemaVersion: Int = Settings.currentSchemaVersion
    public var enabled: Bool = true
    public var displaySelection: DisplaySelection = .auto
    public var naturalScrolling: Bool = true
    public var gesture: GestureConfig = GestureConfig()
    /// Keyed by device serial number.
    public var calibrations: [String: Calibration] = [:]
    public var launchAtLogin: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, enabled, displaySelection, naturalScrolling, gesture, calibrations, launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        displaySelection = try c.decodeIfPresent(DisplaySelection.self, forKey: .displaySelection) ?? d.displaySelection
        naturalScrolling = try c.decodeIfPresent(Bool.self, forKey: .naturalScrolling) ?? d.naturalScrolling
        gesture = try c.decodeIfPresent(GestureConfig.self, forKey: .gesture) ?? d.gesture
        calibrations = try c.decodeIfPresent([String: Calibration].self, forKey: .calibrations) ?? d.calibrations
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }
}
