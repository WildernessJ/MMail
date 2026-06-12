import Foundation

/// Pure, SwiftUI-free layout-sizing seams for the resizable-columns feature.
///
/// All rail/sidebar/list sizing decisions live here so they are unit-testable without
/// instantiating any view or `AppModel`. `RailSize` is the three-way account-rail
/// preset; `clampSidebarWidth` and `clampListWidth` are the single authorities for the
/// folder-sidebar and mail-list width bounds. The `LayoutDefaultsKey` constants + the
/// keyless load accessors keep read and write keyed identically (a write/read key
/// mismatch becomes structurally impossible).

/// Account-rail size preset. `String`-`RawRepresentable` for UserDefaults persistence,
/// `CaseIterable` for completeness. `small` reproduces today's rail exactly (56pt column,
/// 38pt icon-only tiles); `medium` is bigger tiles still icon-only; `large` adds account
/// names beside the avatars.
enum RailSize: String, CaseIterable {
    case small
    case medium
    case large

    /// Rail column width in points. `small == 56` is contractual (today's rail,
    /// `AccountRailView.swift:47`); `medium`/`large` are visual-tunable, only the strict
    /// ordering is asserted (`large` is wide enough to fit account names).
    var width: CGFloat {
        switch self {
        case .small: return 56
        case .medium: return 76
        case .large: return 200
        }
    }

    /// Avatar tile edge in points. `small == 38` is contractual (today's tiles,
    /// `AccountRailView.swift:28/54/77`); `medium`/`large` are visual-tunable, only
    /// `small < large` and `medium > small` are asserted.
    var tileSize: CGFloat {
        switch self {
        case .small: return 38
        case .medium: return 48
        case .large: return 48
        }
    }

    /// Whether account names render beside the avatars. `small`/`medium` are icon-only;
    /// `large` shows names.
    var showsNames: Bool {
        switch self {
        case .small, .medium: return false
        case .large: return true
        }
    }

    /// Next size in the cycle: small → medium → large → small.
    var next: RailSize {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return .small
        }
    }
}

/// Clamp a raw folder-sidebar width into the inclusive bounds `[180, 400]`. The single
/// authority for the sidebar width bounds — applied on every drag update, every
/// programmatic set, and on load from persistence. The lower bound keeps folder labels
/// legible; the upper bound keeps the list/reader usable.
func clampSidebarWidth(_ raw: CGFloat) -> CGFloat {
    min(max(raw, 180), 400)
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
    static let railSize = "mmail.railSize"
    static let sidebarLabels = "mmail.sidebarLabels"
    static let sidebarWidth = "mmail.sidebarWidth"
    static let listWidth = "mmail.listWidth"
}

/// Load the persisted rail size, falling back to `.small` for a missing or unrecognized
/// stored value. View/`AppModel`-free; delegates parsing to `RailSize`.
func loadRailSize(_ d: UserDefaults) -> RailSize {
    RailSize(rawValue: d.string(forKey: LayoutDefaultsKey.railSize) ?? "") ?? .small
}

/// Load the persisted folder-labels visibility, defaulting to `true` (labels shown) when
/// missing. Uses `object(forKey:) as? Bool` so a MISSING key resolves to `true`, not the
/// `false` that `bool(forKey:)` would return.
func loadSidebarLabels(_ d: UserDefaults) -> Bool {
    d.object(forKey: LayoutDefaultsKey.sidebarLabels) as? Bool ?? true
}

/// Load the persisted folder-sidebar width, defaulting to 232 when missing and clamping
/// on load so a corrupt/out-of-range stored value can never produce an unusable layout.
/// View/`AppModel`-free; delegates clamping entirely to `clampSidebarWidth`.
func loadSidebarWidth(_ d: UserDefaults) -> CGFloat {
    // `object(forKey:) as? Double` (not `double(forKey:)`) so a MISSING key is nil → 232, since `double(forKey:)` would return 0.0 and defeat the `?? 232` default.
    clampSidebarWidth((d.object(forKey: LayoutDefaultsKey.sidebarWidth) as? Double).map { CGFloat($0) } ?? 232)
}

/// Load the persisted list width, defaulting to 380 when missing and clamping on load
/// so a corrupt/out-of-range stored value can never produce an unusable layout.
/// View/`AppModel`-free; delegates clamping entirely to `clampListWidth`.
func loadListWidth(_ d: UserDefaults) -> CGFloat {
    // `object(forKey:) as? Double` (not `double(forKey:)`) so a MISSING key is nil → 380, since `double(forKey:)` would return 0.0 and defeat the `?? 380` default.
    clampListWidth((d.object(forKey: LayoutDefaultsKey.listWidth) as? Double).map { CGFloat($0) } ?? 380)
}
