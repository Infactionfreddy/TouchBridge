import Foundation

/// Reads and writes `settings.json`. Never throws on load: a missing file yields defaults,
/// an unreadable file is moved to `settings.json.broken`, defaults are written and returned.
public struct SettingsStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("TouchBridge", isDirectory: true)
    }

    public var fileURL: URL {
        directory.appendingPathComponent("settings.json")
    }

    private struct SchemaProbe: Decodable { var schemaVersion: Int? }

    /// Missing file → defaults. Older schema → migrated by `Settings.init(from:)`, the original copied to
    /// `settings.json.v<N>`, the result saved only if that backup succeeded (otherwise the file stays untouched
    /// and is migrated in memory on every launch). Newer schema → backed up the same way, never saved here.
    /// Unreadable file → set aside as `.broken`, defaults written.
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return Settings() }
        do {
            let settings = try JSONDecoder().decode(Settings.self, from: data)
            let version = (try? JSONDecoder().decode(SchemaProbe.self, from: data).schemaVersion) ?? 1
            if version < Settings.currentSchemaVersion {
                let backup = URL(fileURLWithPath: fileURL.path + ".v\(version)")
                try? FileManager.default.removeItem(at: backup)
                do {
                    try FileManager.default.copyItem(at: fileURL, to: backup)
                    try? save(settings)
                } catch {
                    // keep the original untouched; it is migrated in memory on every launch
                }
            } else if version > Settings.currentSchemaVersion {
                let backup = URL(fileURLWithPath: fileURL.path + ".v\(version)")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
            return settings
        } catch {
            let broken = URL(fileURLWithPath: fileURL.path + ".broken")
            try? FileManager.default.removeItem(at: broken)
            try? FileManager.default.moveItem(at: fileURL, to: broken)
            let defaults = Settings()
            try? save(defaults)
            return defaults
        }
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
