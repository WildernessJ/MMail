# System / Light / Dark Appearance Auto-Follow Specification

## Purpose

MMail's appearance is a single persisted boolean today: `@Published var dark: Bool` (`MMail/State/AppModel.swift:124`), loaded from the legacy key `mmail.dark` (`kDark`, `MMail/State/AppModel.swift:95`; read at `:243`, persisted at `:530`) and read by the WindowGroup root for `.preferredColorScheme` and `.environment(\.palette)` (`MMail/MMailApp.swift:12-13`), by the email-body dark engine via `ReaderHTML.shouldApplyDark(dark: model.dark, …)` (`MMail/Views/ReaderView.swift:341,355`, `showOriginalStrip()` gate at `:394`), by the Settings "Dark mode" toggle (`MMail/Views/SettingsView.swift:35-36`), by the `⌘⇧D` command-palette entry (`MMail/State/AppModel.swift:1558`) and the `⌘⇧D` keydown (`:3323`). A user cannot select "follow the OS": there is no way to have the app flip with the macOS appearance (e.g. at sunset under macOS auto-appearance) without manually toggling.

This feature SHALL replace the binary on/off appearance with a THREE-way persisted setting — **System / Light / Dark** — where **System** tracks the macOS system appearance live and re-renders the whole app (chrome, palette, AND email bodies) without relaunch when the OS appearance changes. It SHALL do so by keeping `@Published var dark: Bool` as a DERIVED value so every existing reader of `model.dark` keeps working UNCHANGED. Because the app forces `.preferredColorScheme` to the resolved scheme (see "System mode follows the macOS appearance live"), the live OS preference SHALL be read from the **system-wide signal independent of the app's own override** — `UserDefaults.standard.string(forKey: "AppleInterfaceStyle")` (the global domain), observed via `DistributedNotificationCenter` — NOT from `NSApp.effectiveAppearance`, which would reflect the forced scheme rather than the OS setting. The change is a UserDefaults preference only — no `MailCache`, `Email`, or schema change.

## Invariants

