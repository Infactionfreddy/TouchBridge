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
    var displays: [DisplayResolver.DisplayDescription] = []
    var liveContacts: [Contact] = []
    /// Frontmost application and the gesture profile that applies to it, for the settings window header.
    var frontmostBundleID: String?
    var activeProfileName = "Default"

    /// Profile shown in the settings window: `GestureProfile.defaultID` or an app's bundle identifier.
    var selectedProfileID: String = GestureProfile.defaultID

    var selectedProfile: GestureProfile {
        settings.profile(id: selectedProfileID) ?? settings.defaultProfile
    }
    private var controller: PipelineController?

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

    /// Menu bar symbol (spec section 8/9 colours):
    /// - red, permissions missing: `hand.raised.slash`
    /// - green, a screen is seized exclusively and touch is on: `hand.tap.fill`
    /// - yellow, a screen is open only shared and touch is on (macOS moves the cursor too): `exclamationmark.triangle`
    ///   (there is no `hand.tap` variant with a warning badge)
    /// - neutral, no screen, open failed or touch off: `hand.tap`
    var menuIcon: String {
        if !allPermissionsGranted { return "hand.raised.slash" }
        if case .attached(_, let exclusive, _) = deviceStatus, settings.enabled {
            return exclusive ? "hand.tap.fill" : "exclamationmark.triangle"
        }
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
        let wasGranted = inputMonitoringGranted && accessibilityGranted
        let input = permissions.inputMonitoringGranted()
        let ax = permissions.accessibilityGranted()
        if input != inputMonitoringGranted || ax != accessibilityGranted {
            logger.info("permissions: input monitoring \(input), accessibility \(ax)")
        }
        inputMonitoringGranted = input
        accessibilityGranted = ax
        if allPermissionsGranted {
            if controller == nil { startController() } else if controller?.isPaused == true { controller?.start() }
        } else if wasGranted, let controller {
            controller.pause()
            liveContacts = []
            showPermissions()
        }
    }

    private func startController() {
        let controller = PipelineController(settings: settings)
        controller.onStatus = { [weak self] status in
            self?.deviceStatus = status
            if status == .none { self?.liveContacts = [] }
        }
        controller.onContacts = { [weak self] _, contacts in self?.liveContacts = contacts }
        controller.onActiveProfile = { [weak self] bundleID, profile in
            self?.frontmostBundleID = bundleID
            self?.activeProfileName = profile.profileName
        }
        self.controller = controller
        displays = controller.availableDisplays()
        controller.start()
    }

    func refreshDisplays() {
        displays = controller?.availableDisplays() ?? []
    }

    func selectDisplay(_ selection: DisplaySelection) {
        settings.displaySelection = selection
        saveSettings()
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
        controller?.updateSettings(settings)
    }

    func showPermissions() {
        Windows.shared.show(PermissionsView(state: self), title: "TouchBridge Permissions", id: "permissions")
    }

    func showIdentifier() {
        Windows.shared.show(GestureIdentifierView(state: self), title: "Gesture Identifier", id: "identifier")
    }

    func showSettings() {
        Windows.shared.show(SettingsView(state: self), title: "TouchBridge Settings", id: "settings")
    }

    // MARK: - Profile editing (every change is saved and pushed to the pipelines at once)

    /// Adds a profile for the application bundle at `url` (from the open panel) and selects it.
    func addProfile(appAt url: URL) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            lastError = "Not an application bundle: \(url.lastPathComponent)"
            return
        }
        if settings.profile(id: bundleID) == nil {
            let info = bundle.infoDictionary ?? [:]
            let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            settings.upsert(GestureProfile(bundleID: bundleID, displayName: name))
            saveSettings()
        }
        selectedProfileID = bundleID
    }

    func removeProfile(id: String) {
        guard id != GestureProfile.defaultID else { return }
        settings.removeProfile(bundleID: id)
        if selectedProfileID == id { selectedProfileID = GestureProfile.defaultID }
        saveSettings()
    }

    /// The binding shown for `kind` in profile `id`, and whether it is inherited (not set in that profile).
    func resolvedBinding(_ kind: GestureKind, in id: String) -> (binding: GestureBinding, inherited: Bool) {
        if let own = settings.profile(id: id)?.bindings[kind] { return (own, false) }
        if id == GestureProfile.defaultID { return (.builtIn(for: kind), true) }
        return (settings.effectiveProfile(for: nil).binding(kind), true)
    }

    func setBinding(_ binding: GestureBinding, for kind: GestureKind, in id: String) {
        guard var profile = settings.profile(id: id) else { return }
        profile.bindings[kind] = binding
        settings.upsert(profile)
        saveSettings()
    }

    func resetBinding(for kind: GestureKind, in id: String) {
        guard var profile = settings.profile(id: id) else { return }
        profile.bindings[kind] = nil
        settings.upsert(profile)
        saveSettings()
    }

    /// The tuning value shown for `field` in profile `id`, and whether it is inherited.
    func resolvedConfigValue(_ field: GestureConfigField, in id: String) -> (value: Double, inherited: Bool) {
        if let own = settings.profile(id: id)?.config[keyPath: field.override] { return (own, false) }
        let inherited = id == GestureProfile.defaultID ? GestureConfig() : settings.effectiveProfile(for: nil).config
        return (inherited[keyPath: field.value], true)
    }

    /// nil removes the override (the value is inherited again).
    func setConfigValue(_ value: Double?, for field: GestureConfigField, in id: String) {
        guard var profile = settings.profile(id: id) else { return }
        profile.config[keyPath: field.override] = value
        settings.upsert(profile)
        saveSettings()
    }

    func restoreGestures(in id: String) {
        guard var profile = settings.profile(id: id) else { return }
        profile.bindings = [:]
        settings.upsert(profile)
        saveSettings()
    }

    func restoreTuning(in id: String) {
        guard var profile = settings.profile(id: id) else { return }
        profile.config = GestureConfigOverrides()
        settings.upsert(profile)
        saveSettings()
    }

    func openSettingsFile() {
        if !FileManager.default.fileExists(atPath: store.fileURL.path) { saveSettings() }
        NSWorkspace.shared.open(store.fileURL)
    }
}
