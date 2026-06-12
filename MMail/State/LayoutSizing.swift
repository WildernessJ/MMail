import Foundation

/// Pure, SwiftUI-free layout-sizing seams for the resizable-columns feature.
///
/// All sidebar/list sizing decisions live here so they are unit-testable without
/// instantiating any view or `AppModel`. `SidebarSize` is the three-way folder-sidebar
/// preset; `clampListWidth` is the single authority for the mail-list width bounds.
/// The `LayoutDefaultsKey` constants + the keyless load accessors keep read and write
/// keyed identically (a write/read key mismatch becomes structurally impossible).

/// Folder-sidebar size preset. `String`-`RawRepresentable` for UserDefaults persistence,
/// `CaseIterable` for completeness. `medium` reproduces today's layout exactly.
enum SidebarSize: String, CaseIterable {
    case small
    case medium
    case large

    /// Column width in points. `medium == 232` is contractual (today's value);
    /// `small`/`large` are visual-tunable, only the strict ordering is asserted.
    var width: CGFloat {
        switch self {
        case .small: return 64
        case .medium: return 232
        case .large: return 280
        }
    }

    /// Whether folder/label text is shown. `small` is icon-only.
    var showsLabels: Bool {
        switch self {
        case .small: return false
        case .medium, .large: return true
        }
    }

    /// Next size in the cycle: small → medium → large → small.
    var next: SidebarSize {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return .small
        }
    }
}

/// Clamp a raw mail-list width into the inclusive bounds `[300, 600]`. The single
/// authority for the list width bounds — applied on every drag update, every
/// programmatic set, and on load from persistence.
func clampListWidth(_ raw: CGFloat) -> CGFloat {
    min(max(raw, 300), 600)
}

/// Canonical UserDefaults keys for the resizable-columns persistence. Both the load
/// accessors below and every `AppModel` persist site MUST write through these constants.
enum LayoutDefaultsKey {
    static let sidebarSize = "mmail.sidebarSize"
    static let listWidth = "mmail.listWidth"
}

/// Load the persisted sidebar size, falling back to `.medium` for a missing or
/// unrecognized stored value. View/`AppModel`-free; delegates parsing to `SidebarSize`.
func loadSidebarSize(_ d: UserDefaults) -> SidebarSize {
    SidebarSize(rawValue: d.string(forKey: LayoutDefaultsKey.sidebarSize) ?? "") ?? .medium
}

/// Load the persisted list width, defaulting to 380 when missing and clamping on load
/// so a corrupt/out-of-range stored value can never produce an unusable layout.
/// View/`AppModel`-free; delegates clamping entirely to `clampListWidth`.
func loadListWidth(_ d: UserDefaults) -> CGFloat {
    // `object(forKey:) as? Double` (not `double(forKey:)`) so a MISSING key is nil → 380, since `double(forKey:)` would return 0.0 and defeat the `?? 380` default.
    clampListWidth((d.object(forKey: LayoutDefaultsKey.listWidth) as? Double).map { CGFloat($0) } ?? 380)
}
