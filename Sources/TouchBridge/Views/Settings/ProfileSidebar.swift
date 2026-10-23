import AppKit
import SwiftUI
import TouchCore
import UniformTypeIdentifiers

struct ProfileSidebar: View {
    @Bindable var state: AppState
    @State private var confirmRemove = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $state.selectedProfileID) {
                Label("Default", systemImage: "hand.tap").tag(GestureProfile.defaultID)
                Section("Applications") {
                    ForEach(state.settings.appProfiles) { profile in
                        let info = AppInfo.describe(bundleID: profile.id, fallbackName: profile.displayName)
                        HStack {
                            Image(nsImage: info.icon).resizable().frame(width: 18, height: 18)
                            Text(info.name)
                        }
                        .tag(profile.id)
                    }
                }
            }
            Divider()
            HStack {
                Button { addProfile() } label: { Image(systemName: "plus") }
                    .help("Add a profile for an application in /Applications")
                Button { confirmRemove = true } label: { Image(systemName: "minus") }
                    .disabled(state.selectedProfileID == GestureProfile.defaultID)
                    .help("Remove the selected profile")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .confirmationDialog("Remove the profile \"\(state.selectedProfile.displayName)\"?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { state.removeProfile(id: state.selectedProfileID) }
        } message: {
            Text("The application falls back to the default profile.")
        }
    }

    private func addProfile() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the application this profile applies to"
        if panel.runModal() == .OK, let url = panel.url {
            state.addProfile(appAt: url)
        }
    }
}
