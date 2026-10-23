import AppKit
import SwiftUI
import TouchCore

struct GesturesTab: View {
    @Bindable var state: AppState
    let profileID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach(FingerGroup.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(GestureKind.allCases.filter { $0.group == group }, id: \.self) { kind in
                            GestureRow(state: state, profileID: profileID, kind: kind)
                        }
                    }
                }
            }
            HStack {
                if profileID != GestureProfile.defaultID {
                    Text("Grey “Default” rows inherit from the default profile.").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore defaults") { state.restoreGestures(in: profileID) }
            }
        }
    }
}

struct GestureRow: View {
    @Bindable var state: AppState
    let profileID: String
    let kind: GestureKind
    @State private var recordingShortcut = false

    var body: some View {
        let resolved = state.resolvedBinding(kind, in: profileID)
        let binding = resolved.binding
        HStack(spacing: 12) {
            Text(kind.displayName).frame(width: 240, alignment: .leading)
            Toggle("", isOn: Binding(get: { binding.enabled }, set: { value in store(binding) { $0.enabled = value } }))
                .labelsHidden()
                .help("Enabled")
            ActionMenu(kind: kind, action: binding.action,
                       onChoose: { action in store(binding) { $0.action = action } },
                       onRecordShortcut: { recordingShortcut = true })
                .frame(width: 230, alignment: .leading)
            if case .openFile(let path) = binding.action, !FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help("File not found: \(path)")
            }
            if kind == .twoFingerDrag {
                Toggle("Natural scrolling", isOn: Binding(get: { binding.naturalScrolling ?? true }, set: { value in store(binding) { $0.naturalScrolling = value } }))
                Toggle("Momentum", isOn: Binding(get: { binding.momentum ?? true }, set: { value in store(binding) { $0.momentum = value } }))
            }
            Spacer()
            if profileID != GestureProfile.defaultID {
                Text(resolved.inherited ? "Default" : "Custom").font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(!kind.isRecognized)
        .help(kind.isRecognized ? "" : "Not recognized yet")
        .contextMenu {
            if !resolved.inherited, profileID != GestureProfile.defaultID {
                Button("Reset to default") { state.resetBinding(for: kind, in: profileID) }
            }
        }
        .sheet(isPresented: $recordingShortcut) {
            ShortcutRecorderSheet(current: currentKey(binding.action)) { outcome in
                switch outcome {
                case .use(let key): store(binding) { $0.action = .keystroke(key: key) }
                case .clear: store(binding) { $0.action = .none }
                case .cancel: break
                }
                recordingShortcut = false
            }
        }
    }

    /// Copies `binding`, applies `change` and stores the result in the selected profile.
    private func store(_ binding: GestureBinding, _ change: (inout GestureBinding) -> Void) {
        var copy = binding
        change(&copy)
        state.setBinding(copy, for: kind, in: profileID)
    }

    private func currentKey(_ action: GestureAction) -> KeyCommand? {
        if case .keystroke(let key) = action { return key }
        return nil
    }
}

struct ActionMenu: View {
    let kind: GestureKind
    let action: GestureAction
    let onChoose: (GestureAction) -> Void
    let onRecordShortcut: () -> Void

    /// Pinch, spread and rotate only pass through or are off in this version; discrete actions come with Part C.
    private var discreteAllowed: Bool {
        ![GestureKind.pinch, .spread, .rotateLeft, .rotateRight].contains(kind)
    }

    var body: some View {
        Menu {
            Button("Pass through") { onChoose(.passThrough) }
            Button("None") { onChoose(.none) }
            Divider()
            Menu("Mouse click") {
                ForEach(MouseButton.allCases, id: \.self) { button in
                    Menu(button.displayName) {
                        Button("Single click") { onChoose(.mouseClick(button: button, count: 1)) }
                        Button("Double click") { onChoose(.mouseClick(button: button, count: 2)) }
                        Button("Triple click") { onChoose(.mouseClick(button: button, count: 3)) }
                    }
                }
            }
            .disabled(!discreteAllowed)
            Button("Keyboard shortcut…") { onRecordShortcut() }.disabled(!discreteAllowed)
            Menu("System") {
                ForEach(SystemAction.allCases, id: \.self) { system in
                    Button(system.displayName) { onChoose(.systemAction(action: system)) }
                }
            }
            .disabled(!discreteAllowed)
            Button("Open file…") { chooseFile() }.disabled(!discreteAllowed)
            if !discreteAllowed {
                Divider()
                Text("Other actions for this gesture come in a later version")
            }
        } label: {
            Text(Self.title(for: action))
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a file or application to open"
        if panel.runModal() == .OK, let url = panel.url {
            onChoose(.openFile(path: url.path))
        }
    }

    static func title(for action: GestureAction) -> String {
        switch action {
        case .none: return "None"
        case .passThrough: return "Pass through"
        case .mouseClick(let button, let count): return "\(button.displayName) click" + (count > 1 ? " ×\(count)" : "")
        case .keystroke(let key): return KeyNames.display(key)
        case .systemAction(let system): return system.displayName
        case .openFile(let path): return "Open " + URL(fileURLWithPath: path).lastPathComponent
        }
    }
}
