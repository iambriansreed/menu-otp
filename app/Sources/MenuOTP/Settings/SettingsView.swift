import AppKit
import OTPCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Issuer/account/secret text for an edit panel or the manual Add form. A class so
/// an IconEditorModel's `label` closure can read the live values.
@Observable
final class AccountFields {
    var issuer = ""
    var account = ""
    var secret = ""

    func clear() {
        issuer = ""
        account = ""
        secret = ""
    }

    /// Letter-placeholder seed: issuer, else account.
    var placeholderSeed: String { issuer.trimmed.isEmpty ? account : issuer }
}

struct SettingsView: View {
    struct InitialState {
        var editing: AccountIdentity?
        var addTab: AddAccountView.Tab = .url
        var reordering = false
        /// Test hook: open Import's file picker as soon as the window appears.
        var openFilePicker = false
        /// Test hook: show Export's plain-text warning as soon as the window appears.
        var confirmExport = false
    }

    let model: AccountsModel
    let loginItem: LoginItem
    let initial: InitialState
    @State private var reordering: Bool

    init(model: AccountsModel, loginItem: LoginItem, initial: InitialState = InitialState()) {
        self.model = model
        self.loginItem = loginItem
        self.initial = initial
        _reordering = State(initialValue: initial.reordering)
    }

    var body: some View {
        Group {
            if reordering {
                reorderView
            } else {
                mainView
            }
        }
        .frame(minWidth: 380, minHeight: 400)
    }

    /// Not a List: on macOS a List holds every click on a text field in one of its
    /// rows for the double-click interval (0.5 s by default) before the field gets
    /// focus, which made the edit panel and the Add Account form feel sluggish.
    private var mainView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionGap) {
                SettingsSection("Accounts") {
                    HStack(spacing: 8) {
                        BulkIconsRow(model: model)
                        if model.accounts.count > 1 {
                            Button("Reorder") { reordering = true }
                                .help("Drag accounts into the order the menu shows them")
                        }
                    }
                } content: {
                    VStack(spacing: 0) {
                        if model.accounts.isEmpty {
                            Text("No accounts added yet.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        ForEach(Array(model.accounts.enumerated()), id: \.element.identity) { index, account in
                            if index > 0 { Divider().padding(.leading, SettingsMetrics.cardPadding) }
                            AccountRowView(account: account, model: model, startEditing: initial.editing == account.identity)
                                .padding(.horizontal, SettingsMetrics.cardPadding)
                        }
                    }
                    // Rows pad themselves vertically, so the dividers run the full height
                    .settingsCard(padded: false)
                }

                SettingsSection("Add Account") {
                    AddAccountView(model: model, initialTab: initial.addTab, openFilePicker: initial.openFilePicker)
                        .settingsCard()
                }

                SettingsSection("General") {
                    // Aligned on the first baseline, so the button stays level with the
                    // toggle when the login item's approval hint adds lines below it
                    HStack(alignment: .firstTextBaseline) {
                        LoginItemRow(loginItem: loginItem)
                        ExportRow(model: model, confirming: initial.confirmExport)
                    }
                    .settingsCard()
                }
            }
            .padding(20)
        }
    }

    /// Reorder mode uses a real List for its native drag and drop: the dragged row
    /// lifts and follows the pointer, an insertion line shows where it will land, and
    /// the list scrolls at its edges. A List is safe here and only here, because this
    /// mode shows no text fields for its click delay to affect.
    private var reorderView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Drag accounts into the order the menu shows them.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { reordering = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 10, trailing: 20))
            List {
                ForEach(model.accounts, id: \.identity) { account in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        IconView(icon: account.icon, placeholderSeed: account.issuer.isEmpty ? account.account : account.issuer)
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
                    }
                    .padding(.vertical, 6)
                }
                .onMove { source, destination in
                    report { try model.move(fromOffsets: source, toOffset: destination) }
                }
            }
            .listStyle(.inset)
        }
    }
}

/// One set of spacing for every section, so they line up.
enum SettingsMetrics {
    static let sectionGap: CGFloat = 20
    /// Between a section's heading and its card
    static let headingGap: CGFloat = 8
    /// Inside every card, and the account rows' side inset
    static let cardPadding: CGFloat = 12
    static let cardRadius: CGFloat = 8
}

extension View {
    /// The rounded, bordered card every section's content sits in, as in System
    /// Settings. `padded: false` for content that insets itself (the account rows).
    func settingsCard(padded: Bool = true) -> some View {
        padding(padded ? SettingsMetrics.cardPadding : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.cardRadius)
                    .strokeBorder(Color(nsColor: .separatorColor))
            )
    }
}

