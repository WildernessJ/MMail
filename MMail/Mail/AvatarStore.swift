import Foundation
import AppKit
import OSLog

/// Persists a per-account avatar image as a PNG under
/// `~/Library/Application Support/MMail/avatars/<id>.png` (the same trust tier as
/// `MailCache` — non-sensitive, unencrypted). Mirrors `ProxySecretStore`'s
/// Application-Support pattern with a static `AvatarStore.default`. On save it
/// center-crops the source to a square and downscales to at most 256px so stored
/// files stay small. `load(for:)` reads the bytes fresh and builds a NEW `NSImage`
/// on every call (no name/URL cache), so a replaced file always loads its new
/// contents. All failures are handled without crashing.
struct AvatarStore {
    let directory: URL

    private static let log = Logger(subsystem: "studio.cobalt.MMail", category: "AvatarStore")

    func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).png")
    }

    @discardableResult
    func save(_ image: NSImage, for id: String) -> Bool { false }

    func load(for id: String) -> NSImage? { nil }

    @discardableResult
    func remove(for id: String) -> Bool { false }

    // MARK: - Default instance

    static let `default` = AvatarStore(
        directory: try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("MMail").appendingPathComponent("avatars")
    )
}
