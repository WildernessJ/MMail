import Foundation

/// A pure, OS-free seam owning the three deterministic decisions behind MMail's
/// three-way appearance setting (System / Light / Dark). No instance holds state
/// and no function reads `UserDefaults`/the OS: the live appearance and the two
/// stored values are passed IN, so every function is deterministic and unit-testable.
///
/// `String`-backed so it round-trips through the `mmail.appearanceMode` UserDefaults
/// key by `rawValue`; `CaseIterable` so the Settings Picker / palette can enumerate it.
enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    /// Map a mode + the live system appearance to the derived `dark` bool (INV-2).
    /// `.system` follows the OS; `.light`/`.dark` are fixed regardless of the OS.
    func resolvedDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .system: return systemIsDark
        case .light:  return false
        case .dark:   return true
        }
    }

    /// Resolve the load-time mode from stored state (INV-3). Pure: the inputs are
    /// the two optional stored values, no live `UserDefaults` read inside.
    /// New key wins; else migrate the legacy bool (`true` → `.dark`, `false` →
    /// `.light`); else default `.system` (fresh install follows the OS).
    static func migrate(stored: AppearanceMode?, legacyDark: Bool?) -> AppearanceMode {
        if let stored { return stored }
        if let legacyDark { return legacyDark ? .dark : .light }
        return .system
    }

    /// The pure `⌘⇧D` explicit-flip decision (INV-6): flip Light↔Dark based on the
    /// current effective appearance. Structurally can only return `.light`/`.dark`,
    /// never `.system`.
    static func toggledExplicit(currentDark: Bool) -> AppearanceMode {
        currentDark ? .light : .dark
    }
}
