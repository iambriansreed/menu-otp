import AppKit
import OTPCore

/// `app/scripts/demo.sh --snapshot <dir>`: puts the popover and Settings on screen in
/// a few states and saves each window with `screencapture -l`, so the UI can be
/// checked visually without clicking anything. Demo mode only. (Offscreen
/// rendering was tried and doesn't work: cacheDisplay drops SwiftUI-drawn content
/// and ImageRenderer draws placeholders for AppKit-backed controls.)
@MainActor
final class Snapshots {
    private let app: AppDelegate
    private let directory: URL

    init(app: AppDelegate, directory: URL) {
        self.app = app
        self.directory = directory
    }

    func start() {
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let savedClipboard = Clipboard.snapshot()
            await run()
            Clipboard.restore(savedClipboard)
            exit(0)
        }
    }

    private func run() async {
        let menu = app.menuController!
        let settings = app.settingsController!
        for _ in 0..<50 where MenuPanelController.placedFrame(of: app.statusItem) == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Demo URLs carry no icons: give a few accounts one of each kind, and hide
        // one, so every row style is on screen. With --real-icons (for the website's
        // screenshots) the icons are the services' real favicons instead, fetched
        // from the icon services. (Demo mode: this only ever writes to the throwaway
        // demo directory.)
        if CommandLine.arguments.contains("--real-icons") {
            await app.model.backfillIcons()
        }
        report {
            try app.model.mutate { list in
                guard list.count >= 3 else { return }
                if !CommandLine.arguments.contains("--real-icons") {
                    list[0].icon = "💳"
                    list[1].icon = Self.sampleFavicon()
                }
                list[2].hidden = true
            }
        }

        menu.show()
        await settle()
        capture(menu.panel, "menu")

        // Found by action, not a fixed index: the title and its separator come first
        let accountRows = menu.rowsForTesting.indices.filter { index in
            if case .copy = menu.rowsForTesting[index].action { return true }
            return false
        }

        // The second account (GitHub in the demo data)
        menu.highlightForTesting(accountRows.dropFirst().first)
        await settle()
        capture(menu.panel, "menu-highlighted")

        // The last account row. In a menu taller than the screen it must have
        // scrolled into view; with the stock demo data nothing scrolls.
        if let last = accountRows.last {
            menu.highlightForTesting(last)
            await settle()
            capture(menu.panel, "menu-last-row")
        }

        if let first = accountRows.first { menu.activate(index: first) }
        await settle()
        capture(menu.panel, "menu-copied")
        menu.hide()

        menu.show()
        await settle()
        capture(menu.panel, "menu-last-clicked")
        menu.hide()

        await compareWithSystemMenu()

        settings.show()
        await settle(0.6)
        capture(settings.window, "settings")
        // The whole of Settings, down to General and the version, for the website: the
        // window made as tall as its scrolled content
        if let window = settings.window, let content = scrollView(in: window.contentView)?.documentView {
            window.setContentSize(NSSize(width: window.contentLayoutRect.width, height: ceil(content.frame.height)))
            await settle(0.6)
            capture(window, "settings-full")
        }
        settings.close()

        settings.initialState = .init(editing: app.model.accounts.first?.identity, addTab: .manual)
        settings.show()
        await settle(0.6)
        capture(settings.window, "settings-editing")
        settings.close()

        settings.initialState = .init(addTab: .importFile)
        settings.show()
        await settle(0.6)
        capture(settings.window, "settings-import")
        settings.close()

        settings.initialState = .init(reordering: true)
        settings.show()
        await settle(0.6)
        capture(settings.window, "settings-reorder")
        settings.close()
    }

    /// A 32x32 PNG data URL, standing in for a fetched favicon.
    static func sampleFavicon() -> String {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return "" }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    /// Our menu and a real NSMenu with the same rows, opened at the same spot (so over
    /// the same backdrop, which the menu material blends in), in light and dark mode,
    /// plain and with the first account highlighted: compare-<mode>-ours[-highlighted]
    /// and compare-<mode>-system[-highlighted]. Their colours should match.
    private func compareWithSystemMenu() async {
        let menu = app.menuController!
        let firstItem = menu.rowsForTesting.firstIndex {
            if case .copy = $0.action { return true } else { return false }
        }
        for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            menu.show()
            await settle(0.5)
            capture(menu.panel, "compare-\(mode)-ours")
            if let firstItem {
                menu.highlightForTesting(firstItem)
                await settle()
                capture(menu.panel, "compare-\(mode)-ours-highlighted")
            }
            let topLeft = NSPoint(x: menu.panel.frame.minX, y: menu.panel.frame.maxY)
            menu.hide()
            await settle()
            popUpSystemMenu(at: topLeft, name: "compare-\(mode)-system")
            await settle()
        }
        NSApp.appearance = nil
    }

    /// NSMenu.popUp runs its own tracking loop until the menu closes, so the captures
    /// happen from timers that fire inside that loop (in .common modes).
    private func popUpSystemMenu(at topLeft: NSPoint, name: String) {
        let system = NSMenu()
        system.addItem(NSMenuItem.sectionHeader(title: "Accounts"))
        for account in app.model.accounts where !account.hidden {
            system.addItem(withTitle: account.label, action: nil, keyEquivalent: "")
        }
        system.addItem(.separator())
        system.addItem(withTitle: "\(AppEnvironment.appName) Settings...", action: nil, keyEquivalent: "")
        system.addItem(withTitle: "Quit \(AppEnvironment.appName)", action: nil, keyEquivalent: "q")
        // Enabled without targets, so they draw like real items
        system.autoenablesItems = false

        let after = { (seconds: Double, work: @escaping @MainActor () -> Void) in
            let timer = Timer(timeInterval: seconds, repeats: false) { _ in MainActor.assumeIsolated(work) }
            RunLoop.main.add(timer, forMode: .common)
        }
        after(0.5) { self.captureMenuWindow(name) }
        after(0.7) {
            // Down arrow highlights the first item (the header can't be highlighted)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 125, keyDown: true)
            down?.postToPid(getpid())
            CGEvent(keyboardEventSource: nil, virtualKey: 125, keyDown: false)?.postToPid(getpid())
        }
        after(1.1) { self.captureMenuWindow("\(name)-highlighted") }
        after(1.3) { system.cancelTracking() }
        system.popUp(positioning: nil, at: topLeft, in: nil)
    }

    /// The open NSMenu's window, found among this process's on-screen windows at the
    /// pop-up menu level.
    private func captureMenuWindow(_ name: String) {
        let level = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let id = windows.first {
            ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() && ($0[kCGWindowLayer as String] as? Int) == level
        }?[kCGWindowNumber as String] as? Int
        guard let id else {
            print("snapshot \(name): FAILED (no menu window)")
            return
        }
        capture(windowID: id, name)
    }

    private func scrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        return view as? NSScrollView ?? view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }

    private func capture(_ window: NSWindow?, _ name: String) {
        guard let window else {
            print("snapshot \(name): FAILED (no window)")
            return
        }
        capture(windowID: window.windowNumber, name)
    }

    private func capture(windowID: Int, _ name: String) {
        let url = directory.appendingPathComponent("\(name).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(windowID), url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("snapshot \(name): FAILED (\(error.localizedDescription))")
            return
        }
        print("snapshot \(name): \(process.terminationStatus == 0 ? url.path : "FAILED (exit \(process.terminationStatus))")")
    }

    private func settle(_ seconds: Double = 0.3) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
