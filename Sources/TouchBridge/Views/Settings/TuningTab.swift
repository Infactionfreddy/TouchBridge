import SwiftUI
import TouchCore

struct TuningTab: View {
    @Bindable var state: AppState
    let profileID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Form {
                ForEach(GestureConfigField.all) { field in
                    TuningRow(state: state, profileID: profileID, field: field)
                }
            }
            .formStyle(.grouped)
            HStack {
                if profileID != GestureProfile.defaultID {
                    Text("Tick “Override” to give this application its own value.").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restore defaults") { state.restoreTuning(in: profileID) }
            }
        }
    }
}

struct TuningRow: View {
    @Bindable var state: AppState
    let profileID: String
    let field: GestureConfigField

    private var isDefaultProfile: Bool { profileID == GestureProfile.defaultID }

    var body: some View {
        let resolved = state.resolvedConfigValue(field, in: profileID)
        let editable = isDefaultProfile || !resolved.inherited
        let value = Binding(get: { resolved.value }, set: { state.setConfigValue($0, for: field, in: profileID) })
        HStack(spacing: 12) {
            if !isDefaultProfile {
                Toggle("Override", isOn: Binding(get: { !resolved.inherited },
                                                set: { on in state.setConfigValue(on ? resolved.value : nil, for: field, in: profileID) }))
                    .labelsHidden()
                    .help("Override the inherited value")
            }
            Text(field.label).frame(width: 260, alignment: .leading)
            TextField("", value: value, format: .number.precision(.fractionLength(0...3)))
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
                .disabled(!editable)
            Stepper("", value: value, step: field.step).labelsHidden().disabled(!editable)
            Text(field.unit).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            Spacer()
            Text("Default \(GestureConfig()[keyPath: field.value].formatted(.number.precision(.fractionLength(0...3))))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
