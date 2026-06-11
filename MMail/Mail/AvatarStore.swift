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

    /// Center-crop the source to a square, downscale to at most 256px, PNG-encode,
    /// and write to `<id>.png`. Runs synchronously on the main thread (lockFocus is
    /// main-thread-only). Returns false (logged) on any nil/throw; never crashes.
    @discardableResult
    func save(_ image: NSImage, for id: String) -> Bool {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Self.log.error("avatar: no CGImage")
            return false
        }
        let rect = AvatarImage.squareCropRect(sourceWidth: CGFloat(cg.width), sourceHeight: CGFloat(cg.height))
        guard let cropped = cg.cropping(to: rect) else { return false }

        // Downscale (never upscale): the crop is square so width == height.
        let targetEdge = min(cropped.width, 256)
        let out = NSImage(size: NSSize(width: targetEdge, height: targetEdge))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cropped, size: .zero).draw(
            in: NSRect(x: 0, y: 0, width: targetEdge, height: targetEdge),
            from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()

        guard let tiff = out.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: fileURL(for: id))
            return true
        } catch {
            Self.log.error("avatar: write failed \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Read the file's bytes fresh and build a NEW `NSImage` on every call (no
    /// name/URL cache), so a replaced file always loads its new contents.
    func load(for id: String) -> NSImage? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return NSImage(data: data)
    }

    /// Delete the stored file. A missing file is not an error — the post-condition
    /// "no file at <id>.png" already holds — so a not-found error counts as success
    /// (no fileExists pre-check, to avoid a check-then-delete race).
    @discardableResult
    func remove(for id: String) -> Bool {
        do {
            try FileManager.default.removeItem(at: fileURL(for: id))
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            Self.log.error("avatar: remove failed \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

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
