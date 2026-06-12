# resizable-columns Specification

## Purpose

MMail SHALL let the user adjust three parts of the 4-column layout (`RootView.content` — a fixed-width `HStack`: account rail · folder sidebar · mail list · reader; `RootView.swift:44-65`):

- **(A) Account rail** (`AccountRailView` — the far-left vertical column of mailbox avatar tiles: the unified "All" tile plus one per account, `AccountRailView.swift`): three discrete size presets — `small` (today's 56pt icon-only rail), `medium` (bigger tiles, still icon-only), `large` (bigger tiles WITH account names beside each avatar) — selected from an "Account Rail Size" submenu in the system View menu and cycled with `⌘⇧L`.
- **(B) Folder sidebar** (`SidebarView` — the folders/labels column): TWO independent, simpler controls — a two-state **labels toggle** (icons+text ↔ icons-only) backed by a View-menu "Show Folder Labels" item, and a **draggable width** handle between the sidebar and the mail list.
- **(C) Mail list ↔ reader divider** (reading-pane mode only): a draggable handle that rebalances the list and reading-pane widths. **This portion is ALREADY BUILT and is unchanged by this spec** (see the "Built / unchanged" note below); it is described here because it is part of the feature surface.

All four persisted settings SHALL survive launches and SHALL be purely additive — an existing user with no stored preference lands on a `small` rail (today's exact 56/38 icon-only rail), a folder sidebar with labels visible at 232pt, and a 380pt list, which is the exact current layout, with no visible change until they touch a control. The feature exists so the user can surface account names on the rail when they want them, trade folder-label legibility for screen space, and rebalance both the sidebar↔list and list↔reader splits to taste — without the fragility of full split-view drag dividers on every column.

### Built / unchanged vs. new (read this before reviewing)

This spec is a **retarget** of an already-built feature. The build put the 3-way Small/Medium/Large size control on the **folder sidebar** (`SidebarView`); the correct target is the **account rail** (`AccountRailView`). The split:

- **BUILT and KEPT AS-IS:** the mail-list ↔ reader drag divider (`ListDragHandle` in `RootView.swift:163-211`), `listWidth`, `clampListWidth [300,600]`, and their persistence (`mmail.listWidth`). Unchanged by this spec.
- **BUILT, REUSED:** the icon-only "compact" RENDER of `SidebarView` (`SidebarView.swift:13,68,97,135,165`, today gated by `model.sidebarSize.showsLabels == false`). The render markup is reused verbatim as the icons-only state of the new two-state folder-labels toggle; only its DRIVER changes (the gate becomes `!model.sidebarLabelsVisible`, per the Folder labels toggle Requirement and the migration note — no `sidebarSize` reference survives).
- **RETARGETED (the wrong column → the right column):** the pure enum `SidebarSize` (`LayoutSizing.swift:13-44`) becomes `RailSize` and drives `AccountRailView`, not `SidebarView`. The "Sidebar Size" submenu (`MMailApp.swift:40-47`) becomes "Account Rail Size". `⌘⇧L` (`AppModel.swift:3294`) cycles the rail, not the sidebar. The `sidebarSize`-keyed state/persistence/mutators are replaced (see below).
- **NEW:** the folder-sidebar two-state labels toggle (`sidebarLabelsVisible` + "Show Folder Labels" menu item), the draggable sidebar↔list width (`sidebarWidth` + `clampSidebarWidth` + a second drag handle), and the `large`-rail names render.

### Migration from the built version (the old machinery is REMOVED, not coexisting)

Because this retargets a BUILT feature, the old folder-sidebar S/M/L machinery SHALL be REMOVED/renamed in place, NOT left to coexist — leaving both would compile but produce dead code and a second, stale code path. The following are the concrete removals/renames an implementer SHALL make:

- `@Published var sidebarSize: SidebarSize` in `AppModel` (currently ~`AppModel.swift:127`) → REMOVED, replaced by `@Published var railSize: RailSize`, PLUS the two new published values `@Published var sidebarLabelsVisible: Bool` and `@Published var sidebarWidth: CGFloat`.
- `setSidebarSize(_:)` / `cycleSidebarSize()` (currently ~`AppModel.swift:1558-1559`) → REMOVED, replaced by `setRailSize(_:)` / `cycleRailSize()`, PLUS the new mutators `setSidebarLabels(_:)` / `toggleSidebarLabels()` and `setSidebarWidth(_:)`.
- `enum SidebarSize` (`LayoutSizing.swift:13`) → RENAMED to `RailSize` (its semantics shift from sidebar to rail): add a `tileSize: CGFloat` member and rename `showsLabels` → `showsNames`.
- `LayoutDefaultsKey.sidebarSize = "mmail.sidebarSize"` (currently `LayoutSizing.swift:56`) → REMOVED. Three new keys are added: `railSize = "mmail.railSize"`, `sidebarLabels = "mmail.sidebarLabels"`, `sidebarWidth = "mmail.sidebarWidth"`. `listWidth = "mmail.listWidth"` is unchanged.
- `loadSidebarSize` → RENAMED to `loadRailSize`; add `loadSidebarLabels` and `loadSidebarWidth`; `loadListWidth` is unchanged.

After this migration NO symbol named `sidebarSize`, `setSidebarSize`, `cycleSidebarSize`, `SidebarSize`, `mmail.sidebarSize`, or `loadSidebarSize` SHALL remain anywhere in the tree.

## Invariants

- The default state SHALL reproduce today's layout EXACTLY: `railSize == .small` (rail width 56, tile size 38, icon-only — today's `AccountRailView.swift:47,28,54`), `sidebarLabelsVisible == true` (icons+text), `sidebarWidth == 232` (today's value, `SidebarView.swift:56`), and `listWidth == 380` (built). The feature is additive — a user who never opens a menu, drags a handle, or presses `⌘⇧L` sees no change. Missing/invalid persisted values SHALL resolve to these defaults.
- `AppModel.handleKeyDown` (`AppModel.swift:3272`) SHALL remain the sole owner of every keyboard shortcut. The ONLY new key the feature introduces is `⌘⇧L` (cycle rail size); `⌘⇧` owns only S/R/D today (`AppModel.swift:3289-3297` cmd+shift switch). The `⌘⇧L` case SHALL sit in that SAME cmd+shift switch and call `cycleRailSize()`, and SHALL therefore fire with the EXACT same gating as `⌘⇧S`/`⌘⇧R`/`⌘⇧D` — i.e. it runs BEFORE the `isTyping || anyOverlayOpen` guard (that guard, `AppModel.swift:3311`, gates only the bare-single-key block lower in `handleKeyDown`), so like the other three it intentionally fires even with a text field focused or an overlay open. It SHALL NOT add an `isTyping`/overlay check the other three lack. The "Show Folder Labels" toggle is menu-only and SHALL NOT bind any key. The View-menu submenu SHALL NOT attach a `.keyboardShortcut` accelerator to any item — the submenu is click-only and the cycle key lives solely in `handleKeyDown`, so it can never double-fire.
- The "Account Rail Size" submenu AND the "Show Folder Labels" toggle SHALL be dedicated stateful SwiftUI added directly in `MMailApp`'s `CommandGroup(after: .sidebar)` (`MMailApp.swift:36-48`), NOT routed through the pure `MenuModel.build(from:)` projection. `MenuModel` is a flat group projection of `buildCommands()` (see `specs/menu-bar.md`) and deliberately stays flat; the rail-size submenu is nested and carries a live checkmark on the current size, and the labels toggle carries a live checkmark/state — these are view state, not flat commands. Keeping them out of `MenuModel`/`buildCommands()` preserves that pure projection unchanged.
- The folder sidebar's `.frame(width:)` (`SidebarView.swift:56`) SHALL read `model.sidebarWidth` (replacing the built `model.sidebarSize.width`). The folder sidebar is no longer preset-sized; its width is drag-controlled and its density is the two-state labels toggle.
- The account rail's width and tile size SHALL be `railSize.width` / `railSize.tileSize` (replacing the hardcoded `.frame(width: 56)` at `AccountRailView.swift:47` and the literal `size: 38` at `:28,54,77`). The rail is preset-only (S/M/L) and is NEVER drag-resized.
- `listWidth` SHALL apply ONLY in reading-pane mode (when `EmailListView` and `ReaderView` are shown side-by-side, `RootView.swift:55-58`). When the reading pane is off, the mail list fills as it does today and `listWidth` has no effect; the list↔reader handle SHALL NOT be present. (Built/unchanged.)
- The sidebar↔list drag handle SHALL be present ONLY where the folder sidebar and the mail list are shown together: it SHALL be absent when `sidebarVisible == false` and in the `home`/`outbox` branches (`RootView.swift:51-53`).
- The persisted `sidebarWidth` SHALL ALWAYS be within `clampSidebarWidth`'s bounds, and `listWidth` within `clampListWidth`'s bounds — each value is clamped on every mutation AND on load, so a corrupt or out-of-range stored value can never produce an unusable layout.
- Sidebar visibility (`⌘⇧S`, `sidebarVisible`), reading-pane toggle (`⌘⇧R`, `readingPane`), and dark toggle (`⌘⇧D`, `dark`) SHALL remain orthogonal and unchanged: none of them alters `railSize`, `sidebarLabelsVisible`, `sidebarWidth`, or `listWidth`, and toggling any of them does not reset any of the four.
- The pure decision seams — `RailSize` (width / `tileSize` / `showsNames` / `next`), `clampSidebarWidth(_:)`, and `clampListWidth(_:)` — SHALL contain ALL sizing logic and SHALL be unit-testable without instantiating any view or `AppModel`. Thin persistence accessors (`loadRailSize`/`loadSidebarLabels`/`loadSidebarWidth`/`loadListWidth` over an injectable `UserDefaults`, plus canonical `LayoutDefaultsKey` constants) MAY accompany them in `LayoutSizing.swift`; these contain NO sizing logic of their own (they delegate entirely to the seams for clamping/parsing) and are likewise view/`AppModel`-free and unit-testable. `LayoutDefaultsKey` is the built key-constant enum, MODIFIED by this spec (see "Migration from the built version"): its `sidebarSize` constant is REMOVED and three new constants — `railSize`/`sidebarLabels`/`sidebarWidth` — are added, with `listWidth` unchanged. The descriptions below specify that END STATE; the new constants do NOT already exist in the file and SHALL be added. The same `LayoutDefaultsKey` constant SHALL be used for both the load accessor and every `AppModel` write of a given setting, so a read/write key mismatch is structurally impossible.

## Requirements

### Requirement: RailSize pure seam

A pure, SwiftUI-independent `RailSize` type (renamed from the built `SidebarSize` in `LayoutSizing.swift:13`) SHALL enumerate exactly three cases — `small`, `medium`, `large` — and expose: `width: CGFloat` (rail column width), `tileSize: CGFloat` (avatar tile edge), `showsNames: Bool` (whether account names render beside avatars), and `next: RailSize` (cycle order small → medium → large → small). It SHALL be `String`-`RawRepresentable` (for UserDefaults persistence) and `CaseIterable`.

The mapping SHALL satisfy these CONTRACTUAL invariants (asserted by unit tests):

- `small.width == 56`, `small.tileSize == 38`, `small.showsNames == false` — today's exact rail (`AccountRailView.swift:47,28/54,77`).
- `large.showsNames == true`; `medium.showsNames == false` (medium is bigger tiles but STILL icon-only).
- Widths strictly increasing: `small.width < medium.width < large.width`.
- Tile sizes: `small.tileSize < large.tileSize` and `medium.tileSize > small.tileSize` (non-decreasing, with small the smallest).
- Cycle order: `small.next == medium`, `medium.next == large`, `large.next == small`.

The exact `medium`/`large` pixel values for `width` and `tileSize` are VISUAL-TUNABLE during live verification and SHALL NOT be asserted by unit tests beyond the ordering/flag invariants above. (`small`'s values ARE contractual because `small` must reproduce today's rail exactly.)

#### Scenario: Small is today's rail exactly

- **WHEN** `RailSize.small` is inspected
- **THEN** `width == 56`
- **AND** `tileSize == 38`
- **AND** `showsNames == false`

#### Scenario: Medium is bigger but still icon-only

- **WHEN** `RailSize.medium` is inspected
- **THEN** `showsNames == false`
- **AND** `width > RailSize.small.width`
- **AND** `tileSize > RailSize.small.tileSize`

#### Scenario: Large shows names and is widest

- **WHEN** the three cases are compared
- **THEN** `small.width < medium.width < large.width`
- **AND** `large.showsNames == true`
- **AND** `large.tileSize > small.tileSize`

#### Scenario: Cycle order wraps

- **WHEN** `next` is taken from each case
- **THEN** `small.next == medium`, `medium.next == large`, and `large.next == small`

#### Scenario: Edge case: rawValue round-trip and unknown value

- **GIVEN** each case's `rawValue`
- **WHEN** a `RailSize` is reconstructed from that string
- **THEN** it equals the original case
- **AND** reconstructing from an unrecognized string yields `nil` (so the caller can fall back to `.small`)

### Requirement: clampSidebarWidth pure seam

A pure function `clampSidebarWidth(_ raw: CGFloat) -> CGFloat` SHALL clamp any input to a sensible inclusive range — `[180, 400]` (the lower bound keeps the folder labels legible; the upper bound keeps the list/reader usable). Inputs below the minimum return the minimum, inputs above the maximum return the maximum, in-range inputs return unchanged. This is the single authority for the folder-sidebar width bounds, applied on every drag update, on every programmatic set (`setSidebarWidth`), and on load from persistence (`loadSidebarWidth`). Only the default `232` is contractual; the `[180, 400]` bounds are visual-tunable at live verification and SHALL NOT be asserted as exact magic numbers beyond "232 is in range and unchanged" plus the monotonic clamp behavior.

#### Scenario: Default in-range value unchanged

- **WHEN** `clampSidebarWidth(232)` is called
- **THEN** it returns `232`

#### Scenario: Edge case: below minimum

- **WHEN** an input below the minimum (e.g. `100`) is clamped
- **THEN** it returns the minimum bound

#### Scenario: Edge case: above maximum

- **WHEN** an input above the maximum (e.g. `1000`) is clamped
- **THEN** it returns the maximum bound

### Requirement: clampListWidth pure seam (BUILT / unchanged)

A pure function `clampListWidth(_ raw: CGFloat) -> CGFloat` SHALL clamp any input to the inclusive range `[300, 600]`: inputs below 300 return 300, inputs above 600 return 600, in-range inputs return unchanged (`LayoutSizing.swift:49-51`). This is the single authority for the mail-list width bounds, applied on every list↔reader drag update, on every programmatic set, and on load from persistence. **Already built — unchanged by this spec.**

#### Scenario: In-range value unchanged

- **WHEN** `clampListWidth(380)` is called
- **THEN** it returns `380`

#### Scenario: Edge case: below minimum

- **WHEN** `clampListWidth(120)` is called
- **THEN** it returns `300`

#### Scenario: Edge case: above maximum

- **WHEN** `clampListWidth(5000)` is called
- **THEN** it returns `600`

#### Scenario: Edge case: exact bounds

- **WHEN** `clampListWidth(300)` and `clampListWidth(600)` are called
- **THEN** they return `300` and `600` respectively

### Requirement: AppModel state and persistence

`AppModel` SHALL hold FOUR `@Published` layout values, following the existing `setSidebar`/`persistTweaks` + `UserDefaults` pattern (init load at `AppModel.swift:240-241`, persist at `:520-527`):

- `@Published var railSize: RailSize` — key `LayoutDefaultsKey.railSize` (`"mmail.railSize"`), stored as the size's `rawValue` string, default `.small`.
- `@Published var sidebarLabelsVisible: Bool` — key `LayoutDefaultsKey.sidebarLabels` (`"mmail.sidebarLabels"`), default `true`.
- `@Published var sidebarWidth: CGFloat` — key `LayoutDefaultsKey.sidebarWidth` (`"mmail.sidebarWidth"`), stored as a Double, default `232`, clamped via `clampSidebarWidth` on load AND on every mutation.
- `@Published var listWidth: CGFloat` — key `LayoutDefaultsKey.listWidth` (`"mmail.listWidth"`), stored as a Double, default `380`, clamped via `clampListWidth` on load AND on every mutation. **(BUILT / unchanged.)**

On init, each value SHALL load via its keyless accessor: `railSize = loadRailSize(d)` (unknown/missing → `.small`); `sidebarLabelsVisible = loadSidebarLabels(d)` (missing → `true`); `sidebarWidth = loadSidebarWidth(d)` (missing → 232, clamped); `listWidth = loadListWidth(d)` (missing → 380, clamped). The `object(forKey:) as? Bool`/`as? Double` form (NOT `bool(forKey:)`/`double(forKey:)`) SHALL be used so a MISSING key resolves to the documented default rather than `false`/`0.0`.

Mutators:

- `setRailSize(_:)` — set + persist via `persistTweaks()` (low-frequency: menu click).
- `cycleRailSize()` — set to `railSize.next` + persist via `persistTweaks()` (called by `⌘⇧L`).
- `setSidebarLabels(_:)` and `toggleSidebarLabels()` — set + persist via `persistTweaks()` (menu click).
- `setSidebarWidth(_:)` — set to `clampSidebarWidth(value)` and persist by writing ONLY the `mmail.sidebarWidth` key directly (a TARGETED single-key write). It SHALL NOT call `persistTweaks()`, because the drag path may invoke it many times; a targeted write avoids flushing the whole tweak batch repeatedly.
- `setListWidth(_:)` — **BUILT/unchanged** (`AppModel.swift:1562`): set to `clampListWidth(value)` and write ONLY `mmail.listWidth` directly; SHALL NOT call `persistTweaks()`.

The existing `persistTweaks()` (`AppModel.swift:520-527`) SHALL write the full batch: `kDark`/`kSidebar`/`kReadingPane` (existing) PLUS `railSize.rawValue`, `sidebarLabelsVisible`, `Double(sidebarWidth)`, and `Double(listWidth)` under the canonical `LayoutDefaultsKey` constants — this is the mechanism that makes `setRailSize`/`cycleRailSize`/`setSidebarLabels` survive relaunch. The per-drag paths (`setSidebarWidth`, `setListWidth`) do NOT use `persistTweaks()` — they use a targeted single-key write, invoked once on drag end, never per frame.

That `persistTweaks()` includes `sidebarWidth` and `listWidth` in its complete batch snapshot WHILE `setSidebarWidth`/`setListWidth` ALSO write those same two keys directly is INTENTIONAL, not a double-write bug: the targeted single-key writes are the high-frequency DRAG-path fast-write, while `persistTweaks()` fires ONLY on non-drag changes (rail size, label toggle, dark, reading-pane). The two paths never run on the same user action, and both write the identical `@Published` value, so the snapshot simply re-persists the already-current width — it can never clobber it with a stale value.

#### Scenario: Defaults on a fresh install

- **GIVEN** none of `mmail.railSize`, `mmail.sidebarLabels`, `mmail.sidebarWidth`, `mmail.listWidth` exist in UserDefaults
- **WHEN** `AppModel` initializes
- **THEN** `railSize == .small`
- **AND** `sidebarLabelsVisible == true`
- **AND** `sidebarWidth == 232`
- **AND** `listWidth == 380`

#### Scenario: Persisted values round-trip

- **GIVEN** `setRailSize(.large)`, `setSidebarLabels(false)`, `setSidebarWidth(300)`, and `setListWidth(420)` were called
- **WHEN** a fresh `AppModel` initializes from the same UserDefaults
- **THEN** `railSize == .large`
- **AND** `sidebarLabelsVisible == false`
- **AND** `sidebarWidth == 300`
- **AND** `listWidth == 420`

#### Scenario: setSidebarWidth clamps before persisting

- **WHEN** `setSidebarWidth(1000)` is called
- **THEN** `sidebarWidth` equals the `clampSidebarWidth` maximum
- **AND** the persisted `mmail.sidebarWidth` is that clamped value (never the raw 1000)

#### Scenario: Edge case: corrupt persisted values

- **GIVEN** `mmail.railSize == "huge"`, `mmail.sidebarWidth == 9999`, and `mmail.listWidth == 9999`
- **WHEN** `AppModel` initializes
- **THEN** `railSize == .small`
- **AND** `sidebarWidth` equals the `clampSidebarWidth` maximum
- **AND** `listWidth == 600`

### Requirement: Account rail renders per size

`AccountRailView` SHALL drive its layout from `model.railSize`:

- The rail column `.frame(width:)` (`AccountRailView.swift:47`) SHALL be `model.railSize.width` (replacing the hardcoded `56`).
- Every avatar tile SHALL use `model.railSize.tileSize` instead of the literal `38`: the "All" `GradientTile` (`AccountRailView.swift:54`), each per-account `GradientTile` (`:28`), the `+` add-account button frame (`:37`), and the `railButton` content frame (`:77`). The active-indicator bar (`:80-84`) and unread badge (`:65-74`) SHALL keep their existing geometry (their offsets MAY be tuned at verify so they track the larger tile, but exact offset values are visual-tunable and not asserted).
- When `model.railSize.showsNames == false` (`small`, `medium`), each rail row renders the tile ALONE, centered, exactly as today — only the tile/column size differing between small and medium. NO names.
- When `model.railSize.showsNames == true` (`large`), each rail row SHALL render the tile WITH a trailing name label in a horizontal row (tile + text): the unified "All" row shows `model.allInboxSpec.label` (`AppModel.swift:1684`; `AllInboxSpec.label`, `AvatarSpec.swift:25,31`); each account row shows `a.name` (`Account.name`, `Models.swift:22`; today only surfaced in the tooltip at `AccountRailView.swift:25`). The `+` add-account row MAY show an "Add account" label beside its tile in names mode (cosmetic; the tooltip already says "Add account" at `:44`) — this is visual-tunable at verify, NOT contractual.

The names render SHALL NOT change which tiles are shown, their order, the active selection/indicator behavior, the unread badges, the account-switch action, or the `⌘0`/`⌘N` tooltips — only the visual density (tile size + presence of names).

#### Scenario: Small rail is today's rail

- **GIVEN** `railSize == .small`
- **WHEN** the rail renders
- **THEN** the rail column width is 56 and tiles are 38pt, icon-only (no names)

#### Scenario: Medium rail is bigger, still icon-only

- **GIVEN** `railSize == .medium`
- **WHEN** the rail renders
- **THEN** tiles are larger than 38pt and the column is wider than 56
- **AND** no account names are shown

#### Scenario: Large rail shows names

- **GIVEN** `railSize == .large` with at least one account
- **WHEN** the rail renders
- **THEN** the unified row shows `model.allInboxSpec.label` beside its tile
- **AND** each account row shows the account's `name` beside its tile
- **AND** the column is wider than the medium width

### Requirement: Account Rail Size control (View menu + ⌘⇧L)

`MMailApp.swift:~40-47` CURRENTLY contains a `Menu("Sidebar Size") { Picker… }` whose options are the built `SidebarSize` cases. This block SHALL be REWRITTEN: the View menu SHALL contain an "Account Rail Size" submenu — a dedicated stateful `Menu` in `MMailApp`'s `CommandGroup(after: .sidebar)` (`MMailApp.swift:40-47`), NOT through `MenuModel`/`buildCommands()` (see Invariants) — with three click-only items (Small/Medium/Large) over `RailSize`, the current size marked with a checkmark; selecting an item calls `setRailSize(_:)`. (An implementer seeing the old `"Sidebar Size"` / `SidebarSize` text at this anchor SHALL replace it, not add a parallel menu.) Alongside it in the same `CommandGroup`, the "Show Folder Labels" toggle item (defined in its own Requirement below) is added. `⌘⇧L` SHALL cycle the size via the single existing case in `handleKeyDown`'s cmd+shift switch (`AppModel.swift:3294`), now calling `cycleRailSize()`, returning `true` (handled). The submenu items SHALL NOT register `.keyboardShortcut` accelerators (so `⌘⇧L` is owned solely by `handleKeyDown` and cannot double-fire). At `RootView.swift:~39`, the built `.animation(.easeOut(duration: 0.2), value: model.sidebarSize)` modifier (alongside the `sidebarVisible`/`readingPane` animations at `RootView.swift:37-39`, same `ZStack` in `body`) SHALL be EDITED IN-PLACE so its `value:` becomes `model.railSize`, and a SIBLING `.animation(.easeOut(duration: 0.2), value: model.sidebarLabelsVisible)` SHALL be ADDED so the folder-labels toggle animates too. Both changes glide rail-size and label-density changes consistently with the other layout toggles. The `sidebarWidth` drag SHALL NOT be animated — it tracks the pointer live, so no `.animation(..., value: model.sidebarWidth)` modifier SHALL be added (an animation there would lag the divider behind the cursor); the same applies to the built `listWidth` drag, which is correspondingly un-animated.

#### Scenario: Submenu reflects and sets the current size

- **GIVEN** `railSize == .small`
- **WHEN** the View → Account Rail Size submenu is shown
- **THEN** the Small item is checkmarked and Medium/Large are not
- **AND** clicking Large sets `railSize == .large`

#### Scenario: ⌘⇧L cycles rail size

- **GIVEN** `railSize == .small`
- **WHEN** the user presses `⌘⇧L`
- **THEN** `railSize` becomes `.medium`
- **AND** pressing `⌘⇧L` twice more cycles `.medium → .large → .small`, returning to `.small` (full wrap)

#### Scenario: ⌘⇧L fires consistently with the other cmd+shift shortcuts

- **GIVEN** a text field is focused (e.g. the search field or compose body)
- **WHEN** the user presses `⌘⇧L`
- **THEN** `railSize` still cycles (the cmd+shift block runs before the bare-single-key `isTyping` guard, exactly as `⌘⇧S`/`⌘⇧R`/`⌘⇧D` do today)
- **AND** typing a bare `l` in that field inserts a literal `l` (no single-key `l` binding exists)

#### Scenario: Edge case: ⌘⇧L does not collide

- **WHEN** the user presses `⌘⇧S`, `⌘⇧R`, `⌘⇧D`, and `⌘⇧L` in turn
- **THEN** each performs only its own action (sidebar toggle, reading-pane toggle, dark toggle, rail-size cycle) and none double-fires

### Requirement: Folder labels toggle (View menu, two states)

`SidebarView` SHALL render either today's icons+text layout or the already-built icon-only compact layout, driven by `model.sidebarLabelsVisible`. `SidebarView.swift:~13` CURRENTLY computes the compact flag as `!model.sidebarSize.showsLabels`; this SHALL be REPLACED so the `compact` flag becomes `!model.sidebarLabelsVisible`. (Separately, `SidebarView.swift:~56` CURRENTLY reads `.frame(width: model.sidebarSize.width)` and SHALL be REPLACED with `.frame(width: model.sidebarWidth)` — that width replacement is specified in the "Draggable folder-sidebar ↔ list divider" Requirement below; both `sidebarSize` references at this view SHALL be removed.) When `sidebarLabelsVisible == false`, the sidebar SHALL render the EXISTING compact layout AS-IS (no new layout work):

- Folder rows show the folder icon centered with NO label text, NO shortcut hint, NO numeric unread count, and a `.help(folder.name)` tooltip (`SidebarView.swift:97-99,126`).
- The compose button shows the pencil icon only — no "Compose" text, no `Kbd("C")` (`:68-70`).
- The "LABELS" section header text is hidden; label rows show their colored dot centered with `.help(label.name)` and no text (`:35-43,135-137,153`). (The LABELS section is already absent on the `home` folder — `SidebarView.swift:34` — so compact needs no extra guard there.)
- The footer shows the account/avatar tile only, centered; the name/email text and BOTH the help and settings icon buttons are HIDDEN (`:164-167`). Those buttons remain reachable via the menu bar (Settings `⌘,`, Keyboard Shortcuts `?` / Help menu). This is acceptable and is the same behavior as the built compact render — see Non-Goals.

When `sidebarLabelsVisible == true` (default) the sidebar renders exactly as today (icons + labels + counts). The toggle SHALL NOT change which folders/labels are shown, their order, selection behavior, or actions — only their visual density.

Control: the View menu SHALL contain a "Show Folder Labels" toggle item — added as a dedicated stateful item in `MMailApp`'s `CommandGroup(after: .sidebar)` (a `Toggle` or a checkmarked `Button` reflecting `model.sidebarLabelsVisible`), NOT through `MenuModel`/`buildCommands()` — calling `setSidebarLabels(_:)` / `toggleSidebarLabels()`. It is menu-only: NO keyboard shortcut, NO `.keyboardShortcut`.

#### Scenario: Hiding labels renders the compact sidebar

- **GIVEN** `sidebarLabelsVisible == false`
- **WHEN** the sidebar renders
- **THEN** folder rows show icons with no text labels, and each has a tooltip equal to the folder name
- **AND** the compose button is pencil-only, the LABELS header is hidden, label dots are centered, and the footer is the avatar tile only (help/settings buttons hidden)

#### Scenario: Showing labels renders today's sidebar

- **GIVEN** `sidebarLabelsVisible == true`
- **WHEN** the sidebar renders
- **THEN** folder rows show icon + label + count exactly as before

#### Scenario: Menu toggle flips and persists

- **GIVEN** `sidebarLabelsVisible == true`
- **WHEN** the user clicks View → "Show Folder Labels"
- **THEN** `sidebarLabelsVisible` becomes `false` and the sidebar switches to icons-only
- **AND** the new value survives relaunch

### Requirement: Draggable folder-sidebar ↔ list divider

`SidebarView`'s column `.frame(width:)` (`SidebarView.swift:56`) SHALL be `model.sidebarWidth` (replacing the built `model.sidebarSize.width`). A thin draggable handle SHALL sit between the folder sidebar and the mail list — present ONLY when the folder sidebar and the mail list are shown together (`sidebarVisible == true` AND NOT the `home`/`outbox` branches; `RootView.swift:47-63`). The handle SHALL mirror the existing list↔reader `ListDragHandle` (`RootView.swift:163-211`) EXACTLY, operating on `model.sidebarWidth` / `clampSidebarWidth` / `setSidebarWidth` in place of `listWidth` / `clampListWidth` / `setListWidth`. It MAY be a second instance of the same private struct parameterized by the bound value+clamp+persist, or a sibling private struct following the identical pattern.

Drag mechanics (identical to the built handle):

- The gesture SHALL be `DragGesture(minimumDistance: 0)` so the first `onChanged` fires at touch-down with ~zero translation (a non-zero `minimumDistance` would make the first `onChanged` fire only AFTER the threshold, so the start width could never be captured at translation 0 and the sidebar would jump).
- The width SHALL be captured ONCE per gesture into a local `@State var dragStart: CGFloat?`: on `onChanged`, `if dragStart == nil { dragStart = model.sidebarWidth }`. The implementation MUST `guard let` the captured value and MUST NOT force-unwrap (a cancelled/restarted gesture can deliver `onChanged` with the capture still unset).
- On each `onChanged`, `model.sidebarWidth = clampSidebarWidth(<captured start> + value.translation.width)`. This mutates the `@Published` value for LIVE layout only and SHALL NOT write to UserDefaults.
- On `onEnded`, the model SHALL persist exactly once by calling `setSidebarWidth(model.sidebarWidth)` (a single targeted `mmail.sidebarWidth` write) and reset `dragStart = nil`.
- The handle SHALL show a horizontal-resize cursor on hover via the macOS-14 `NSCursor.resizeLeftRight` push/pop pattern (`.onHover` push/pop tracked by a `pushed` flag, plus an `onDisappear` pop so the cursor can't stick when the sidebar is hidden mid-hover) — `.pointerStyle` is 15.0+ and SHALL NOT be used.

#### Scenario: Dragging resizes the sidebar and reflows the list

- **GIVEN** the folder sidebar is shown with `sidebarWidth == 232`
- **WHEN** the user drags the handle to the right
- **THEN** `sidebarWidth` increases (clamped within bounds) and the mail list absorbs the change

#### Scenario: Drag is clamped at the bounds

- **GIVEN** the folder sidebar is shown
- **WHEN** the user drags the handle far left/right
- **THEN** `sidebarWidth` stops at the `clampSidebarWidth` minimum / maximum and the sidebar never collapses

#### Scenario: New width persists across relaunch

- **GIVEN** the user dragged the sidebar to 300 and released
- **WHEN** the app relaunches
- **THEN** the folder sidebar opens at width 300

#### Scenario: Edge case: no handle when the sidebar is hidden

- **GIVEN** `sidebarVisible == false`
- **WHEN** the layout renders
- **THEN** no sidebar↔list drag handle is present

#### Scenario: Edge case: no handle in home/outbox

- **GIVEN** `folder == "home"` (or `"outbox"`)
- **WHEN** the layout renders
- **THEN** no sidebar↔list drag handle is present (the mail list is not shown)

### Requirement: Draggable list ↔ reader divider (BUILT / unchanged)

In reading-pane mode (`RootView.content`'s `readingPane` branch, `RootView.swift:55-58`), a thin draggable `ListDragHandle` (`RootView.swift:163-211`) sits between `EmailListView` and `ReaderView`. `EmailListView`'s width is `model.readingPane ? model.listWidth : nil` (`EmailListView.swift:30-31`); the reader keeps `maxWidth: .infinity` and fills the remainder. The handle uses `DragGesture(minimumDistance: 0)`, captures `model.listWidth` once into `dragStart`, sets `model.listWidth = clampListWidth(dragStart + translation)` on `onChanged` (live only, no persist), and persists once on `onEnded` via `setListWidth(model.listWidth)`. The macOS-14 `NSCursor.resizeLeftRight` push/pop (with `onDisappear` pop) gives the resize cursor. The handle is absent when the reading pane is off, in `readerFullScreen`, and in `home`/`outbox`. **All of the above is already built and is unchanged by this spec; it is restated here only to document the full feature surface.**

#### Scenario: Dragging resizes the list and reflows the reader

- **GIVEN** reading-pane mode with `listWidth == 380`
- **WHEN** the user drags the handle 60pt to the right
- **THEN** `listWidth` becomes 440 (clamped within bounds) and the reader narrows by the same amount

#### Scenario: Drag is clamped at the bounds

- **GIVEN** reading-pane mode with `listWidth == 380`
- **WHEN** the user drags the handle far left/right
- **THEN** `listWidth` stops at 300 / 600 and the list never collapses below 300

#### Scenario: New width persists across relaunch

- **GIVEN** the user dragged the list to 500 and released
- **WHEN** the app relaunches
- **THEN** the mail list opens at width 500

#### Scenario: Edge case: no handle when reading pane is off

- **GIVEN** `readingPane == false` (single-pane list)
- **WHEN** the layout renders
- **THEN** no list↔reader drag handle is present and the mail list fills the available width as today

### Requirement: Backward-compatible, orthogonal to existing toggles

The feature SHALL NOT alter the behavior of `sidebarVisible`/`setSidebar` (`⌘⇧S`), `readingPane`/`setReadingPane` (`⌘⇧R`), `dark`/`setDark` (`⌘⇧D`), or any existing layout code beyond the documented width/render seams. Hiding the sidebar SHALL still hide it regardless of `sidebarLabelsVisible`/`sidebarWidth`; toggling the reading pane SHALL still show/hide the reader and SHALL NOT reset `listWidth`, `sidebarWidth`, `sidebarLabelsVisible`, or `railSize`.

#### Scenario: Hiding the sidebar is independent of its width/labels

- **GIVEN** `sidebarWidth == 300`, `sidebarLabelsVisible == false`, and `sidebarVisible == true`
- **WHEN** the user presses `⌘⇧S`
- **THEN** the sidebar hides
- **AND** pressing `⌘⇧S` again restores it at width 300, icons-only

#### Scenario: Toggling reading pane preserves all four widths/sizes

- **GIVEN** `listWidth == 500`, `sidebarWidth == 300`, `railSize == .large`, `sidebarLabelsVisible == false`
- **WHEN** the user toggles the reading pane off and back on
- **THEN** all four values are unchanged

## Success Criteria

- **SC-001**: From a cold launch with no stored preferences, the layout is pixel-identical to today — account rail at 56/38 icon-only (`small`), folder sidebar with icons+labels at 232, mail list at 380 in reading-pane mode. (Additive/backward-compatible.)
- **SC-002**: The View menu shows an "Account Rail Size" submenu whose three items (Small/Medium/Large) reflect the current size with a checkmark; clicking an item changes the rail size live and persists across relaunch.
- **SC-003**: `⌘⇧L` cycles the rail size small → medium → large → small with no double-fire and no interference with `⌘⇧S`/`⌘⇧R`/`⌘⇧D`; bare `L` typed in a focused text field inserts a literal `l` (existing `isTyping` guard unaffected); `⌘⇧L` still cycles while a text field is focused, exactly like `⌘⇧S/R/D`.
- **SC-004**: At `small` the rail is today's 56/38 icon-only column; at `medium` the rail is wider with bigger tiles, still icon-only; at `large` the rail shows account names (`a.name`) and `model.allInboxSpec.label` beside larger tiles. (Live-verified.)
- **SC-005**: The View menu shows a "Show Folder Labels" toggle; toggling it switches the folder sidebar between icons+text and the (built) icons-only compact layout, and the choice persists across relaunch. (Live-verified.)
- **SC-006**: In a sidebar-visible non-home/outbox view, the user can drag the sidebar↔list handle to resize the folder sidebar; the list reflows; the width clamps within `clampSidebarWidth` bounds and persists across relaunch. The handle is absent when the sidebar is hidden and in home/outbox. (Live-verified.)
- **SC-007**: In reading-pane mode the (built) list↔reader handle still resizes the mail list, the reader reflows, the width clamps to `[300,600]`, and the new width persists across relaunch. A corrupt/out-of-range persisted `listWidth` resolves to a clamped, usable value on launch. (Live-verified; built portion.)
- **SC-008**: The pure-seam scenarios pass under the project's Swift test target — `RailSize` width/`tileSize`/`showsNames`/`next`/rawValue; `clampSidebarWidth` and `clampListWidth` bounds; and the **load path** via the injectable persistence accessors (`loadRailSize`/`loadSidebarLabels`/`loadSidebarWidth`/`loadListWidth` over a throwaway `UserDefaults` suite, using the canonical key constants): defaults when unset, clamp-on-load of out-of-range widths, and unknown-size → `.small`. The **write path** (that `persistTweaks`/`setSidebarWidth`/`setListWidth` actually write those keys) and the full set→relaunch→read round-trip are verified by **live relaunch** (manual-exploration gate) — the established norm for this project's persistence features — not by constructing a full `AppModel` in a unit test (its init has bootstrap side-effects). Type-check + manual-exploration gates green.
- **SC-009**: With the feature installed, every existing layout control behaves identically — `⌘⇧S` hides/shows the sidebar at its current width/labels, `⌘⇧R` toggles the reading pane without resetting any of the four values, `⌘⇧D` toggles dark, and no shortcut double-fires.

## Non-Goals

- No drag-resizing of the account rail. The rail is preset-only (S/M/L via menu + `⌘⇧L`); its width and tile size come from `RailSize`. There are exactly TWO drag handles total: the NEW folder-sidebar ↔ list handle and the BUILT list ↔ reader handle.
- No migration to `HSplitView` / `NavigationSplitView`. The custom thin handles preserve the existing fixed-frame `HStack` architecture deliberately (split-view divider persistence and min-width control are fragile against the custom rail/sidebar).
- No unread-count substitute in the icons-only folder sidebar — numeric counts are simply hidden in icon-only mode (same as the built compact render; no dot-badge in this iteration).
- The reused icons-only folder sidebar render HIDES the footer help/settings buttons (and the account name/email). Both buttons remain reachable via the menu bar (Settings `⌘,`, Keyboard Shortcuts `?` / Help menu). This is accepted, matches the built compact render, and is tunable at verify if it proves too lossy.
- No user-editable preset values and no Settings UI — the rail S/M/L pixel values and the sidebar/list clamp bounds are fixed in code; the controls live only in the View menu + `⌘⇧L`.
- No per-account or per-folder layout memory — `railSize`, `sidebarLabelsVisible`, `sidebarWidth`, and `listWidth` are global.
- No min-window auto-relayout beyond the fixed clamps — on a very narrow window the reader (the flex `maxWidth: .infinity` column) simply compresses; no special collapse logic.
- No change to the pure `MenuModel`/`buildCommands()` projection — the "Account Rail Size" submenu and the "Show Folder Labels" toggle are added directly in `MMailApp`'s `CommandGroup` as stateful view code (they carry live checkmarks), so `MenuModel` stays a flat, unit-tested group projection and is not extended to support nested submenus or stateful toggles.
- The exact `medium`/`large` rail pixel values, the `clampSidebarWidth [180,400]` bounds, the larger-tile badge/indicator offsets, and whether the `+` add-account row shows a label in names mode are VISUAL-TUNABLE at live verify — only `small == 56/38/icon-only`, `large.showsNames == true`, `sidebarWidth` default `232`, and `listWidth` default `380`/`[300,600]` are contractual.
