import CoreGraphics
import CoreImage
import Foundation

/// Reads an account out of the QR codes in an image: a grab of the part of the screen
/// where a site shows its two-factor setup code.
public enum QRCode {
    public enum ScanError: LocalizedError, Equatable {
        case noCode
        case notOTPAuth
        /// Google Authenticator's export, a protobuf of many accounts, not one URL
        case migration
        case invalid
        case noAccountName

        public var errorDescription: String? {
            switch self {
            case .noCode: "No QR code found there. Select the whole code and try again."
            case .notOTPAuth: "That QR code isn't a two-factor setup code (otpauth://)."
            case .migration: "That's a Google Authenticator export, which can't be read. Scan each account's own setup code instead."
            case .invalid: "That QR code's otpauth:// URL isn't valid."
            case .noAccountName: "That QR code has no account name."
            }
        }
    }

    /// The text of every QR code in `image`.
    ///
    /// CoreImage's detector rather than Vision's: Vision's requests need an inference
    /// context that virtual machines, CI's macOS runners included, can fail to create.
    public static func messages(in image: CGImage) -> [String] {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: CIImage(cgImage: image)) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    /// The account in the first code that parses as one. A selection can catch other
    /// codes beside the setup code, so failing that, the most useful explanation among
    /// them, whatever order they were found in.
    public static func account(from messages: [String]) -> Result<Account, ScanError> {
        let parsed = messages.compactMap(OTPAuthURL.parse)
        // An account name is required everywhere an account comes in (see AccountsModel)
        if let account = parsed.first(where: { !$0.account.isEmpty }) { return .success(account) }
        if !parsed.isEmpty { return .failure(.noAccountName) }

        let lowered = messages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if lowered.contains(where: { $0.hasPrefix("otpauth-migration:") }) { return .failure(.migration) }
        if lowered.contains(where: { $0.hasPrefix("otpauth:") }) { return .failure(.invalid) }
        return .failure(messages.isEmpty ? .noCode : .notOTPAuth)
    }
}
