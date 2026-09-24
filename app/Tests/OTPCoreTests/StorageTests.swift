import CryptoKit
import Foundation
import Testing
@testable import OTPCore

func temporaryDirectory() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("menu-otp-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Counts key() calls and can be told to fail.
final class SpyKeyProvider: KeyProvider {
    var calls = 0
    var failure: Error?
    let inner = InMemoryKeyProvider()
    func key() throws -> SymmetricKey {
        calls += 1
        if let failure { throw failure }
        return try inner.key()
    }
}

private let sample = [
    Account(account: "jane@example.com", secret: "JBSWY3DP", issuer: "GitHub", icon: "🐙"),
    Account(account: "root", secret: "KRSXG5A", issuer: "AWS", hidden: true, iconCheckedAt: 42),
]

@Test func missingFileLoadsEmptyWithoutTouchingTheKey() throws {
    let spy = SpyKeyProvider()
    let store = AccountStore(fileURL: temporaryDirectory().appendingPathComponent("accounts.enc"), keyProvider: spy)
    #expect(try store.load() == StoreLoad(accounts: []))
    #expect(spy.calls == 0)
}

@Test func saveThenLoadRoundTrips() throws {
    let key = InMemoryKeyProvider()
    let url = temporaryDirectory().appendingPathComponent("accounts.enc")
    try AccountStore(fileURL: url, keyProvider: key).save(sample)
    #expect(try AccountStore(fileURL: url, keyProvider: key).load().accounts == sample)
}

@Test func fileIsEncryptedAndPrivate() throws {
    let url = temporaryDirectory().appendingPathComponent("accounts.enc")
    try AccountStore(fileURL: url, keyProvider: InMemoryKeyProvider()).save(sample)
    let bytes = try Data(contentsOf: url)
    #expect(bytes.starts(with: Data("MOTP1".utf8)))
    #expect(bytes.range(of: Data("JBSWY3DP".utf8)) == nil)
    let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    #expect(perms == 0o600)
    #expect(!FileManager.default.fileExists(atPath: url.path + ".tmp"))
}

/// A crash between writing the temp file and renaming it leaves the temp file behind,
/// possibly with a looser mode. The next save must neither inherit that mode nor fail.
@Test func leftoverTempFileNeitherBlocksNorLoosensTheNextSave() throws {
    let url = temporaryDirectory().appendingPathComponent("accounts.enc")
    FileManager.default.createFile(
        atPath: url.path + ".tmp", contents: Data("half a save".utf8), attributes: [.posixPermissions: 0o644]
    )
    let key = InMemoryKeyProvider()
    try AccountStore(fileURL: url, keyProvider: key).save(sample)
    #expect(try AccountStore(fileURL: url, keyProvider: key).load().accounts == sample)
    let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    #expect(perms == 0o600)
    #expect(!FileManager.default.fileExists(atPath: url.path + ".tmp"))
}

@Test func saveReplacesAnEarlierSave() throws {
    let url = temporaryDirectory().appendingPathComponent("accounts.enc")
    let key = InMemoryKeyProvider()
    try AccountStore(fileURL: url, keyProvider: key).save(sample)
    try AccountStore(fileURL: url, keyProvider: key).save([sample[0]])
    #expect(try AccountStore(fileURL: url, keyProvider: key).load().accounts == [sample[0]])
}

@Test func undecryptableFileIsMovedAsideNotDeleted() throws {
    let dir = temporaryDirectory()
    let url = dir.appendingPathComponent("accounts.enc")
    try AccountStore(fileURL: url, keyProvider: InMemoryKeyProvider()).save(sample)
    // A different key can't open it
    let loaded = try AccountStore(fileURL: url, keyProvider: InMemoryKeyProvider()).load()
    #expect(loaded.accounts == [])
    let aside = try #require(loaded.setAside)
    #expect(aside.lastPathComponent.hasPrefix("accounts.enc.unreadable-"))
    #expect(FileManager.default.fileExists(atPath: aside.path))
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func unreadableFileThatCantBeMovedThrowsAndStays() throws {
    let dir = temporaryDirectory()
    let url = dir.appendingPathComponent("accounts.enc")
    try AccountStore(fileURL: url, keyProvider: InMemoryKeyProvider()).save(sample)
    // A read-only directory: the file can be read but not renamed
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
    #expect(throws: AccountStoreError.self) {
        try AccountStore(fileURL: url, keyProvider: InMemoryKeyProvider()).load()
    }
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func keychainErrorsReadAsSentences() {
    let text = KeyProviderError.keychain(-25293).localizedDescription
    #expect(text.hasPrefix("Keychain access failed"))
    #expect(text.contains("-25293"))
}

@Test func keyFailureThrowsAndLeavesFileAlone() throws {
    let url = temporaryDirectory().appendingPathComponent("accounts.enc")
    try AccountStore(fileURL: url, keyProvider: InMemoryKeyProvider()).save(sample)
    let spy = SpyKeyProvider()
    spy.failure = KeyProviderError.keychain(-25293)
    #expect(throws: KeyProviderError.keychain(-25293)) { try AccountStore(fileURL: url, keyProvider: spy).load() }
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func instanceLockIsExclusiveUntilReleased() throws {
    let path = temporaryDirectory().appendingPathComponent("instance.lock")
    var first: InstanceLock? = try InstanceLock.acquire(at: path)
    #expect(first != nil)
    #expect(try InstanceLock.acquire(at: path) == nil)
    first = nil
    #expect(try InstanceLock.acquire(at: path) != nil)
}

/// A lock file that can't be opened is an error, not "already running": the app must
/// say what went wrong instead of quitting silently.
@Test func instanceLockThatCantBeOpenedThrows() {
    let path = temporaryDirectory().appendingPathComponent("missing/instance.lock")
    #expect(throws: InstanceLockError.self) { try InstanceLock.acquire(at: path) }
}

/// Touches the real login Keychain with a throwaway service name. Off by default:
/// run with MENU_OTP_KEYCHAIN_TESTS=1 (see the plan's Task 3 for the guarded command).
@Test(.enabled(if: ProcessInfo.processInfo.environment["MENU_OTP_KEYCHAIN_TESTS"] == "1"))
func keychainProviderCreatesThenReusesItsKey() throws {
    let service = "com.iambrian.menu-otp.tests.\(UUID().uuidString)"
    let provider = KeychainKeyProvider(service: service)
    defer { provider.deleteItem() }
    let created = try provider.key()
    let reread = try KeychainKeyProvider(service: service).key()
    #expect(created == reread)
}
