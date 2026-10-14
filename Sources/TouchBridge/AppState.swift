import AppKit
import Observation
import ServiceManagement
import TouchCore
import os

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    enum DeviceStatus: Equatable {
        case none
        /// `problem` is nil when exclusive; when shared it describes why exclusive access is missing.
        case attached(name: String, exclusive: Bool, problem: String?)
        case openFailed(name: String)
    }

    var settings: Settings
    var inputMonitoringGranted = false
    var accessibilityGranted = false
    var deviceStatus: DeviceStatus = .none
    var lastError: String?

    let store: SettingsStore
    let permissions = PermissionCoordinator()
    private let logger = Logger(subsystem: "org.touchbridge", category: "permissions")
    private var started = false

    private init() {
        store = SettingsStore(directory: SettingsStore.defaultDirectory())
        settings = store.load()
    }

    var allPermissionsGranted: Bool { inputMonitoringGranted && accessibilityGranted }

    var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    var menuIcon: String {
        if !allPermissionsGranted { return "hand.raised.slash" }
        if case .attached = deviceStatus, settings.enabled { return "hand.tap.fill" }
        return "hand.tap"
    }

    var statusLine: String {
        if !allPermissionsGranted { return "Permissions missing" }
        switch deviceStatus {
        case .none: return "No touch screen connected"
        case .attached(let name, let exclusive, let problem):
            if exclusive { return "\(name): exclusive" }
            return "\(name): shared — \(problem ?? "exclusive access failed"); cursor is also moved by macOS"
        case .openFailed(let name): return "\(name): could not open"
        }
    }

    func start() {
        guard !started else { return }
        started = true
        refreshPermissions()
        if !allPermissionsGranted { showPermissions() }
        permissions.startPolling { [weak self] in self?.refreshPermissions() }
    }

    func refreshPermissions() {
        let input = permissions.inputMonitoringGranted()
        let ax = permissions.accessibilityGranted()
        if input != inputMonitoringGranted || ax != accessibilityGranted {
            logger.info("permissions: input monitoring \(input), accessibility \(ax)")
        }
        inputMonitoringGranted = input
        accessibilityGranted = ax
    }

    func setEnabled(_ enabled: Bool) {
        settings.enabled = enabled
        saveSettings()
    }

    func setNaturalScrolling(_ natural: Bool) {
        settings.naturalScrolling = natural
        saveSettings()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = enabled
            saveSettings()
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
    }

    func saveSettings() {
        do { try store.save(settings) } catch { lastError = "Could not save settings: \(error.localizedDescription)" }
    }

    func showPermissions() {
        Windows.shared.show(PermissionsView(state: self), title: "TouchBridge Permissions", id: "permissions")
    }

    func openSettingsFile() {
        if !FileManager.default.fileExists(atPath: store.fileURL.path) { saveSettings() }
        NSWorkspace.shared.open(store.fileURL)
    }
}
