import SwiftUI

/// A text field for anything holding a TOTP secret: masked by default, with an eye
/// button to show it. Masked, it's a SecureField, so macOS also turns on secure event
/// input while it has focus (other apps can't read the keystrokes) and it takes no part
/// in spell checking or text completion. Screen sharing and screenshots see bullets.
struct SecretField: View {
    /// The field's accessibility label, and its placeholder unless `prompt` is given
    let title: String
    @Binding var text: String
    /// Placeholder text, when a label column already shows the title
    var prompt: String?
    /// What the eye button's help and VoiceOver label call it ("Show secret").
    var name = "secret"
    var onSubmit: () -> Void = {}

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if revealed {
                    TextField(title, text: $text, prompt: prompt.map { Text($0) })
                        .autocorrectionDisabled()
                } else {
                    SecureField(title, text: $text, prompt: prompt.map { Text($0) })
                }
            }
            .focused($focused)
            .onSubmit(onSubmit)
            Button {
                // Swapping the field drops focus; give it back if the user was typing
                let wasFocused = focused
                revealed.toggle()
                if wasFocused { DispatchQueue.main.async { focused = true } }
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .frame(width: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(revealed ? "Hide \(name)" : "Show \(name)")
            .accessibilityLabel(revealed ? "Hide \(name)" : "Show \(name)")
        }
    }
}
