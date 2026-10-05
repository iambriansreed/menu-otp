import CoreImage
import Foundation
import Testing
@testable import OTPCore

private let figma = "otpauth://totp/Figma:me%40example.com?secret=MFCNSNW5&issuer=Figma"

/// A QR code for `message`, drawn the way a setup page shows one: dark modules on a white
/// page with a margin around it, several pixels per module.
private func qrImage(_ message: String) throws -> CGImage {
    let filter = try #require(CIFilter(name: "CIQRCodeGenerator"))
    filter.setValue(Data(message.utf8), forKey: "inputMessage")
    let code = try #require(filter.outputImage)
        .transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    let page = CIImage(color: .white).cropped(to: code.extent.insetBy(dx: -40, dy: -40))
    let image = code.composited(over: page)
    return try #require(CIContext().createCGImage(image, from: image.extent))
}

@Test func readsTheMessageOfAQRCodeInAnImage() throws {
    #expect(QRCode.messages(in: try qrImage(figma)) == [figma])
}

// From Screen fades Settings to 30% while the crosshair is up, so a selection over the
// window grabs the code with the window drawn on top
@Test(arguments: [0.12, 0.93])
func readsACodeThroughAFadedWindow(windowGray: Double) throws {
    let code = CIImage(cgImage: try qrImage(figma))
    let window = CIImage(color: CIColor(red: windowGray, green: windowGray, blue: windowGray, alpha: 0.3))
        .cropped(to: code.extent)
    let image = try #require(CIContext().createCGImage(window.composited(over: code), from: code.extent))
    #expect(QRCode.messages(in: image) == [figma])
}

@Test func findsNoMessagesInAnImageWithoutACode() throws {
    let blank = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
    let image = try #require(CIContext().createCGImage(blank, from: blank.extent))
    #expect(QRCode.messages(in: image).isEmpty)
}

@Test func anOTPAuthCodeIsTheAccount() {
    let scanned = QRCode.account(from: [figma])
    #expect(scanned == .success(Account(account: "me@example.com", secret: "MFCNSNW5", issuer: "Figma")))
}

// A selection can catch other codes beside the setup one
@Test func theFirstValidOTPAuthCodeWinsOverOtherCodes() {
    let scanned = QRCode.account(from: ["https://example.com", "otpauth://hotp/x?secret=ABCD", figma])
    #expect((try? scanned.get())?.issuer == "Figma")
}

@Test(arguments: [
    ([], QRCode.ScanError.noCode),
    (["https://example.com"], .notOTPAuth),
    (["otpauth-migration://offline?data=CjEKCkhlbGxvId6tvu8"], .migration),
    (["OTPAUTH://hotp/x?secret=ABCD"], .invalid),
    (["otpauth://totp/x?secret=NOT-BASE32!"], .invalid),
    (["otpauth://totp/?secret=ABCD&issuer=Figma"], .noAccountName),
    // The most useful explanation, whatever order the codes were found in
    (["https://example.com", "otpauth-migration://offline?data=x"], .migration),
])
func explainsWhyNoAccountWasFound(messages: [String], expected: QRCode.ScanError) {
    #expect(QRCode.account(from: messages) == .failure(expected))
}

@Test func everyScanErrorHasAMessage() {
    let all: [QRCode.ScanError] = [.noCode, .notOTPAuth, .migration, .invalid, .noAccountName]
    for error in all {
        #expect(!(error.errorDescription ?? "").isEmpty)
    }
}
