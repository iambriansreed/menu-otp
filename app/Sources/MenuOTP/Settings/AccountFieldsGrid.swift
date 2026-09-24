import OTPCore
import SwiftUI

/// Issuer, account, secret and icon, each with a label in a column on the left and an
/// example as its placeholder. Shared by the Manual form and the edit panel, so both
/// look the same. The fields keep their names as titles, which is what VoiceOver reads.
struct AccountFieldsGrid: View {
    @Bindable var fields: AccountFields
    let iconEditor: IconEditorModel
    /// The edit panel focuses Issuer when it opens; the Manual form doesn't.
    var issuerFocus: FocusState<Bool>.Binding?
    var onSubmit: () -> Void = {}

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            row("Issuer") {
                let field = TextField("Issuer", text: $fields.issuer, prompt: Text("GitHub"))
                    .onSubmit(onSubmit)
                if let issuerFocus { field.focused(issuerFocus) } else { field }
            }
            row("Account") {
                TextField("Account", text: $fields.account, prompt: Text("jane@example.com"))
                    .onSubmit(onSubmit)
            }
            row("Secret") {
                SecretField(title: "Secret", text: $fields.secret, prompt: "Base32 key from the setup page", onSubmit: onSubmit)
            }
            row("Icon") {
                IconEditorView(editor: iconEditor, placeholderSeed: fields.placeholderSeed)
            }
        }
    }

    /// Labels line up on the right, against their fields, on the first text baseline
    /// (the icon row's status line can wrap below it).
    private func row(_ label: String, @ViewBuilder field: () -> some View) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
                // The field is already named; don't read the name twice
                .accessibilityHidden(true)
            field()
        }
    }
}
