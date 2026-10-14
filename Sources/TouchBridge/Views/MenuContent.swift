import SwiftUI

struct MenuContent: View {
    @Bindable var state: AppState

    var body: some View {
        Text(state.statusLine)
        if let error = state.lastError {
            Text(error).foregroundStyle(.red)
        }
        Divider()
        Toggle("Touch active", isOn: Binding(get: { state.settings.enabled }, set: { state.setEnabled($0) }))
        Toggle("Natural scrolling", isOn: Binding(get: { state.settings.naturalScrolling }, set: { state.setNaturalScrolling($0) }))
        Toggle("Launch at login", isOn: Binding(get: { state.launchAtLoginEnabled }, set: { state.setLaunchAtLogin($0) }))
        Divider()
        Button("Permissions…") { state.showPermissions() }
        Button("Open settings file") { state.openSettingsFile() }
        Divider()
        Button("Quit TouchBridge") { NSApp.terminate(nil) }
    }
}
