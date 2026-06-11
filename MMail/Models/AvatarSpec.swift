import Foundation

/// Pure, SwiftUI-free resolution of an account avatar's letters/color/usesImage.
/// The single place that decides avatar color and initials, unit-testable without
/// instantiating a view or touching disk.
struct AvatarSpec {
    let initials: String
    let gradientHex: [String]
    let usesImage: Bool

    static func resolve(displayName: String, email: String, customColorHex: String?, hasImage: Bool) -> AvatarSpec {
        AvatarSpec(initials: "", gradientHex: [], usesImage: false)
    }
}

/// Pure helpers for avatar image geometry. `CGRect`/`CGFloat` come from CoreGraphics
/// (re-exported by Foundation on Apple platforms) — no SwiftUI/AppKit needed here.
enum AvatarImage {
    /// Centered square crop rectangle in TOP-LEFT origin image coordinates
    /// (the convention of `CGImage.cropping(to:)`).
    static func squareCropRect(sourceWidth: CGFloat, sourceHeight: CGFloat) -> CGRect {
        .zero
    }
}