- **INV-1 (derived `dark` is the single render source of truth):** `@Published var dark: Bool` (`MMail/State/AppModel.swift:124`) SHALL be retained and become a DERIVED value, recomputed from `appearanceMode` plus the current system appearance whenever either changes. Every existing PURE READER of `model.dark` — `MMailApp` `.preferredColorScheme`/`.environment(\.palette)` (`MMail/MMailApp.swift:12-13`), the dark-engine `applyDark` inputs (`MMail/Views/ReaderView.swift:341,355` and the plain-text + `showOriginalStrip()` gates at `:355,:394`), the command-palette label (`MMail/State/AppModel.swift:1558`), and the keydown path (`:3323`) — SHALL continue reading `model.dark` with NO source change. The Settings appearance control (the `set: { model.setDark($0) }` binding at `MMail/Views/SettingsView.swift:35-36`, which is a WRITER, not a reader) and the new command-palette appearance commands are the INTENTIONALLY-CHANGED sites: they are rewritten to drive `appearanceMode`/`setAppearanceMode`, and the Settings control is REPLACED by the three-way control (see the Settings requirement). No OTHER reader of `dark` is rewritten to read `appearanceMode` directly.
- **INV-2 (pure resolution seam):** A pure function `AppearanceMode.resolvedDark(systemIsDark: Bool) -> Bool` SHALL define the mapping: `.system` → `systemIsDark`; `.light` → `false`; `.dark` → `true`. It SHALL take no global/OS state as a hidden input (the live appearance is passed in), so it is deterministic and unit-testable.
- **INV-3 (additive persistence + pure migration + no legacy write):** A new String-backed `enum AppearanceMode: String { case system, light, dark }` SHALL persist under a NEW additive UserDefaults key `mmail.appearanceMode`, written ONLY by `setAppearanceMode(_:)`. The legacy `kDark = "mmail.dark"` key (`MMail/State/AppModel.swift:95`) SHALL be READ ONCE on load for migration and SHALL NEVER be written again post-feature: `persistTweaks()` (`MMail/State/AppModel.swift:528`, called by `setSidebar`/`setReadingPane`/`setRailSize`/`cycleRailSize`/`setSidebarLabels`) currently writes `d.set(dark, forKey: kDark)` (`:530`); that line SHALL be REMOVED so unrelated layout tweaks no longer re-write the legacy bool on every change. This removes the migration ambiguity — no live legacy write can shadow `mmail.appearanceMode` once it is the source of truth (e.g. a stale `mmail.dark` can never be silently refreshed to contradict the new key). On load a pure function SHALL resolve the mode: if `mmail.appearanceMode` is present, use it; else if the legacy `mmail.dark` bool is present, migrate (`true` → `.dark`, `false` → `.light`); else default `.system`. This `migrate(stored:legacyDark:)` function SHALL be pure (its inputs are the two optional stored values) and unit-testable, taking no live `UserDefaults` read inside itself.
- **INV-4 (live OS observation via the system-wide signal, mode-gated):** When `appearanceMode == .system`, the model SHALL determine the live OS appearance by reading `UserDefaults.standard.string(forKey: "AppleInterfaceStyle")` from the global domain (`== "Dark"` → `systemIsDark == true`; `nil` → light) and SHALL observe `DistributedNotificationCenter.default()` for `"AppleInterfaceThemeChangedNotification"`, recomputing `dark` on every OS appearance change, on the main actor. The observer SHALL NOT use `NSApp.effectiveAppearance` as the System-mode signal: because the app forces `.preferredColorScheme` to the resolved `dark` value (not `nil`, see the System-mode requirement and SC-9), `NSApp.effectiveAppearance` reflects that FORCED scheme, so an OS flip would never be detectable through it. `AppleInterfaceStyle` plus the distributed notification is the required signal precisely because it reflects the system setting REGARDLESS of the app's own override. When `appearanceMode != .system`, `dark` is FIXED by the mode (`.light` → `false`, `.dark` → `true`, INV-2) and OS appearance changes SHALL NOT alter `dark`. (`AppleInterfaceStyle` and `AppleInterfaceThemeChangedNotification` have zero existing uses in the codebase; the plan SHALL spike-confirm the notification actually fires before relying on it, but the signal CHOICE is fixed here, not deferred to the plan.) The observer's lifecycle obligations are fixed by INV-5.
- **INV-5 (observer lifecycle + race resolution):** The appearance observer SHALL be installed exactly ONCE for the lifetime of the `AppModel` (no duplicate observers across mode switches) and SHALL NOT create a retain cycle (no strong `self` capture that outlives the model). Both the `setAppearanceMode(_:)` mode write AND the observer's recompute of `dark` SHALL be delivered on the MAIN ACTOR, so the two cannot interleave (no read-modify-write race on `appearanceMode`/`dark`). The observer's recompute SHALL be GATED on `appearanceMode == .system` and SHALL read the live `AppleInterfaceStyle` at recompute time (INV-4), so a mode switch that races a notification resolves deterministically: if the mode is no longer `.system` when the recompute runs, it no-ops. Toggling out of and back into `.system` SHALL NOT leak or stack observers; it gates the recompute on the current mode rather than add/remove the observer each time.
- **INV-6 (⌘⇧D lands on an explicit mode):** Pressing `⌘⇧D` (keydown `MMail/State/AppModel.swift:3323`; palette command `:1558`) SHALL set an EXPLICIT mode based on the current effective appearance via a PURE decision seam `AppearanceMode.toggledExplicit(currentDark: Bool) -> AppearanceMode`: `currentDark == true` → `.light`; `currentDark == false` → `.dark`; it NEVER returns `.system`. It SHALL ALWAYS leave `appearanceMode == .system` and land on `.light` or `.dark` — it does NOT cycle through System. This preserves today's binary-flip muscle memory and keeps the toggle decision unit-testable by inspection.
- **INV-7 (System is keyboard-reachable):** Because `⌘⇧D` never selects `.system` (INV-6), the `⌘K` command palette (`buildCommands()`, `MMail/State/AppModel.swift:1536-1568`) SHALL expose a way to select `.system` — at minimum a command that sets `appearanceMode = .system` — so System is reachable without the mouse. Settings (`MMail/Views/SettingsView.swift:34-41`) SHALL ALSO offer all three.
- **INV-8 (no cache/schema change):** This feature SHALL change UserDefaults preferences only. The `MailCache` on-disk schema and the `Email` `Codable` shape SHALL be byte-for-byte unchanged. No new field is added to any persisted mail/cache structure.

