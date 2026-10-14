import Foundation

public enum DisplaySelection: Codable, Equatable, Sendable {
    case auto
    case display(uuid: String)
}

public struct Settings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = Settings.currentSchemaVersion
    public var enabled: Bool = true
    public var displaySelection: DisplaySelection = .auto
    public var naturalScrolling: Bool = true
    public var gesture: GestureConfig = GestureConfig()
    /// Keyed by device serial number.
    public var calibrations: [String: Calibration] = [:]
    public var launchAtLogin: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        displaySelection = try c.decodeIfPresent(DisplaySelection.self, forKey: .displaySelection) ?? d.displaySelection
        naturalScrolling = try c.decodeIfPresent(Bool.self, forKey: .naturalScrolling) ?? d.naturalScrolling
        gesture = try c.decodeIfPresent(GestureConfig.self, forKey: .gesture) ?? d.gesture
        calibrations = try c.decodeIfPresent([String: Calibration].self, forKey: .calibrations) ?? d.calibrations
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }
}
