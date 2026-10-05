import AppKit
import CoreGraphics
import ImageIO

/// The system's own area selection (the ⌘⇧4 crosshair; Space switches to picking a
/// window), run as `screencapture -i`, for scanning a setup page's QR code.
enum ScreenCapture {
    enum Failure: LocalizedError {
        case permission

        var errorDescription: String? {
            "Allow Menu OTP under Screen & System Audio Recording in System Settings, then try again."
        }
    }

    /// The Privacy & Security pane that holds the Screen Recording switch.
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    /// Throws `Failure.permission` when the app can't see other apps' windows.
    ///
    /// Without the permission the grab still succeeds, but holds only the wallpaper and
    /// the menu bar: other apps' windows are left out, and the scan would blame the
    /// selection. The first request shows the system's prompt and adds the app to the
    /// list in System Settings; later ones show nothing.
    static func checkPermission() throws {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw Failure.permission
        }
    }

    /// The selected area, or nil when the selection was cancelled (Escape). Call
    /// `checkPermission` first.
    static func selectArea() async throws -> CGImage? {
        // The grab shows the secret, so it goes in a directory only we can read and is
        // gone before the scan starts
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent("menu-otp-scan-\(UUID().uuidString)")
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: directory) }
        let file = directory.appendingPathComponent("selection.png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i select an area, -x no shutter sound, -o no shadow on a picked window
        process.arguments = ["-i", "-x", "-o", "-t", "png", file.path]
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in done.resume() }
            do { try process.run() } catch { done.resume(throwing: error) }
        }

        // No file means the selection was cancelled. Read into memory first: an image
        // source on the file itself may decode lazily, after the file is deleted.
        guard let data = try? Data(contentsOf: file),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
