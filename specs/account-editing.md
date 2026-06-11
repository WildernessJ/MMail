# account-editing Specification

## Purpose

MMail SHALL let a user edit an existing IMAP/SMTP account's **identity** in place — rename its display name, recolor its avatar tile, or replace the letters tile with a chosen image — from the Settings → Accounts section, without removing and re-adding the account (which today forces re-entering credentials). All customization SHALL persist across relaunches and SHALL flow through the single derived `Account` model so every place the avatar appears (the account rail, the sidebar header, and the two compose surfaces) stays consistent. The feature exists because identity edits are currently impossible: the display name is captured once at setup (`ManualAccountSetupView.swift:111`) and the avatar (initials + color) is fully auto-derived (`AppModel.uiAccount(for:)`), so the only way to change either is delete + re-add.

## Invariants

- The new persistence fields on `MailAccountConfig` (`avatarColorHex`, `hasCustomAvatar`) SHALL be **additively Codable** (`Optional`, default `nil`). A config persisted before this feature SHALL decode unchanged with both fields `nil`, behaving exactly as today. There SHALL be NO migration step and NO cache wipe.
- Account customization SHALL live in `MailAccountConfig` (the persisted source of truth) and reach the UI only through the derived `Account` rebuilt by `uiAccount(for:)`. The rail, sidebar header, and compose avatars SHALL NEVER disagree, because all four read the same rebuilt `Account`.
- Avatar **initials** SHALL always derive from the effective display name (first grapheme of `displayName`, or of `email` when `displayName` is empty), uppercased. There SHALL be NO separate user-editable initials field.
- When `hasCustomAvatar == true`, the chosen image SHALL fully replace the letters-and-color tile at **every** avatar site. When `false`/`nil`, the letters-and-color tile SHALL render and the stored `avatarColorHex` (if any) SHALL set its color.
- This feature SHALL NOT touch mail credentials, the Keychain, network egress, or the security boundary. Avatar image files are non-sensitive and stored unencrypted under Application Support (the same trust tier as `MailCache`).
- Editing one account SHALL NOT mutate any other account's config, avatar file, or derived `Account`.
- Image processing (decode + center-crop + downscale + PNG-encode) and file writes SHALL run **synchronously on the main thread** as a one-shot user action on an already-small image. `NSImage` SHALL NOT be sent across a `Task`/actor boundary. (`AppModel` is not `@MainActor` but mutates state on the main thread by convention — `AppModel.swift:2767`; the project compiles in **Swift 5 language mode** — `project.yml` `SWIFT_VERSION: "5.0"` — so `NSImage`'s non-`Sendable`ness is at most a warning, but the synchronous-main-thread rule keeps it a non-issue.)
- The derived `Account` SHALL remain identified by `id` only: it stays non-`Codable`, non-`Equatable`, and non-`Hashable`. Adding `var avatarImage: NSImage?` introduces no conformance (there is none today to break) and is never compared by value — SwiftUI diffs the `accounts` array by `id`.
- Loading an avatar for rendering SHALL produce a **fresh `NSImage` instance from disk on each rebuild** (e.g. decode from freshly-read `Data`), so replacing an image at the same `<id>.png` path always renders the new image — there SHALL be no name/URL image cache that could surface a stale avatar.

## Requirements

### Requirement: Persisted customization fields

`MailAccountConfig` SHALL gain two stored properties: `avatarColorHex: String?` (a hex string like `"E5484D"`, or `nil` = derive from the email hash as today) and `hasCustomAvatar: Bool?` (`true` = render the stored image; `nil`/`false` = render the letters tile). Both SHALL be `Codable` and `Optional` so existing persisted accounts decode with both `nil`.

#### Scenario: Pre-feature config decodes unchanged

- **GIVEN** a `MailAccountConfig` JSON persisted before this feature (no `avatarColorHex`, no `hasCustomAvatar` keys)
- **WHEN** it is decoded after this feature ships
- **THEN** decoding succeeds with `avatarColorHex == nil` and `hasCustomAvatar == nil`
- **AND** its derived `Account` has the same initials and email-hash-derived color it had before

#### Scenario: Customized config round-trips

- **GIVEN** a config with `avatarColorHex == "1FB36B"` and `hasCustomAvatar == true`
- **WHEN** it is JSON-encoded and decoded
- **THEN** both fields survive the round-trip with the same values

### Requirement: Pure avatar resolution seam

A pure, SwiftUI-free function `AvatarSpec.resolve(displayName:email:customColorHex:hasImage:)` SHALL compute, from a config's relevant fields, the avatar's `initials`, its `gradientHex` (the two gradient stops), and `usesImage`. It SHALL be unit-testable without instantiating a view or touching disk, and SHALL be the single place that decides avatar color and initials. The rules SHALL be:

- `initials` = first **grapheme cluster** (Swift `Character`, i.e. `String.prefix(1)` — which is grapheme-correct and must NOT be downgraded to `unicodeScalars.first`, which would split emoji) of `displayName` if non-empty after trimming, else of `email`, uppercased. This matches today's `uiAccount` exactly.
- `gradientHex` = `[customColorHex, customColorHex]` (a solid fill of the chosen color) when `customColorHex` is non-`nil`; otherwise `[Sender.stableColorHex(for: email), "1E2DB0"]` (today's derived gradient).
- `usesImage` = the passed `hasImage` flag.

`AppModel.uiAccount(for:)` (which SHALL remain a `static func`) SHALL be refactored to consume this seam (value-preserving for an un-customized config) and, when `usesImage` is true, additionally load the stored image into the returned `Account` via the static `AvatarStore.default.load(for: cfg.id)` (mirroring `ProxySecretStore.default`). `AvatarSpec.resolve` itself stays pure and touches no disk.

#### Scenario: Un-customized config preserves today's look

- **WHEN** `AvatarSpec.resolve(displayName: "Jane Doe", email: "jane@x.org", customColorHex: nil, hasImage: false)` is called
- **THEN** `initials == "J"`
- **AND** `gradientHex == [Sender.stableColorHex(for: "jane@x.org"), "1E2DB0"]`
- **AND** `usesImage == false`

#### Scenario: Custom color yields a solid fill

- **WHEN** `AvatarSpec.resolve(displayName: "Jane Doe", email: "jane@x.org", customColorHex: "E5484D", hasImage: false)` is called
- **THEN** `gradientHex == ["E5484D", "E5484D"]`
- **AND** `initials == "J"`

#### Scenario: Edge case: empty display name falls back to email

- **WHEN** `AvatarSpec.resolve(displayName: "   ", email: "jane@x.org", customColorHex: nil, hasImage: false)` is called
- **THEN** `initials == "J"` (derived from the email, not a blank tile)

#### Scenario: Edge case: image flag overrides color for rendering

- **WHEN** `AvatarSpec.resolve(displayName: "Jane Doe", email: "jane@x.org", customColorHex: "E5484D", hasImage: true)` is called
- **THEN** `usesImage == true`
- **AND** `gradientHex == ["E5484D", "E5484D"]` (color is still resolved and persisted, used if the image is later removed)

### Requirement: Avatar image storage

A store (mirroring `ProxySecretStore`'s Application-Support pattern, with a static `AvatarStore.default`) SHALL persist a per-account avatar image as a PNG at `~/Library/Application Support/MMail/avatars/<accountId>.png`. It SHALL expose `save(_ image:for:)`, `load(for:) -> NSImage?`, and `remove(for:)`. On save it SHALL center-crop the source to a square and downscale it to at most a fixed target edge (256px) so stored files stay small. `load(for:)` SHALL read the file's bytes fresh and build a **new** `NSImage` from that `Data` on every call (no name-keyed `NSImage(named:)` cache), so a replaced file always loads its new contents. Save and remove failures SHALL be handled without crashing (return a discardable success flag / no-throw).

A pure helper `AvatarImage.squareCropRect(sourceWidth:sourceHeight:)` SHALL compute the centered square crop rectangle, and SHALL be unit-testable. The rule SHALL be: the square's edge equals the smaller of width/height, centered on the longer axis (the target SHALL NOT upscale a source smaller than 256px — the stored edge is `min(smallerSide, 256)`). **Coordinate convention:** the returned rect is defined in **top-left origin** image coordinates (the convention of `CGImage.cropping(to:)`, which is the REQUIRED crop mechanism — the implementation SHALL crop via `CGImage.cropping(to:)`, NOT a flipped `NSImage.draw(in:from:)`). The centered-crop offset `(longer − shorter) / 2` is symmetric, so for THIS feature's always-centered crop the numeric values happen to coincide with bottom-left origin — but the implementer SHALL NOT treat origin as "don't care": the rect is top-left and is consumed by `CGImage.cropping(to:)`.

#### Scenario: Square crop of a wide image

- **WHEN** `AvatarImage.squareCropRect(sourceWidth: 800, sourceHeight: 400)` is called
- **THEN** the rect is `x: 200, y: 0, width: 400, height: 400` (centered horizontally)

#### Scenario: Square crop of a tall image

- **WHEN** `AvatarImage.squareCropRect(sourceWidth: 300, sourceHeight: 900)` is called
- **THEN** the rect is `x: 0, y: 300, width: 300, height: 300` (centered vertically)

#### Scenario: Edge case: already square

- **WHEN** `AvatarImage.squareCropRect(sourceWidth: 500, sourceHeight: 500)` is called
- **THEN** the rect is `x: 0, y: 0, width: 500, height: 500` (full image)

#### Scenario: Save then load round-trips an image

- **GIVEN** an in-memory `NSImage`
- **WHEN** it is saved for account id `"acct-1"` and then loaded
- **THEN** `load(for: "acct-1")` returns a non-nil `NSImage`
- **AND** a PNG file exists at `…/MMail/avatars/acct-1.png`

### Requirement: Account mutation API

`AppModel` SHALL expose functions to edit an account and keep `realConfigs`, the derived `accounts`, and persistence in sync. Each SHALL update the matching `MailAccountConfig` in `realConfigs`, rebuild that account's `Account` via `uiAccount(for:)`, and call `persistRealAccounts()`. A private rebuild helper SHALL replace exactly the one `accounts` entry whose id matches.

- `renameAccount(_ id:to:)` — set `displayName` to the trimmed new value; rebuild; persist.
- `setAccountColor(_ id:hex:)` — set `avatarColorHex` to the chosen hex; rebuild; persist.
- `setAccountImage(_ id:_ image:)` — save the image via the store, set `hasCustomAvatar = true`; rebuild (loading the image); persist.
- `removeAccountImage(_ id:)` — remove the stored file, set `hasCustomAvatar = false`; rebuild; persist.

#### Scenario: Rename updates the derived account and persists

- **GIVEN** an account with `displayName == "Personal"`
- **WHEN** `renameAccount(id, to: "Work")` is called
- **THEN** `config(for: id)?.displayName == "Work"`
- **AND** the matching entry in `accounts` has `name == "Work"` and `initials == "W"`
- **AND** the persisted UserDefaults blob reflects `"Work"`

#### Scenario: Color change recolors the derived account

- **GIVEN** an account with `avatarColorHex == nil`
- **WHEN** `setAccountColor(id, hex: "7A5AE0")` is called
- **THEN** `config(for: id)?.avatarColorHex == "7A5AE0"`
- **AND** the matching `accounts` entry's `gradientColors` are a solid `7A5AE0`

#### Scenario: Set then remove image toggles hasCustomAvatar and the file

- **GIVEN** an account with `hasCustomAvatar == nil`
- **WHEN** `setAccountImage(id, someImage)` is called
- **THEN** `config(for: id)?.hasCustomAvatar == true` and the avatar PNG exists
- **WHEN** `removeAccountImage(id)` is then called
- **THEN** `config(for: id)?.hasCustomAvatar == false` and the avatar PNG no longer exists
- **AND** the derived `Account` reverts to the letters-and-color tile

#### Scenario: Editing one account leaves others untouched

- **GIVEN** two accounts A and B
- **WHEN** `renameAccount(A.id, to: "Renamed")` is called
- **THEN** B's config, derived `Account`, and avatar file are unchanged

### Requirement: Image-capable avatar tile rendered at every site

The avatar tile component SHALL render the stored image (clipped to its rounded square) when one is present, and otherwise render the gradient-and-initials tile as today. All four account-avatar render sites SHALL use it and pass the derived `Account`'s image and color: the account rail (`AccountRailView.swift:28`), the sidebar header (`SidebarView.swift:135`), and the two compose surfaces (`ComposeView.swift:243` and `:261`). Non-account tiles (the "you" reader avatar, the unified "All" tile, sender avatars) SHALL be unaffected. Note `SidebarView.swift:135-136` is a single `GradientTile` call whose colors/text are chosen by an `isAll` ternary: ONLY the per-account (non-`isAll`) branch SHALL gain the image; the `isAll` "All inboxes" branch (hardcoded `"M"` + fixed colors) SHALL stay unchanged.

#### Scenario: Image renders at all account sites

- **GIVEN** an account with `hasCustomAvatar == true`
- **WHEN** the rail, sidebar header, and compose account picker are shown
- **THEN** each shows the account's image clipped to its rounded tile (at that site's size), not the initials

#### Scenario: Edge case: replacing an image shows the new one (no stale cache)

- **GIVEN** an account whose avatar was set to image X, then replaced with a different image Y at the same `<id>.png` path
- **WHEN** the account is rebuilt and its tiles are shown
- **THEN** the tiles render image Y (a fresh `NSImage` loaded from the rewritten file), never the stale image X

#### Scenario: Letters tile honors the custom color

- **GIVEN** an account with `avatarColorHex == "F4A52A"` and `hasCustomAvatar` false
- **WHEN** the rail tile is shown
- **THEN** it shows the initials on a solid `F4A52A` tile

#### Scenario: Unified "All" and sender avatars unchanged

- **GIVEN** the account customization above
- **WHEN** the unified "All" tile and a sender avatar are shown
- **THEN** their appearance is unchanged by this feature

### Requirement: Settings editing UI

The Settings → Accounts section SHALL present, per account, an editing row (mirroring the existing `LabelEditRow` pattern) that contains: an avatar preview tile, an inline-editable display-name text field (committing on submit via `renameAccount`), a color-swatch popover offering the existing 10-color `AppModel.labelPalette` (calling `setAccountColor`), and image controls — **Choose image…** (a native macOS file picker filtered to images; on pick, calls `setAccountImage`) and **Use letters** (visible only when an image is set; calls `removeAccountImage`). The existing **Resync** and **Remove** buttons SHALL be retained. The color swatches SHALL be shown when no image is set (color is moot while an image renders).

#### Scenario: Rename from the Settings row

- **GIVEN** the Settings → Accounts row for an account named "Personal"
- **WHEN** the user edits the name field to "Work" and commits
- **THEN** `renameAccount` runs and the rail/sidebar/compose tiles show "W"

#### Scenario: Pick a color from the swatch popover

- **GIVEN** an account with no custom image
- **WHEN** the user opens the color popover and taps the green swatch
- **THEN** `setAccountColor` runs with that hex and the avatar recolors everywhere

#### Scenario: Choose then revert an image

- **GIVEN** an account with no custom image
- **WHEN** the user clicks Choose image… and selects a PNG
- **THEN** the image is stored and shown at every avatar site, and a **Use letters** control appears
- **WHEN** the user clicks Use letters
- **THEN** the image is removed and the letters-and-color tile returns

### Requirement: Account removal cleans up the avatar file

`removeRealAccount(_:)` SHALL delete the account's stored avatar file (if any) so removing an account leaves no orphaned avatar PNG.

#### Scenario: Removing an account deletes its avatar

- **GIVEN** an account with `hasCustomAvatar == true` and a stored avatar PNG
- **WHEN** `removeRealAccount(id)` is called
- **THEN** the avatar PNG at `…/MMail/avatars/<id>.png` no longer exists

## Success Criteria

- **SC-001**: A user can rename an account in Settings → Accounts and the new name + initials appear on the rail, sidebar header, and both compose surfaces, surviving an app relaunch (live-verified).
- **SC-002**: A user can pick an avatar color from the swatch palette and the tile recolors (solid fill) at every avatar site, surviving relaunch.
- **SC-003**: A user can choose an image via the native file picker; it is center-cropped + downscaled, stored under `…/MMail/avatars/`, rendered at every avatar site, and survives relaunch.
- **SC-004**: A user can revert from an image back to the letters-and-color tile (**Use letters**), and the stored PNG is deleted.
- **SC-005**: An account configured before this feature (no new fields) loads with identical appearance to before — no cache wipe, no decode error (additive-Codable verified).
- **SC-006**: Removing an account deletes its avatar file (no orphan left behind).
- **SC-007**: The pure-seam scenarios pass under the Swift test target: `AvatarSpec.resolve` (color/initials/empty-name/image-flag) and `AvatarImage.squareCropRect` (wide/tall/square), plus the additive-Codable round-trip. These are **hand-authored XCTest** added to `MMailTests/` (this repo's `testing.method` is `e2e-first`; the harness property-tests skill emits Python/hypothesis and is explicitly rejected here — do NOT route these through it).
- **SC-008**: The type-check, manual-exploration, and review gates are green.

## Non-Goals

- No user-editable **initials** override — initials always follow the display name (explicitly dropped during brainstorming).
- No per-account two-tone gradient editor — a custom color renders as a solid fill; the only color choice is the 10-swatch palette (no full color wheel).
- No Photos-library picker, drag-and-drop, paste, or manual crop/zoom UI — image selection is a single native file-picker pick with automatic center-crop.
- No avatar customization for the unified "All" tile, the "you" reader avatar, or sender avatars — accounts only.
- No editing of mail server settings (host/port/security/username) or credentials in this feature — identity (name + avatar) only.
- No cross-device sync of avatars or customization — it is local to this machine, like `MailCache`.

## ADDED Requirements

### Requirement: Unified-inbox identity customization

The unified "All" inbox (the `currentAccount == "all"` pseudo-entry, which has NO `MailAccountConfig`) SHALL be renamable and SHALL support a custom avatar color and image, mirroring account customization. Because "All" has no config, its customization SHALL persist in standalone `UserDefaults` keys (e.g. `allInboxName`, `allInboxColorHex`, `allInboxHasImage`) and its image SHALL reuse `AvatarStore` under the reserved id `"all"` (`avatars/all.png`); accounts SHALL be unaffected (additive). The customization SHALL render consistently at BOTH sites where "All" appears — the account rail (`AccountRailView` `allTile`, `AccountRailView.swift:53`) and the sidebar footer (`SidebarView` footer, `SidebarView.swift:135-141`) — replacing today's divergent hardcoded tiles (rail "All"/magenta vs sidebar "M"/blue) with one shared rendering. When no image is set, the tile SHALL show SHORT text: the first up-to-3 characters of the trimmed custom name, or `"All"` when the name is empty/unset. The full custom name SHALL be the sidebar footer label and the rail tooltip; when unset the label SHALL remain `"All inboxes"`. When an image is set it SHALL replace the letters tile at both sites. Default (uncustomized) color SHALL unify on the rail's existing magenta (`p.magenta`) at both sites.

A pure, SwiftUI-free seam `AllInboxSpec.resolve(name:hasImage:)` SHALL compute the tile's short `tileText` (≤3 graphemes, default `"All"`), the `label` (default `"All inboxes"`), and `usesImage`, and SHALL be unit-testable. Color resolution stays in the view (custom hex → solid fill; nil → `p.magenta`).

#### Scenario: Rename the unified inbox

- **GIVEN** the unified inbox has no custom name
- **WHEN** the user sets its name to "Everything"
- **THEN** the rail tile shows `"Eve"`, the sidebar footer label and the rail tooltip show `"Everything"`
- **AND** this persists across relaunch

#### Scenario: Edge case: default unnamed unified inbox

- **GIVEN** no custom name is set
- **WHEN** the tiles render
- **THEN** both the rail and sidebar tiles show `"All"` and the sidebar label shows `"All inboxes"`

#### Scenario: Custom color is a solid fill at both sites

- **WHEN** the user picks color `"1FB36B"` for the unified inbox
- **THEN** both the rail and sidebar tiles render a solid `1FB36B` fill
- **AND** it persists across relaunch

#### Scenario: Custom image then revert

- **WHEN** the user chooses an image for the unified inbox
- **THEN** both tiles show the center-cropped image, a PNG exists at `…/avatars/all.png`, and a "Use letters" control appears
- **WHEN** the user reverts (Use letters)
- **THEN** both tiles return to the letters-and-color rendering and `…/avatars/all.png` is deleted

#### Scenario: Pure short-text seam

- **WHEN** `AllInboxSpec.resolve(name: "Everything", hasImage: false)` is called
- **THEN** `tileText == "Eve"` and `label == "Everything"`
- **AND** `AllInboxSpec.resolve(name: "   ", hasImage: false)` yields `tileText == "All"` and `label == "All inboxes"`

### Requirement: Unified-inbox editing UI

Settings → Accounts SHALL present a "Unified inbox" editing row ABOVE the per-account rows, with the same controls as an account row: avatar preview, inline name field (committing via a `setAllInboxName` mutation), a color-swatch popover over `AppModel.labelPalette` (→ `setAllInboxColor`), and Choose image…/Use letters (→ `setAllInboxImage`/`removeAllInboxImage`). It SHALL NOT offer Resync or Remove (the unified inbox is not a removable account and has no server folder of its own).

#### Scenario: Edit from Settings updates both tiles live

- **GIVEN** Settings → Accounts is open
- **WHEN** the user edits the Unified inbox row's name, color, or image
- **THEN** the matching `setAllInbox…` mutation runs, persists, and the rail tile + sidebar footer update without reopening Settings

## ADDED Success Criteria

- **SC-009**: The unified inbox can be renamed, recolored, and given/cleared an image from Settings, reflected at the rail and sidebar footer, persisting across relaunch (live-verified).
- **SC-010**: `AllInboxSpec.resolve` short-text/label resolution (default "All"/"All inboxes", ≤3-char truncation, whitespace→default) is covered by a hand-authored Swift unit test; the type-check + manual gates are green.

## ADDED Non-Goals

- The unified-inbox tile uses a ≤3-char short text (e.g. "All", "Eve"), NOT the single-initial rule account tiles use — deliberate, to preserve the unified-inbox identity (user-chosen).
- No per-site divergence after this change — rail and sidebar render from the one shared descriptor; the old sidebar "M"/blue default is removed.
