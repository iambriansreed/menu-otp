import OTPCore
import SwiftUI

/// One account in Settings: a summary row, or its edit panel.
///
/// The row's identity in the List is the account's identity, so SwiftUI keeps this
/// view's @State (an open panel, typed-but-unsaved fields, a staged icon) across
/// every unrelated change to the list. That is what the Electron version's
/// captureOpenEdits() machinery had to do by hand.
struct AccountRowView: View {
    let account: Account
    let model: AccountsModel
    var startEditing = false

    @State private var isEditing = false
    @State private var isHovering = false
    @State private var confirmingDelete = false
    @State private var isHoveringDelete = false
    @FocusState private var focusedAction: RowAction?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private enum RowAction: Hashable {
        case hide, edit, delete
    }

    /// The delete alert counts too: its row keeps its buttons while it's up.
    private var showsActions: Bool {
        isHovering || focusedAction != nil || voiceOver || confirmingDelete
    }

    private var actionColor: Color { showsActions ? .secondary : .clear }
    @State private var fields = AccountFields()
    @State private var iconEditor: IconEditorModel?
    @State private var error = ""
    @FocusState private var issuerFocused: Bool

    var body: some View {
        Group {
            if isEditing, let iconEditor {
                editPanel(iconEditor)
            } else {
                summary
            }
        }
        .onAppear {
            if startEditing, !isEditing { beginEditing() }
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            IconView(icon: account.icon, placeholderSeed: account.issuer.isEmpty ? account.account : account.issuer)
                .modifier(HiddenIconStyle(isHidden: account.hidden, isHovering: isHovering, hasIcon: IconView.hasIcon(account.icon)))
            Text(account.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(account.hidden ? 0.55 : 1)
            Spacer(minLength: 4)
            if account.hidden {
                Text("HIDDEN")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            // Only while the row is pointed at or one of its buttons has keyboard focus,
            // as in Finder and System Settings lists, so the list reads as names rather
            // than a column of buttons. Always shown to VoiceOver users. They keep their
            // space while hidden, so a name never re-truncates as the pointer moves.
            //
            // Hidden by drawing them in a clear colour, not with opacity(0): SwiftUI
            // drops a zero-opacity view from the accessibility tree, which took the
            // buttons away from Voice Control and Switch Control (and failed
            // app/scripts/a11y-test.sh). A clear icon is still a button to all of them.
            HStack(spacing: 2) {
                Button {
                    report { try model.toggleHidden(account.identity) }
                } label: {
                    Image(systemName: account.hidden ? "eye.slash" : "eye").modifier(RowActionPadding())
                }
                .help(account.hidden ? "Show in menu" : "Hide from menu")
                // Named per account: VoiceOver otherwise reads the symbol ("eye",
                // "trash") and every row's buttons sound the same
                .accessibilityLabel(account.hidden ? "Show \(account.label) in menu" : "Hide \(account.label) from menu")
                .focused($focusedAction, equals: .hide)
                Button(action: beginEditing) {
                    Image(systemName: "pencil").modifier(RowActionPadding())
                }
                .help("Edit")
                .accessibilityLabel("Edit \(account.label)")
                .focused($focusedAction, equals: .edit)
                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash").modifier(RowActionPadding())
                }
                // Grey like the others until it's the one being pointed at
                .foregroundStyle(isHoveringDelete ? Color.red : actionColor)
                .onHover { isHoveringDelete = $0 }
                .help("Delete")
                .accessibilityLabel("Delete \(account.label)")
                .focused($focusedAction, equals: .delete)
            }
            .foregroundStyle(actionColor)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .alert("Delete “\(account.label)”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                report { try model.delete(account.identity) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its secret is removed from \(AppEnvironment.appName). This can't be undone.")
        }
    }

    private func editPanel(_ iconEditor: IconEditorModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The same labelled layout as Add Account's Manual form
            AccountFieldsGrid(fields: fields, iconEditor: iconEditor, issuerFocus: $issuerFocused, onSubmit: save)
            if !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { isEditing = false }
                Button("Save", action: save).buttonStyle(.borderedProminent)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(.vertical, SettingsMetrics.cardPadding)
    }

    private func beginEditing() {
        fields.issuer = account.issuer
        fields.account = account.account
        fields.secret = account.secret
        error = ""
        let fields = fields
        iconEditor = IconEditorModel(
            icon: account.icon,
            url: account.url,
            lookup: model.lookupFavicon,
            label: { (fields.issuer, fields.account) }
        )
        isEditing = true
        // Ready to type, as in Easy OTP. The field exists only after this update.
        DispatchQueue.main.async { issuerFocused = true }
    }

    private func save() {
        guard let iconEditor else { return }
        do {
            try model.saveEdit(
                original: account.identity,
                issuer: fields.issuer,
                account: fields.account,
                secret: fields.secret,
                icon: iconEditor.currentIcon,
                url: iconEditor.currentURL,
                iconUntouched: !iconEditor.isDirty
            )
            isEditing = false
        } catch {
            // ModelError reads as a sentence ("Account and Secret are required.", …)
            self.error = error.localizedDescription
        }
    }
}

/// Breathing room around a row's small borderless buttons (hide, edit, delete), with a
/// click target that covers it.
struct RowActionPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}

/// Settings mirrors the menu for hidden accounts only: their (real) icons are
/// greyed and inverted until the row is hovered, and dimmed either way. A visible
/// account never looks grey in Settings, since it never does in the menu.
struct HiddenIconStyle: ViewModifier {
    let isHidden: Bool
    let isHovering: Bool
    let hasIcon: Bool

    func body(content: Content) -> some View {
        if !isHidden {
            content
        } else if isHovering || !hasIcon {
            content.opacity(0.55)
        } else {
            content.grayscale(1).colorInvert().opacity(0.55)
        }
    }
}
