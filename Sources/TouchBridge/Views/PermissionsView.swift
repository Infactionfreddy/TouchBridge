import SwiftUI

struct PermissionsView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TouchBridge needs two permissions").font(.title2)
            row(granted: state.inputMonitoringGranted,
                title: "Input Monitoring",
                detail: "Lets TouchBridge open the touch screen exclusively so macOS stops moving the cursor itself.") {
                state.permissions.requestInputMonitoring()
            }
            row(granted: state.accessibilityGranted,
                title: "Accessibility",
                detail: "Lets TouchBridge post mouse events and gestures.") {
                state.permissions.requestAccessibility()
            }
            Text("The status updates automatically after you grant a permission in System Settings.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 460)
    }

    private func row(granted: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant…", action: action)
            }
        }
    }
}