/// A titled group: a heading, an optional control at its right, then the content.
struct SettingsSection<Accessory: View, Content: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content

    init(_ title: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.headingGap) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                accessory
            }
            content
        }
    }
}

extension SettingsSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
    }
}

/// Runs a model mutation from a button, showing any failure (a disk or Keychain
/// error while saving) instead of swallowing it.
@MainActor
func report(_ action: () throws -> Void) {
    do {
        try action()
    } catch {
        NSApp.presentError(error)
    }
}

struct BulkIconsRow: View {
    let model: AccountsModel
    @State private var status = ""
    @State private var success = false
    @State private var running = false

    private var anyMissing: Bool { model.accounts.contains(where: \.hasNoIcon) }

    var body: some View {
        // In the Accounts heading, left of Reorder
        HStack(spacing: 8) {
            if !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(success ? Color.green : Color.secondary)
            }
            // Nothing to find once every account has an icon; the status stays so a
            // "Found N of M." is still readable after the button disappears
            if anyMissing {
                Button("Find Missing Icons", action: run).disabled(running)
            }
        }
        .onChange(of: anyMissing) { _, nowMissing in
            // New work appeared: the old result no longer describes the list
            if nowMissing, !running {
                status = ""
                success = false
            }
        }
    }

    private func run() {
        let targets = model.accounts.filter(\.hasNoIcon).map(\.identity)
        running = true
        success = false
        status = "Looking up icons 0/\(targets.count)…"
        Task {
            let found = await model.fillMissingIcons(targets) { done, total in
                status = "Looking up icons \(done)/\(total)…"
            }
            running = false
            success = !anyMissing
            status = found > 0 ? "Found \(found) of \(targets.count)." : "No favicons found."
        }
    }
}

/// Export writes every secret to disk unencrypted, so it asks first and says so.
struct ExportRow: View {
    let model: AccountsModel
    @State private var confirming: Bool
    @State private var status = ""
    @State private var host = HostWindow()

    init(model: AccountsModel, confirming: Bool = false) {
        self.model = model
        _confirming = State(initialValue: confirming)
    }

    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Button("Export Accounts…") { confirming = true }
                .disabled(model.accounts.isEmpty)
                .help("Save every account as an otpauth:// URL, one per line, for Import or another app")
        }
        .background(HostWindowReader(host: host))
        .alert("Export secrets in plain text?", isPresented: $confirming) {
            Button("Export…", role: .destructive, action: choosePlace)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file holds every account's secret, unencrypted. Anyone who can read it "
                + "can generate your codes. Keep it somewhere safe and delete it when you're done.")
        }
    }

    /// A sheet on the Settings window, like Import's picker. NSSavePanel rather than
    /// fileExporter so the model writes the file itself, with owner-only permissions.
    ///
    /// The window is the one this row lives in, never `NSApp.keyWindow`: this runs from
    /// the warning alert's button, while that alert's sheet is still key and closing,
    /// and a panel attached to it vanished along with it. On the Settings window,
    /// AppKit queues the panel until the alert's sheet has gone.
    private func choosePlace() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "menu_otp_export.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let save = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            do {
                try model.export(to: url)
                let count = model.accounts.count
                status = "Exported \(count) account\(count == 1 ? "" : "s")."
            } catch {
                status = ""
                NSApp.presentError(error)
            }
        }
        if let window = host.window {
            panel.beginSheetModal(for: window, completionHandler: save)
        } else {
            save(panel.runModal())
        }
    }
}

/// The window a SwiftUI view is in, for AppKit calls that need one. A class, so
/// setting it from `HostWindowReader` doesn't redraw the view that holds it.
final class HostWindow {
    weak var window: NSWindow?
}

struct HostWindowReader: NSViewRepresentable {
    let host: HostWindow

    func makeNSView(context: Context) -> NSView { Reader(host: host) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Reader: NSView {
        let host: HostWindow

        init(host: HostWindow) {
            self.host = host
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { host.window = window }
        }
    }
}

struct LoginItemRow: View {
    let loginItem: LoginItem
    @State private var isOn = false
    @State private var needsApproval = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Open at login", isOn: Binding(get: { isOn }, set: { set($0) }))
            if needsApproval {
                HStack(spacing: 4) {
                    Text("Allow it in System Settings → General → Login Items.")
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        needsApproval = loginItem.needsApproval
        isOn = loginItem.isEnabled || needsApproval
    }

    private func set(_ on: Bool) {
        do {
            try loginItem.setEnabled(on)
            error = ""
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }
}