## Requirements

### Requirement: A three-way persisted AppearanceMode with derived `dark`

The system SHALL persist a three-way `AppearanceMode` (System / Light / Dark) under `mmail.appearanceMode`, expose it as `@Published var appearanceMode` with a `func setAppearanceMode(_:)` setter that persists and recomputes the derived `dark`, and keep `@Published var dark: Bool` as the recomputed single render source of truth (INV-1, INV-2, INV-3).

#### Scenario: Setting an explicit mode recomputes `dark` and persists

- **GIVEN** the app is running with any current `appearanceMode`
- **WHEN** `setAppearanceMode(.dark)` is called (e.g. from Settings)
- **THEN** `appearanceMode` becomes `.dark`, `mmail.appearanceMode` is written, and `dark` recomputes to `true` via `AppearanceMode.resolvedDark` (INV-2)
- **AND** every reader of `model.dark` re-renders to dark: `MMailApp` colorScheme + palette (`MMail/MMailApp.swift:12-13`) and the email-body dark engine (`MMail/Views/ReaderView.swift:341,355`) — no reader is changed (INV-1)

#### Scenario: Selecting Light recomputes `dark` to false regardless of the OS

- **GIVEN** the macOS system appearance is Dark
- **WHEN** the user selects `.light`
- **THEN** `dark` recomputes to `false` (`resolvedDark(.light)` ignores `systemIsDark`, INV-2)
- **AND** a subsequent OS appearance change does NOT alter `dark` (mode is not `.system`, INV-4)

#### Scenario: `setAppearanceMode` is the recompute owner and `setDark` is reconciled

- **GIVEN** existing call sites invoke `model.setDark(_:)` (`MMail/State/AppModel.swift:1580`) — the Settings toggle path it replaces, the command, and the keydown
- **WHEN** the feature lands
- **THEN** the `⌘⇧D` paths (`:1558`, `:3323`) and the Settings appearance control route through `setAppearanceMode(_:)`, and `setDark` is either removed or kept ONLY as a thin shim mapping `true`/`false` to `setAppearanceMode(.dark)`/`(.light)` so no caller writes `dark` directly out from under the derived recompute
- **AND** the migration function and `resolvedDark` are the only places that compute a mode-or-bool, keeping one source of truth

### Requirement: Migration preserves the existing user's look

On load the system SHALL resolve `appearanceMode` from stored state via the pure `migrate(stored:legacyDark:)` function: new key wins; else legacy `mmail.dark` migrates (`true` → `.dark`, `false` → `.light`); else default `.system` (INV-3).

#### Scenario: Existing dark=true user migrates to explicit Dark

- **GIVEN** a returning user who had `mmail.dark == true` and has never written `mmail.appearanceMode`
- **WHEN** the app loads and reads `appearanceMode`
- **THEN** `migrate(stored: nil, legacyDark: true)` returns `.dark`, so the app launches dark exactly as before
- **AND** the user is NOT silently switched to System (their explicit dark choice is honored)

#### Scenario: Existing dark=false user migrates to explicit Light

- **GIVEN** a returning user who had `mmail.dark == false` and no `mmail.appearanceMode`
- **WHEN** the app loads
- **THEN** `migrate(stored: nil, legacyDark: false)` returns `.light`, preserving their light look

#### Scenario: Fresh install defaults to System

- **GIVEN** a brand-new install with NEITHER `mmail.appearanceMode` NOR `mmail.dark` set
- **WHEN** the app loads
- **THEN** `migrate(stored: nil, legacyDark: nil)` returns `.system`, so a fresh user follows the OS by default

#### Scenario: New key wins over a stale legacy bool

