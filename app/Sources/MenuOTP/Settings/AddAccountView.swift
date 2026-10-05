import AppKit
import OTPCore
import SwiftUI
import UniformTypeIdentifiers

struct AddAccountView: View {
    enum Tab: Hashable {
        case screen
        case bulkImport
        case manual
    }

    let model: AccountsModel
    /// From Screen added (or updated) this account; Settings opens it for editing
    let onScanned: (AccountIdentity) -> Void

    @State private var tab: Tab
    @State private var otpURL = ""
    @State private var fields: AccountFields
    @State private var manualIconEditor: IconEditorModel
    @State private var error = ""
    /// What From Screen or Bulk Import last did
    @State private var status = ""
    @State private var isDropTargeted = false
    @State private var isScanning = false
    @State private var needsScreenPermission = false
    @State private var choosingFile: Bool
    @State private var host = HostWindow()

    init(
        model: AccountsModel, onScanned: @escaping (AccountIdentity) -> Void = { _ in },
        initialTab: Tab = .screen, openFilePicker: Bool = false
    ) {
        self.model = model
        self.onScanned = onScanned
        _tab = State(initialValue: initialTab)
        _choosingFile = State(initialValue: openFilePicker)
        // Built here rather than in onAppear: creating it mid-layout and inserting
        // the editor on the next pass sends SwiftUI round an AttributeGraph cycle
        let fields = AccountFields()
        _fields = State(initialValue: fields)
        _manualIconEditor = State(initialValue: IconEditorModel(
            icon: nil, url: nil, lookup: model.lookupFavicon,
            label: { (fields.issuer, fields.account) }
        ))
    }

    var body: some View {
        @Bindable var fields = fields
        VStack(alignment: .leading, spacing: 8) {
            // Across the whole card, like the form below it, under any SDK
            FullWidthSegmentedControl(
                label: "Add from",
                options: [("From Screen", Tab.screen), ("Bulk Import", Tab.bulkImport), ("Manual", Tab.manual)],
                selection: $tab
            )
            .frame(maxWidth: .infinity)
            // Sets the tabs apart from the form they switch, beyond the stack's spacing
            .padding(.bottom, 6)
            .onChange(of: tab) {
                // Messages belong to the tab that produced them
                error = ""
                status = ""
                needsScreenPermission = false
            }

            switch tab {
            case .screen:
                clickZone(
                    isScanning ? "Drag across the QR code, or press Escape" : "Click, then drag across a QR code on screen",
                    highlighted: isScanning, action: scanScreen
                )
                if !error.isEmpty {
                    HStack(spacing: 10) {
                        Text(error).font(.caption).foregroundStyle(.red)
                        if needsScreenPermission {
                            Spacer()
                            Button("Open System Settings") { NSWorkspace.shared.open(ScreenCapture.settingsURL) }
                        }
                    }
                }
            case .bulkImport:
                importDropZone
            case .manual:
                AccountFieldsGrid(fields: fields, iconEditor: manualIconEditor, otpURL: $otpURL, onSubmit: add)
            }

            if tab != .manual, !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            if tab == .manual {
                HStack(spacing: 10) {
                    Spacer()
                    if !error.isEmpty {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Button("Add Account", action: add).buttonStyle(.borderedProminent)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .background(HostWindowReader(host: host))
        // A sheet on the Settings window (same window, same Space), not a free-floating
        // panel. Any file with data in it: the contents decide what imports.
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.data]) { result in
            if case .success(let url) = result { importFile(url) }
        }
    }

    /// A dashed box that is one big button: From Screen's, and Bulk Import's drop zone.
    private func clickZone(_ text: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .frame(maxWidth: .infinity)
                .padding(20)
                .foregroundStyle(highlighted ? Color.accentColor : Color.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundStyle(highlighted ? Color.accentColor : Color(nsColor: .separatorColor))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var importDropZone: some View {
        clickZone("Click or drop a file — one otpauth:// URL per line", highlighted: isDropTargeted) {
            choosingFile = true
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in importFile(url) }
            }
            return true
        }
    }

    private func add() {
        // A URL, when one is given, is the whole account; otherwise the fields are
        let fromURL = !otpURL.trimmed.isEmpty
        let entry: Account
        switch tab {
        case .manual where fromURL:
            guard let parsed = OTPAuthURL.parse(otpURL) else {
                error = "Invalid otpauth:// URL."
                return
            }
            guard !parsed.account.isEmpty else {
                error = "That URL has no account name."
                return
            }
            entry = parsed
        case .manual:
            let account = fields.account.trimmed
            let secret = Account.normalizeSecret(fields.secret)
            guard !account.isEmpty, !secret.isEmpty else {
                error = "Paste a URL, or enter an Account and Secret."
                return
            }
            entry = Account(
                account: account,
                secret: secret,
                issuer: fields.issuer.trimmed,
                icon: manualIconEditor.currentIcon.nilIfEmpty,
                url: manualIconEditor.currentURL.nilIfEmpty
            )
        case .screen, .bulkImport:
            return
        }

        do {
            let stored = try model.add(entry)
            error = ""
            if fromURL {
                otpURL = ""
            } else {
                fields.clear()
                manualIconEditor.reset()
            }
            // No icon given: look one up from the URL/issuer
            Task { await model.autoFavicon(for: stored.identity) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The system's area selection, then the QR code in it, added like a pasted URL.
    private func scanScreen() {
        // Not .disabled while scanning: that would grey out the zone's prompt
        guard !isScanning else { return }
        error = ""
        status = ""
        needsScreenPermission = false
        do {
            try ScreenCapture.checkPermission()
        } catch {
            needsScreenPermission = true
            self.error = error.localizedDescription
            return
        }
        isScanning = true
        // Faded while the crosshair is up, so a code behind Settings can be seen and
        // selected. (A selection over the window grabs the faded window on top of the
        // code; the detector reads through it, see QRCodeTests.)
        let window = host.window
        window?.alphaValue = 0.3
        Task {
            defer {
                isScanning = false
                window?.alphaValue = 1
                // The selection belongs to another process, which may have left this app
                // inactive. Settings is an ordinary window and does activate.
                NSApp.activate()
                window?.makeKeyAndOrderFront(nil)
            }
            do {
                // Escape: nothing selected, nothing to say
                guard let image = try await ScreenCapture.selectArea() else { return }
                let stored = try model.add(QRCode.account(from: QRCode.messages(in: image)).get())
                status = "Added \(stored.label)."
                onScanned(stored.identity)
                Task { await model.autoFavicon(for: stored.identity) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// UTF-8, or UTF-16 with a byte-order mark; anything else is decoded lossily, so
    /// an unexpected file imports as skipped lines instead of failing outright.
    static func decodeText(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func importFile(_ url: URL) {
        // A file chosen in the picker comes with security-scoped access, which is only
        // good while held; read it up front
        let scoped = url.startAccessingSecurityScopedResource()
        let data = Result { try Data(contentsOf: url) }
        if scoped { url.stopAccessingSecurityScopedResource() }
        Task {
            do {
                let text = Self.decodeText(try data.get())
                let summary = try model.importText(text)
                status = summary.text
                _ = await model.fillMissingIcons(summary.imported) { done, total in
                    status = "\(summary.text) — looking up icons \(done)/\(total)…"
                }
                status = summary.text
            } catch {
                status = "Couldn't import: \(error.localizedDescription)"
            }
        }
    }
}
