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
        Menu("Touch screen display") {
            Button(state.settings.displaySelection == .auto ? "Automatic ✓" : "Automatic") {
                state.selectDisplay(.auto)
            }
            ForEach(state.displays) { display in
                let selected = state.settings.displaySelection == .display(uuid: display.uuid)
                Button(selected ? "\(display.name) ✓" : display.name) {
                    state.selectDisplay(.display(uuid: display.uuid))
                }
            }
        }
        .onAppear { state.refreshDisplays() }
        Divider()
        Button("Permissions…") { state.showPermissions() }
        Button("Gesture Identifier…") { state.showIdentifier() }
        Button("Settings…") { state.showSettings() }
        Divider()
        Button("Quit TouchBridge") { NSApp.terminate(nil) }
    }
}