- **GIVEN** a user who has set `mmail.appearanceMode == .system` but whose stale `mmail.dark` is still `true` from before
- **WHEN** the app loads
- **THEN** `migrate(stored: .system, legacyDark: true)` returns `.system` — the new key takes precedence and the stale legacy bool is ignored

#### Scenario: An unrelated layout tweak no longer writes the legacy key

- **GIVEN** the feature has landed and `mmail.appearanceMode` is the persisted source of truth
- **WHEN** the user changes an unrelated layout preference that routes through `persistTweaks()` — e.g. `setSidebar`, `setReadingPane`, `setRailSize`, `cycleRailSize`, or `setSidebarLabels` (`MMail/State/AppModel.swift:1581-1585`)
- **THEN** `persistTweaks()` does NOT write `kDark` (`mmail.dark`) — the `d.set(dark, forKey: kDark)` line at `:530` has been removed, so the legacy bool is never refreshed and can never shadow the new key (INV-3)
- **AND** `mmail.appearanceMode` is written only by `setAppearanceMode(_:)`, leaving migration unambiguous

### Requirement: System mode follows the macOS appearance live

When `appearanceMode == .system`, the app's effective appearance SHALL track the macOS system appearance — read from `UserDefaults.standard.string(forKey: "AppleInterfaceStyle")` and observed via `DistributedNotificationCenter`'s `"AppleInterfaceThemeChangedNotification"` (INV-4) — and recompute `dark` without relaunch when the OS appearance changes (INV-4, INV-5). `MMailApp` SHALL keep driving `.preferredColorScheme`/`.environment(\.palette)` off the derived `dark` (`MMail/MMailApp.swift:12-13`); when in System mode it SHALL pass the RESOLVED `dark` value (not `nil`) so the palette token environment — which has only `.light`/`.dark` cases — always receives a concrete scheme matching the OS, keeping chrome and the email dark engine in agreement. Because that forced scheme makes `NSApp.effectiveAppearance` report the override rather than the OS preference, the live-OS signal MUST be the system-wide `AppleInterfaceStyle` / distributed notification (INV-4), not `effectiveAppearance`.

#### Scenario: OS flips to dark while in System mode

- **GIVEN** `appearanceMode == .system` and the OS appearance is Light (so `dark == false`)
- **WHEN** the macOS appearance flips to Dark (e.g. at sunset under auto-appearance) while the app stays open
- **THEN** the `DistributedNotificationCenter` observer for `"AppleInterfaceThemeChangedNotification"` fires on the main actor, re-reads `AppleInterfaceStyle` (now `"Dark"`), and recomputes `dark` to `true` (INV-4, INV-5)
- **AND** `MMailApp` re-renders to the dark palette and the OPEN reader's email body re-darkens because `ReaderHTML.shouldApplyDark(dark: model.dark, …)` (`MMail/Views/ReaderView.swift:341`) now sees `dark == true` and the WebView toggles the dark transform in place (`HTMLMessageView.toggleDark(_:applyDark:)`, `MMail/Views/HTMLMessageView.swift:318`) with no relaunch

#### Scenario: OS flip is ignored while in an explicit mode

- **GIVEN** `appearanceMode == .light` (or `.dark`)
- **WHEN** the macOS appearance flips
- **THEN** `dark` does NOT change (it stays `false` for `.light`, `true` for `.dark`, INV-4) and nothing re-renders from the OS change
- **AND** the observer either does not recompute or its recompute is gated to no-op while mode != `.system` (INV-5)

#### Scenario: `preferredColorScheme` carries the resolved value in System mode

- **GIVEN** `appearanceMode == .system`
- **WHEN** `MMailApp` evaluates `.preferredColorScheme(...)` / `.environment(\.palette, ...)`
- **THEN** it passes the resolved `model.dark` (`.dark` when `dark`, else `.light`) — NOT `nil` — so the in-app palette environment receives a concrete scheme rather than relying on SwiftUI inheritance, keeping chrome and email-body dark decisions consistent

### Requirement: ⌘⇧D toggles to an explicit Light or Dark

