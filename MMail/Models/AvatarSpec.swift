import Foundation

/// Pure, SwiftUI-free resolution of an account avatar's letters/color/usesImage.
/// The single place that decides avatar color and initials, unit-testable without
/// instantiating a view or touching disk.
struct AvatarSpec {
    let initials: String
    let gradientHex: [String]
    let usesImage: Bool

    static func resolve(displayName: String, email: String, customColorHex: String?, hasImage: Bool) -> AvatarSpec {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmedName.isEmpty ? email : trimmedName
        let initials = String(source.prefix(1)).uppercased()
        let gradientHex = customColorHex.map { [$0, $0] } ?? [Sender.stableColorHex(for: email), "1E2DB0"]
        return AvatarSpec(initials: initials, gradientHex: gradientHex, usesImage: hasImage)
    }
}

/// Pure, SwiftUI-free resolution of the unified "All" inbox tile's short text,
/// full label, and usesImage. Unlike `AvatarSpec` (single initial), the unified
/// tile uses up-to-3 characters of the custom name to preserve its identity.
struct AllInboxSpec {
    let tileText: String
    let label: String
    let usesImage: Bool

    static func resolve(name: String, hasImage: Bool) -> AllInboxSpec {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let tileText = trimmed.isEmpty ? "All" : String(trimmed.prefix(3))
        let label = trimmed.isEmpty ? "All inboxes" : trimmed
        return AllInboxSpec(tileText: tileText, label: label, usesImage: hasImage)
    }
}

/// Pure helpers for avatar image geometry. `CGRect`/`CGFloat` come from CoreGraphics
/// (re-exported by Foundation on Apple platforms) — no SwiftUI/AppKit needed here.
enum AvatarImage {
    /// Centered square crop rectangle in TOP-LEFT origin image coordinates
    /// (the convention of `CGImage.cropping(to:)`).
    static func squareCropRect(sourceWidth: CGFloat, sourceHeight: CGFloat) -> CGRect {
        let edge = min(sourceWidth, sourceHeight)
        let x = (sourceWidth - edge) / 2
        let y = (sourceHeight - edge) / 2
        return CGRect(x: x, y: y, width: edge, height: edge)
    }
}
