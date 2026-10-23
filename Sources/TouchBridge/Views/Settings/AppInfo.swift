import AppKit
import UniformTypeIdentifiers

enum AppInfo {
    /// Icon and name for a profile's application; a generic icon and "(not installed)" when it is missing.
    @MainActor
    static func describe(bundleID: String, fallbackName: String) -> (name: String, icon: NSImage, installed: Bool) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return (fallbackName, NSWorkspace.shared.icon(forFile: url.path), true)
        }
        return (fallbackName + " (not installed)", NSWorkspace.shared.icon(for: .applicationBundle), false)
    }
}
