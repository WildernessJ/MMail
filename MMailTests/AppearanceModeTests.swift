import Foundation
import Testing
@testable import MMail

/// Unit tests for the pure, OS-free `AppearanceMode` seam: the deterministic
/// decision functions behind the three-way System / Light / Dark setting. No
/// `UserDefaults`/OS read happens inside any seam function — the live appearance
/// and the two stored values are passed IN, so the suite is fully deterministic.
/// Covers SC-1..SC-6 (INV-2, INV-3, INV-6).

/// `resolvedDark(systemIsDark:)` — the three-mode → bool mapping (SC-1, INV-2).
@Suite struct ResolvedDark {
    /// `.system` returns the passed `systemIsDark` for both inputs.
    @Test func systemFollowsSystemIsDark() {
        #expect(AppearanceMode.system.resolvedDark(systemIsDark: true) == true)
        #expect(AppearanceMode.system.resolvedDark(systemIsDark: false) == false)
    }

    /// `.light` returns `false` regardless of the OS appearance.
    @Test func lightIsAlwaysFalse() {
        #expect(AppearanceMode.light.resolvedDark(systemIsDark: true) == false)
        #expect(AppearanceMode.light.resolvedDark(systemIsDark: false) == false)
    }

    /// `.dark` returns `true` regardless of the OS appearance.
    @Test func darkIsAlwaysTrue() {
        #expect(AppearanceMode.dark.resolvedDark(systemIsDark: true) == true)
        #expect(AppearanceMode.dark.resolvedDark(systemIsDark: false) == true)
    }
}

/// `migrate(stored:legacyDark:)` — new-key-wins → legacy-bool → `.system`
/// (SC-2..SC-5, INV-3).
@Suite struct Migration {
    /// New key wins: a present stored mode is returned as-is.
    @Test func newKeyWins() {
        #expect(AppearanceMode.migrate(stored: .light, legacyDark: nil) == .light)
        #expect(AppearanceMode.migrate(stored: .dark, legacyDark: nil) == .dark)
    }

    /// New key wins even when a stale legacy bool disagrees: the legacy bool is
    /// ignored when the new key is present (SC-2).
    @Test func newKeyWinsOverStaleLegacy() {
        #expect(AppearanceMode.migrate(stored: .system, legacyDark: true) == .system)
    }

    /// Legacy migration: `mmail.dark == true` migrates to explicit `.dark` (SC-3).
    @Test func legacyDarkTrueMigratesToDark() {
        #expect(AppearanceMode.migrate(stored: nil, legacyDark: true) == .dark)
    }

    /// Legacy migration: `mmail.dark == false` migrates to explicit `.light` (SC-4).
    @Test func legacyDarkFalseMigratesToLight() {
        #expect(AppearanceMode.migrate(stored: nil, legacyDark: false) == .light)
    }

    /// Fresh install (neither key set) defaults to `.system` (SC-5).
    @Test func freshInstallDefaultsToSystem() {
        #expect(AppearanceMode.migrate(stored: nil, legacyDark: nil) == .system)
    }
}

/// `toggledExplicit(currentDark:)` — the `⌘⇧D` explicit-flip decision; never
/// returns `.system` (SC-6, INV-6).
@Suite struct ToggledExplicit {
    /// From effective-dark → explicit Light.
    @Test func fromDarkGoesLight() {
        #expect(AppearanceMode.toggledExplicit(currentDark: true) == .light)
    }

    /// From effective-light → explicit Dark.
    @Test func fromLightGoesDark() {
        #expect(AppearanceMode.toggledExplicit(currentDark: false) == .dark)
    }

    /// It NEVER lands on `.system` for either input.
    @Test func neverReturnsSystem() {
        #expect(AppearanceMode.toggledExplicit(currentDark: true) != .system)
        #expect(AppearanceMode.toggledExplicit(currentDark: false) != .system)
    }
}
