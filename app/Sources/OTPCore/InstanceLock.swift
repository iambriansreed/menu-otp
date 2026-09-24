import Foundation

public struct InstanceLockError: LocalizedError {
    public let path: URL
    public let code: POSIXErrorCode

    public var errorDescription: String? {
        "\(path.path) couldn't be opened (\(POSIXError(code).localizedDescription))."
    }
}

/// One running instance per data directory, like Electron's
/// requestSingleInstanceLock() (which is per-userData). An flock(2) on a file in
/// the data directory: the kernel drops it when the process dies, so a crash can
/// never leave a stale lock behind. Demo mode uses its own data directory, so a
/// demo instance runs alongside the real one.
public final class InstanceLock {
    private let fd: Int32

    private init(fd: Int32) {
        self.fd = fd
    }

    /// nil if another process (or another InstanceLock in this one) holds the lock.
    /// Throws when the lock file can't be opened or locked for any other reason (an
    /// unwritable or missing directory, say), which must not be mistaken for "already
    /// running": that case quits quietly, and the user would never learn why.
    public static func acquire(at path: URL) throws -> InstanceLock? {
        let fd = open(path.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw InstanceLockError(path: path, code: currentCode()) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = currentCode()
            close(fd)
            if code == .EWOULDBLOCK { return nil }
            throw InstanceLockError(path: path, code: code)
        }
        return InstanceLock(fd: fd)
    }

    private static func currentCode() -> POSIXErrorCode {
        POSIXErrorCode(rawValue: errno) ?? .EIO
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}