Pressing `⌘⇧D` (keydown `MMail/State/AppModel.swift:3323`; palette entry `:1558`) SHALL set an explicit mode from the current effective appearance and always leave System (INV-6).

#### Scenario: ⌘⇧D from effective-dark sets explicit Light

- **GIVEN** `dark == true` (whether because `appearanceMode == .dark` OR `.system` while the OS is dark)
- **WHEN** the user presses `⌘⇧D`
- **THEN** `appearanceMode` becomes `.light`, `dark` recomputes to `false`, and the app goes light
- **AND** if it was `.system`, it has now LEFT System and become explicit Light (INV-6)

#### Scenario: ⌘⇧D from effective-light sets explicit Dark

- **GIVEN** `dark == false`
- **WHEN** the user presses `⌘⇧D`
- **THEN** `appearanceMode` becomes `.dark`, `dark` recomputes to `true`

#### Scenario: ⌘⇧D from System mode lands on explicit, not the other System

- **GIVEN** `appearanceMode == .system` and the OS is currently Light (`dark == false`)
- **WHEN** the user presses `⌘⇧D`
- **THEN** the result is explicit `.dark` (based on current `dark == false`), NOT `.system` — `⌘⇧D` never produces `.system` (INV-6)
- **AND** the command-palette label for the entry continues to reflect the current effective state (it reads `dark`, `MMail/State/AppModel.swift:1558`)

### Requirement: Settings and the ⌘K palette expose all three modes

Settings SHALL replace the on/off "Dark mode" toggle with a three-way control (System / Light / Dark) bound to `appearanceMode`/`setAppearanceMode`, and the `⌘K` command palette SHALL make `.system` selectable by keyboard (INV-7).

#### Scenario: Settings shows a three-way appearance control

- **GIVEN** the Settings "Appearance" section currently renders a `toggleRow("Dark mode", …)` bound to `model.dark`/`model.setDark` (`MMail/Views/SettingsView.swift:35-36`)
- **WHEN** the feature lands
- **THEN** that row is replaced by a three-way control (e.g. a segmented Picker) bound to `Binding(get: { model.appearanceMode }, set: { model.setAppearanceMode($0) })` offering System / Light / Dark
- **AND** the adjacent rows (Show sidebar, Reading pane, `:37-40`) are untouched

#### Scenario: System is selectable from the ⌘K palette

- **GIVEN** the command palette is built by `buildCommands()` (`MMail/State/AppModel.swift:1536-1568`), today containing a single "Toggle dark mode" entry (`:1558`)
- **WHEN** the user opens `⌘K` and searches appearance
- **THEN** a command exists that sets `appearanceMode = .system` (at minimum a "System appearance" command; the plan MAY also add explicit "Light appearance"/"Dark appearance" commands), so System is reachable without the mouse (INV-7)
- **AND** the existing `⌘⇧D` binary-flip entry is retained or restated per INV-6 (it still flips Light↔Dark and leaves System)

#### Scenario: HelpSheet shortcut text stays accurate

- **GIVEN** the Help sheet lists `Shortcut(label: "Toggle dark mode", keys: ["⌘","⇧","D"])` (`MMail/Views/HelpSheetView.swift:44`)
- **WHEN** the feature lands
- **THEN** the `⌘⇧D` shortcut row remains present and its description remains accurate (it still flips Light↔Dark; wording MAY be refined but the key combo is unchanged)

## Success Criteria

