import CryptoKit
import Foundation

public struct StoreLoad: Equatable, Sendable {
    public var accounts: [Account]
    /// Set when an unreadable accounts.enc was moved here instead of being loaded.
    /// The app must tell the user: they are looking at an empty list.
    public var setAside: URL?

    public init(accounts: [Account], setAside: URL? = nil) {
        self.accounts = accounts
        self.setAside = setAside
    }
}

public enum AccountStoreError: LocalizedError {
    case cannotSetAside(file: URL, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case let .cannotSetAside(file, underlying):
            "\(file.lastPathComponent) couldn't be read, and moving it aside failed "
                + "(\(underlying.localizedDescription)). Nothing was changed."
        }
    }
}

/// accounts.enc: "MOTP1" followed by an AES-256-GCM sealed box (nonce + ciphertext +
/// tag) of the JSON-encoded `[Account]`.
public final class AccountStore {
    static let magic = Data("MOTP1".utf8)

    public let fileURL: URL
    private let keyProvider: KeyProvider

    public init(fileURL: URL, keyProvider: KeyProvider) {
        self.fileURL = fileURL
        self.keyProvider = keyProvider
    }

    /// No file yet -> no accounts, without touching the Keychain, so a first launch
    /// doesn't prompt until there is something to save.
    ///
    /// A key that can't be *obtained* (Keychain denied, locked, errored) throws and
    /// leaves the file alone: the caller must stop rather than save over it.
    ///
    /// A file that can't be *decrypted or parsed* with a key we do have is moved
    /// aside to `accounts.enc.unreadable-<epoch>` and reported in `setAside`. The
    /// Electron app deleted such a file outright; moving it keeps a recovery path for
    /// the only copy of the user's secrets. If even the move fails this throws, so
    /// the next save can't replace the file.
    public func load() throws -> StoreLoad {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return StoreLoad(accounts: []) }
        let key = try keyProvider.key()
        let data = try Data(contentsOf: fileURL)
        do {
            guard data.starts(with: Self.magic) else { throw CocoaError(.fileReadCorruptFile) }
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.magic.count))
            let json = try AES.GCM.open(box, using: key)
            return StoreLoad(accounts: try JSONDecoder().decode([Account].self, from: json))
        } catch {
            let aside = fileURL.deletingLastPathComponent().appendingPathComponent(
                "\(fileURL.lastPathComponent).unreadable-\(Int(Date().timeIntervalSince1970))"
            )
            do {
                try FileManager.default.moveItem(at: fileURL, to: aside)
            } catch {
                throw AccountStoreError.cannotSetAside(file: fileURL, underlying: error)
            }
            return StoreLoad(accounts: [], setAside: aside)
        }
    }

    /// Encrypts to a temp file beside the real one, flushes it to the disk, then
    /// rename(2)s it into place and flushes the directory. rename is atomic on one
    /// volume, so a crash mid-write leaves the old file or the new one, never half of
    /// one (which load() would treat as unreadable).
    ///
    /// The flushes are for power loss rather than a crash: without them the rename can
    /// reach the disk before the data it points at, leaving an empty accounts.enc, the
    /// only copy of the user's secrets. F_FULLFSYNC, not fsync: on macOS fsync only hands
    /// the data to the drive, whose cache can still lose it.
    public func save(_ accounts: [Account]) throws {
        let key = try keyProvider.key()
        let json = try JSONEncoder().encode(accounts)
        guard let sealed = try AES.GCM.seal(json, using: key).combined else {
            throw CocoaError(.fileWriteUnknown)
        }
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent("\(fileURL.lastPathComponent).tmp")

        // A temp file left by a crash could have any mode; O_EXCL below then creates a
        // fresh one with 0600 rather than reusing it
        unlink(tmp.path)
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw Self.writeError() }
        do {
            defer { close(fd) }
            try Self.writeAll(Self.magic + sealed, to: fd)
            guard Self.fullSync(fd) else { throw Self.writeError() }
        } catch {
            unlink(tmp.path)
            throw error
        }
        guard rename(tmp.path, fileURL.path) == 0 else { throw Self.writeError() }
        // The rename lives in the directory's entry; flush that too. Best effort: the
        // data is already safe, and a failure here isn't worth failing the save over.
        let dirFD = open(dir.path, O_RDONLY)
        if dirFD >= 0 {
            _ = Self.fullSync(dirFD)
            close(dirFD)
        }
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw writeError()
                }
                offset += written
            }
        }
    }

    /// F_FULLFSYNC where the filesystem supports it, plain fsync where it doesn't (some
    /// network and FAT volumes).
    private static func fullSync(_ fd: Int32) -> Bool {
        fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0
    }

    private static func writeError() -> CocoaError {
        CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(.init(rawValue: errno) ?? .EIO)])
    }
}
