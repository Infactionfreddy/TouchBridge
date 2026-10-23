import SwiftUI
import TouchCore

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationSplitView {
            ProfileSidebar(state: state)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                TabView {
                    GesturesTab(state: state, profileID: state.selectedProfileID)
                        .tabItem { Text("Gestures") }
                    TuningTab(state: state, profileID: state.selectedProfileID)
                        .tabItem { Text("Tuning") }
                    AdvancedTab(state: state)
                        .tabItem { Text("Advanced") }
                }
                .padding()
            }
        }
        .frame(minWidth: 960, minHeight: 600)
    }

    private var header: some View {
        HStack {
            Text(state.selectedProfile.displayName).font(.title2)
            Spacer()
            Text("Frontmost: \(state.frontmostBundleID ?? "—")  ·  active profile: \(state.activeProfileName)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 8)
    }
}

struct AdvancedTab: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Button("Open settings file") { state.openSettingsFile() }
            Text("~/Library/Application Support/TouchBridge/settings.json. Edits made outside TouchBridge take effect after a restart.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
