import Foundation
import OSLog

/// Persists the image-proxy HMAC signing secret in a private `0600` fallback file
/// (under `~/Library/Application Support/MMail/`) so it survives an unsigned
/// rebuild that invalidates the Keychain item. The Keychain remains primary; this
/// is only a backstop. Splits into PURE decision helpers (resolve / shouldSyncFile
/// / saveErrorMessage — unit-testable with injected strings, no I/O) and the impure
/// file read/write + `loadAndSync` wrapper that performs the actual disk access.
struct ProxySecretStore {
    let directory: URL

    var fileURL: URL { directory.appendingPathComponent("proxy-secret") }

    private static let log = Logger(subsystem: "studio.cobalt.MMail", category: "ProxySecretStore")

    // MARK: - Pure decision helpers (no I/O)

    /// Resolve the effective secret: trimmed Keychain value if non-empty, else
    /// trimmed file value if non-empty, else nil. Performs NO Keychain or
    /// filesystem access — caller injects the source strings.
    static func resolve(keychain: String?, file: String?) -> String? {
        if let k = keychain?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
            return k
        }
        if let f = file?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            return f
        }
        return nil
    }

    /// True when the fallback file should be (re)written to match the authoritative
    /// Keychain secret: the effective secret came from a non-blank Keychain and the
    /// file diverges (absent, blank, or holding a different value). False when the
    /// effective value came from the file (Keychain blank), when nothing is set, or
    /// when the file already equals the secret (idempotent).
    static func shouldSyncFile(effective: String?, keychainTrimmed: String?, fileTrimmed: String?) -> Bool {
        effective != nil
            && effective == keychainTrimmed
            && (keychainTrimmed?.isEmpty == false)
            && fileTrimmed != effective
    }

    /// User-facing save-failure message, or nil when both stores succeeded.
    static func saveErrorMessage(keychainOK: Bool, fileOK: Bool) -> String? {
        switch (keychainOK, fileOK) {
        case (true, true):
            return nil
        case (false, true):
            return "Couldn't save the signing secret to the macOS Keychain. It was written to the local fallback file."
        case (true, false):
            return "Saved the signing secret to the macOS Keychain, but couldn't write the local fallback file (the proxy may not survive an unsigned rebuild)."
        case (false, false):
            return "Couldn't save the signing secret to the macOS Keychain or the local fallback file."
        }
    }

    // MARK: - File I/O

    /// Read the trimmed secret from `fileURL`, or nil if the file is missing/blank.
    func read() -> String? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Atomically write the trimmed secret to `fileURL` at mode `0600`: write a
    /// `0600` temp file in the same directory via POSIX `open`, then `rename(2)` it
    /// into place. Never throws; returns whether the write succeeded. On any failure
    /// the temp file is cleaned up.
    @discardableResult
    func write(_ secret: String) -> Bool {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Self.log.error("proxy-secret: failed to create directory: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let tmpURL = directory.appendingPathComponent("proxy-secret.tmp-\(UUID().uuidString)")
        let bytes = Array(trimmed.utf8)

        let fd = tmpURL.path.withCString { open($0, O_CREAT | O_WRONLY | O_TRUNC, 0o600) }
        guard fd >= 0 else {
            Self.log.error("proxy-secret: open(temp) failed (errno \(errno, privacy: .public))")
            return false
        }

        // Returns nil on success, or the write(2) errno captured at the point of
        // failure (BEFORE close(fd), which can clobber errno).
        let writeErrno = bytes.withUnsafeBytes { buf -> Int32? in
            var offset = 0
            while offset < buf.count {
                let n = Foundation.write(fd, buf.baseAddress!.advanced(by: offset), buf.count - offset)
                if n <= 0 { return errno }
                offset += n
            }
            return nil
        }
        close(fd)

        if let writeErrno {
            Self.log.error("proxy-secret: write(temp) failed (errno \(writeErrno, privacy: .public))")
            try? FileManager.default.removeItem(at: tmpURL)
            return false
        }

        let renamed = tmpURL.path.withCString { src in
            fileURL.path.withCString { dst in
                rename(src, dst)
            }
        }
        guard renamed == 0 else {
            Self.log.error("proxy-secret: rename failed (errno \(errno, privacy: .public))")
            try? FileManager.default.removeItem(at: tmpURL)
            return false
        }
        return true
    }

    /// Read the file, resolve against the Keychain secret, sync the file when the
    /// Keychain is authoritative and the file diverges, and return the effective
    /// secret. A sync-write failure is logged but does not break the read.
    func loadAndSync(keychainSecret: String?) -> String? {
        let fileValue = read()
        let effective = Self.resolve(keychain: keychainSecret, file: fileValue)
        if Self.shouldSyncFile(
            effective: effective,
            keychainTrimmed: keychainSecret?.trimmingCharacters(in: .whitespacesAndNewlines),
            fileTrimmed: fileValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        ), let effective {
            if !write(effective) {
                Self.log.error("proxy-secret: sync write to fallback file failed; read is unaffected")
            }
        }
        return effective
    }

    // MARK: - Default instance

    static let `default` = ProxySecretStore(
        directory: try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("MMail")
    )
}
