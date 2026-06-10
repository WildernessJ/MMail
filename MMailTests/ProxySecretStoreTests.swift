import Testing
import Foundation
@testable import MMail

/// Unit tests for `ProxySecretStore`: the PURE decision helpers (`resolve`,
/// `shouldSyncFile`, `saveErrorMessage` — injected strings, NO I/O) and the impure
/// file round-trip + `loadAndSync` sync behaviour (real I/O in per-test temp dirs).
/// All file tests use a fresh `FileManager.default.temporaryDirectory` subdir so
/// nothing touches the real `~/Library/Application Support/MMail/`.
@Suite struct ProxySecretStoreTests {

    /// A fresh, empty temp directory unique to one test (not yet created on disk;
    /// `write` is responsible for creating it).
    private func tempStore() -> ProxySecretStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return ProxySecretStore(directory: dir)
    }

    // MARK: - resolve (pure, injected strings, NO I/O) — SC-002

    @Test func resolveKeychainWinsOverFile() {
        #expect(ProxySecretStore.resolve(keychain: "K", file: "F") == "K")
    }

    @Test func resolveKeychainBlankFallsBackToFile() {
        #expect(ProxySecretStore.resolve(keychain: "   ", file: "F") == "F")
        #expect(ProxySecretStore.resolve(keychain: nil, file: "F") == "F")
    }

    @Test func resolveBothBlankIsNil() {
        #expect(ProxySecretStore.resolve(keychain: "  ", file: "  ") == nil)
        #expect(ProxySecretStore.resolve(keychain: nil, file: nil) == nil)
    }

    @Test func resolveWhitespaceOnlyFileIsNil() {
        #expect(ProxySecretStore.resolve(keychain: nil, file: " \n\t ") == nil)
    }

    // MARK: - shouldSyncFile (pure) — SC-004

    @Test func shouldSyncMigratesWhenFileAbsent() {
        #expect(ProxySecretStore.shouldSyncFile(effective: "K", keychainTrimmed: "K", fileTrimmed: nil) == true)
    }

    @Test func shouldSyncCorrectsDivergence() {
        #expect(ProxySecretStore.shouldSyncFile(effective: "K", keychainTrimmed: "K", fileTrimmed: "F") == true)
    }

    @Test func shouldSyncIsIdempotentWhenEqual() {
        #expect(ProxySecretStore.shouldSyncFile(effective: "K", keychainTrimmed: "K", fileTrimmed: "K") == false)
    }

    @Test func shouldSyncFalseWhenCameFromFile() {
        #expect(ProxySecretStore.shouldSyncFile(effective: "F", keychainTrimmed: nil, fileTrimmed: "F") == false)
    }

    @Test func shouldSyncFalseWhenNoSecretAnywhere() {
        #expect(ProxySecretStore.shouldSyncFile(effective: nil, keychainTrimmed: nil, fileTrimmed: nil) == false)
    }

    // MARK: - saveErrorMessage (pure) — SC-006

    @Test func saveErrorBothOKIsNil() {
        #expect(ProxySecretStore.saveErrorMessage(keychainOK: true, fileOK: true) == nil)
    }

    @Test func saveErrorFileFailedMentionsFile() {
        let msg = ProxySecretStore.saveErrorMessage(keychainOK: true, fileOK: false)
        #expect(msg != nil)
        #expect(msg?.lowercased().contains("file") == true)
    }

    @Test func saveErrorKeychainFailedMentionsKeychain() {
        let msg = ProxySecretStore.saveErrorMessage(keychainOK: false, fileOK: true)
        #expect(msg != nil)
        #expect(msg?.lowercased().contains("keychain") == true)
    }

    @Test func saveErrorBothFailedIsNonNil() {
        #expect(ProxySecretStore.saveErrorMessage(keychainOK: false, fileOK: false) != nil)
    }

    // MARK: - file round-trip (real I/O in per-test temp dir) — SC-003

    @Test func writeThenReadRoundTrips() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.write("s") == true)
        #expect(store.read() == "s")
    }

    @Test func writtenFileHasMode0600() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.write("s") == true)
        let attrs = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        let perms = try #require(attrs[.posixPermissions] as? NSNumber)
        #expect(perms.int16Value == 0o600)
    }

    @Test func writtenRawBytesHaveNoTrailingNewline() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.write("s") == true)
        let raw = try Data(contentsOf: store.fileURL)
        #expect(raw == Data("s".utf8))
    }

    @Test func writeStoresTrimmedSecret() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.write("  s\n") == true)
        let raw = try Data(contentsOf: store.fileURL)
        #expect(raw == Data("s".utf8))
        #expect(store.read() == "s")
    }

    // MARK: - write failure — SC-006 (file-failure half)

    @Test func writeIntoUnwritableParentReturnsFalse() throws {
        // Create a 0o500 (read+execute, no write) directory; a store rooted at a
        // child of it cannot create its directory, so write must fail gracefully.
        let locked = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: locked)
        }
        let store = ProxySecretStore(directory: locked.appendingPathComponent("child"))
        #expect(store.write("s") == false)
    }

    // MARK: - loadAndSync (real I/O) — SC-004, SC-005

    @Test func loadAndSyncMigratesWhenFileAbsent() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.read() == nil)
        #expect(store.loadAndSync(keychainSecret: "K") == "K")
        #expect(store.read() == "K")
    }

    @Test func loadAndSyncCorrectsDivergence() {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.write("F") == true)
        #expect(store.loadAndSync(keychainSecret: "K") == "K")
        #expect(store.read() == "K")
    }

    @Test func loadAndSyncFromFileDoesNotRewrite() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.write("F") == true)
        let beforeMod = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date
        #expect(store.loadAndSync(keychainSecret: nil) == "F")
        #expect(store.read() == "F")
        let afterMod = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date
        #expect(beforeMod == afterMod, "no write should occur when the secret came from the file")
    }

    @Test func loadAndSyncIsIdempotentWhenFileMatchesKeychain() throws {
        // End-to-end idempotent path (SC-004): file already equals the Keychain
        // secret, so loadAndSync must return it WITHOUT rewriting the file. The
        // atomic write uses rename(2), which always yields a NEW inode, so an
        // unchanged st_ino proves no rewrite occurred.
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        #expect(store.write("K") == true)

        func inode(_ path: String) throws -> UInt64 {
            var st = stat()
            #expect(stat(path, &st) == 0)
            return UInt64(st.st_ino)
        }
        let beforeInode = try inode(store.fileURL.path)

        #expect(store.loadAndSync(keychainSecret: "K") == "K")

        let afterInode = try inode(store.fileURL.path)
        #expect(beforeInode == afterInode, "no rewrite should occur when the file already matches the Keychain secret")
    }

    // MARK: - loadAndSync: sync-write fails but read still works (spec scenario)

    @Test func loadAndSyncSurvivesSyncWriteFailure() throws {
        // Pre-create the store directory, then chmod it 0o500 so the internal
        // sync write (file absent + Keychain authoritative) fails. The read must
        // still yield "K".
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: store.directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: store.directory.path)
            try? FileManager.default.removeItem(at: store.directory)
        }
        #expect(store.read() == nil)
        #expect(store.loadAndSync(keychainSecret: "K") == "K")
    }
}