- **SC-1 (unit — resolvedDark):** `AppearanceMode.resolvedDark(systemIsDark:)` returns `systemIsDark` for `.system`, `false` for `.light`, `true` for `.dark` — covered by Swift-Testing unit tests over all three modes × both `systemIsDark` values (INV-2). Verified by unit test.
- **SC-2 (unit — migration new-key-wins):** `migrate(stored:legacyDark:)` returns the stored mode when `mmail.appearanceMode` is present, ignoring the legacy bool — covered including the stale-legacy case (`stored: .system, legacyDark: true` → `.system`, INV-3). Verified by unit test.
- **SC-3 (unit — migration legacy dark=true):** `migrate(stored: nil, legacyDark: true)` returns `.dark` (existing dark user preserved, INV-3). Verified by unit test.
- **SC-4 (unit — migration legacy dark=false):** `migrate(stored: nil, legacyDark: false)` returns `.light`. Verified by unit test.
- **SC-5 (unit — fresh install default):** `migrate(stored: nil, legacyDark: nil)` returns `.system`. Verified by unit test.
- **SC-6 (unit — ⌘⇧D explicit-toggle decision):** The pure decision behind `⌘⇧D` is factored as `AppearanceMode.toggledExplicit(currentDark: Bool) -> AppearanceMode` and unit-tested over both inputs: `toggledExplicit(currentDark: true) == .light`, `toggledExplicit(currentDark: false) == .dark`, and it NEVER returns `.system` (INV-6). Verified by unit test.
- **SC-7 (live — Settings picker):** Selecting System / Light / Dark in the Settings three-way control switches the app appearance accordingly; selecting Light while the OS is Dark goes light and stays light through an OS flip (INV-4). Verified live by the user.
- **SC-8 (live — ⌘⇧D flip):** `⌘⇧D` flips Light↔Dark each press from any starting state, including from System mode (lands on explicit, leaving System, INV-6). Verified live by the user.
- **SC-9 (live — System follows OS via the system-wide signal, including in-session email-body re-darken):** In System mode, the live-OS signal is `AppleInterfaceStyle` read on the `"AppleInterfaceThemeChangedNotification"` distributed notification (NOT `NSApp.effectiveAppearance`, which reflects the forced scheme, INV-4). Verified live by the user as TWO distinct cases:
  - **(a) in-session OS flip with an HTML email OPEN** — with `appearanceMode == .system` and an HTML email body currently displayed, flipping the macOS appearance re-darkens/re-lightens THAT open body IN PLACE via `model.dark` change → `HTMLMessageView.updateNSView` (`MMail/Views/HTMLMessageView.swift:77`) → `toggleDark(_:applyDark:)` (`:318`), driven by `ReaderHTML.shouldApplyDark(dark: model.dark, …)` (`MMail/Views/ReaderView.swift:341`). This exercises the documented in-session coordinator-staleness path (`MMail/Views/HTMLMessageView.swift:198` threads `applyDark` from the live struct, not the frozen first-render snapshot), so it is verified as its own step — distinct from the relaunch path of SC-10.
  - **(b) explicit mode** — with `appearanceMode == .light` (or `.dark`), the same OS flip changes nothing (INV-4).
  (WebView dark-transform computed-style invariants are additionally headlessly checkable via an offscreen WKWebView.)
- **SC-10 (live — migration preserves look):** A user who launched the prior build with dark on launches the new build still dark (migrated to explicit `.dark`), and a light user launches light — no surprise switch to System (INV-3). Verified live by the user (relaunch into the pinned Dock app with existing UserDefaults).
- **SC-11 (no schema change):** The `MailCache` on-disk schema and `Email` `Codable` shape are byte-for-byte unchanged; only the additive `mmail.appearanceMode` UserDefaults key is introduced (INV-8). Verified by diff/inspection.

## Non-Goals

- **No per-message appearance.** A single app-wide appearance governs everything; there is no per-email or per-thread light/dark override.
- **No scheduled / sunset / custom-time logic beyond the OS.** "System" delegates entirely to the macOS system appearance (the global `AppleInterfaceStyle` signal, INV-4). MMail SHALL NOT implement its own sunset/sunrise schedule, location-based timing, or custom auto-switch hours — if the user wants time-based switching, they enable macOS auto-appearance and choose System.
- **No new cache or `Email`/schema change.** This is a UserDefaults preference only (INV-8); no persistence-schema work is in scope.
- **No new palette tokens or theme variants.** The existing two-scheme palette (`.light`/`.dark`) is reused as-is; this feature only changes WHICH scheme is selected and WHEN, not the palette content.
- **No multi-window appearance divergence.** The single shared `AppModel`'s derived `dark` governs all windows uniformly; per-window appearance is out of scope.
