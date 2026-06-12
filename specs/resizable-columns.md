# resizable-columns Specification

## Purpose

MMail SHALL let the user adjust two parts of the 4-column layout (`RootView.content`, a fixed-width `HStack`: avatar rail · folder sidebar · mail list · reader): (A) the **folder sidebar** SHALL have three discrete size presets — `small` (icon-only), `medium` (today's icons+labels), `large` (roomier icons+labels) — selected from a "Sidebar Size" submenu in the system View menu and cycled with `⌘⇧L`; and (B) the **mail-list ↔ reader divider** SHALL be draggable (reading-pane mode only) to rebalance the list and reading-pane widths. Both settings SHALL persist across launches and SHALL be purely additive — an existing user with no stored preference lands on `medium` sidebar + a 380pt list, which is the exact current layout, with no visible change until they touch a control. The feature exists so the user can trade folder-label legibility for screen space (compact sidebar) and rebalance list-vs-reader to taste, without the complexity or fragility of full split-view drag dividers on every column.

## Invariants

- The default state SHALL reproduce today's layout EXACTLY: `sidebarSize == .medium` (width 232, labels shown) and `listWidth == 380`. The feature is additive — a user who never opens the menu or drags the divider sees no change. Missing/invalid persisted values SHALL resolve to these defaults.
- `AppModel.handleKeyDown` SHALL remain the sole owner of every keyboard shortcut. The ONLY new key the feature introduces is `⌘⇧L` (cycle sidebar size); it is an unused combo today (`⌘⇧` owns only S/R/D — `AppModel.swift` cmd+shift switch). The new `⌘⇧L` case SHALL sit in that SAME cmd+shift switch and SHALL therefore fire with the EXACT same gating as the existing `⌘⇧S`/`⌘⇧R`/`⌘⇧D` — i.e. it runs BEFORE the `isTyping || anyOverlayOpen` guard (that guard gates only the bare-single-key block lower in `handleKeyDown`), so like the other three it intentionally fires even with a text field focused or an overlay open. It SHALL NOT add an `isTyping`/overlay check the other three lack. The View-menu submenu SHALL NOT attach a `.keyboardShortcut` accelerator to any item — the submenu is click-only and the cycle key lives solely in `handleKeyDown`, so it can never double-fire.
- The "Sidebar Size" submenu SHALL be a dedicated stateful SwiftUI `Menu` added in `MMailApp`'s command block (a `CommandGroup`), NOT routed through the pure `MenuModel.build(from:)` projection. `MenuModel` is a flat group projection of `buildCommands()` (see `specs/menu-bar.md`) and deliberately stays flat; the size submenu is nested and carries a live checkmark on the current size, which is view state, not a flat command. Keeping it out of `MenuModel`/`buildCommands()` preserves that pure projection unchanged.
- The avatar rail width (56, `AccountRailView.swift:47`) SHALL NOT change. Sidebar resizing is preset-only and the rail is excluded from all resizing.
- `listWidth` SHALL apply ONLY in reading-pane mode (when `EmailListView` and `ReaderView` are shown side-by-side). When the reading pane is off, the mail list fills as it does today and `listWidth` has no effect; the drag handle SHALL NOT be present.
- The persisted `listWidth` SHALL ALWAYS be within `clampListWidth`'s bounds — the value is clamped on every mutation AND on load, so a corrupt or out-of-range stored value can never produce an unusable layout.
- Sidebar visibility (`⌘⇧S`, `sidebarVisible`) and reading-pane toggle (`⌘⇧R`, `readingPane`) SHALL remain orthogonal and unchanged: hidden/small/medium/large all coexist, and toggling either does not alter `sidebarSize` or `listWidth`.
- The two pure decision seams — `SidebarSize` (width / `showsLabels` / `next`) and `clampListWidth(_:)` — SHALL contain ALL sizing logic and SHALL be unit-testable without instantiating any view or `AppModel`. Thin persistence accessors (`loadSidebarSize`/`loadListWidth` over an injectable `UserDefaults`, plus canonical key constants) MAY accompany them in the same file; these contain NO sizing logic of their own (they delegate entirely to the two seams for clamping/parsing) and are likewise view/`AppModel`-free and unit-testable.

## Requirements

### Requirement: SidebarSize pure seam

A pure, SwiftUI-independent `SidebarSize` type SHALL enumerate exactly three cases — `small`, `medium`, `large` — and expose: `width: CGFloat`, `showsLabels: Bool`, and `next: SidebarSize` (cycle order small → medium → large → small). It SHALL be `String`-`RawRepresentable` (for UserDefaults persistence) and `CaseIterable`. The mapping SHALL satisfy: `medium.width == 232` and `medium.showsLabels == true` (today's values); `small.showsLabels == false` (icon-only); `large.showsLabels == true`; and `small.width < medium.width < large.width` (strictly increasing). The exact `small` and `large` pixel widths (≈64 and ≈280) are visual-tunable during live verification and SHALL NOT be asserted by unit tests — tests assert the invariants (medium==232, showsLabels per case, strict width ordering, cycle order), not the tunable pixel values.

#### Scenario: Medium is today's layout

- **WHEN** `SidebarSize.medium` is inspected
- **THEN** `width == 232`
- **AND** `showsLabels == true`

#### Scenario: Small is icon-only

- **WHEN** `SidebarSize.small` is inspected
- **THEN** `showsLabels == false`
- **AND** `width < SidebarSize.medium.width`

#### Scenario: Width ordering and label flags

- **WHEN** the three cases are compared
- **THEN** `small.width < medium.width < large.width`
- **AND** `large.showsLabels == true`

#### Scenario: Cycle order wraps

- **WHEN** `next` is taken from each case
- **THEN** `small.next == medium`, `medium.next == large`, and `large.next == small`

#### Scenario: Edge case: rawValue round-trip and unknown value

- **GIVEN** each case's `rawValue`
- **WHEN** a `SidebarSize` is reconstructed from that string
- **THEN** it equals the original case
- **AND** reconstructing from an unrecognized string yields `nil` (so the caller can fall back to `.medium`)

### Requirement: clampListWidth pure seam

A pure function `clampListWidth(_ raw: CGFloat) -> CGFloat` SHALL clamp any input to the inclusive range `[300, 600]`: inputs below 300 return 300, inputs above 600 return 600, in-range inputs return unchanged. This is the single authority for the mail-list width bounds, applied on every drag update, on every programmatic set, and on load from persistence.

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

`AppModel` SHALL hold `@Published var sidebarSize: SidebarSize` and `@Published var listWidth: CGFloat`, following the existing `setSidebar`/`persistTweaks` + `UserDefaults` pattern (`AppModel.swift:233` init load, `:517` persist). Persistence keys SHALL be `mmail.sidebarSize` (stored as the size's `rawValue` string) and `mmail.listWidth` (stored as a Double). On init, `sidebarSize` SHALL load from the stored rawValue falling back to `.medium` for missing/unrecognized values, and `listWidth` SHALL load as `clampListWidth(stored ?? 380)`. Mutators SHALL be:

- `setSidebarSize(_:)` — set + persist via `persistTweaks()` (low-frequency: menu click or `⌘⇧L`).
- `cycleSidebarSize()` — set to `sidebarSize.next` + persist via `persistTweaks()`.
- `setListWidth(_:)` — set to `clampListWidth(value)` and persist by writing ONLY the `mmail.listWidth` key directly. It SHALL NOT call `persistTweaks()`, because the drag path may invoke it many times; a targeted single-key write avoids flushing the whole tweak batch (`dark`/`sidebar`/`readingPane`/`sidebarSize`) repeatedly.

The existing `persistTweaks()` (`AppModel.swift:516-521`, currently writes `kDark`/`kSidebar`/`kReadingPane`) SHALL be MODIFIED to additionally write `mmail.sidebarSize` and `mmail.listWidth` — this is the mechanism that makes `setSidebarSize`/`cycleSidebarSize` survive relaunch (exercised by the "Persisted values round-trip" scenario below; if the function is not extended, sidebar size silently fails to persist with no error). The per-drag persistence path does NOT use `persistTweaks()` — it uses `setListWidth`'s targeted single-key write, invoked once on drag end (see the Draggable requirement), never per frame.

#### Scenario: Defaults on a fresh install

- **GIVEN** no `mmail.sidebarSize` or `mmail.listWidth` keys in UserDefaults
- **WHEN** `AppModel` initializes
- **THEN** `sidebarSize == .medium`
- **AND** `listWidth == 380`

#### Scenario: Persisted values round-trip

- **GIVEN** `setSidebarSize(.small)` and `setListWidth(420)` were called
- **WHEN** a fresh `AppModel` initializes from the same UserDefaults
- **THEN** `sidebarSize == .small`
- **AND** `listWidth == 420`

#### Scenario: setListWidth clamps before persisting

- **WHEN** `setListWidth(1000)` is called
- **THEN** `listWidth == 600`
- **AND** the persisted `mmail.listWidth` is `600` (never the raw 1000)

#### Scenario: Edge case: corrupt persisted values

- **GIVEN** `mmail.sidebarSize == "huge"` and `mmail.listWidth == 9999`
- **WHEN** `AppModel` initializes
- **THEN** `sidebarSize == .medium`
- **AND** `listWidth == 600`

### Requirement: Sidebar renders per size

`SidebarView` SHALL set its column `.frame(width:)` to `model.sidebarSize.width` (replacing the hardcoded 232 at `SidebarView.swift:52`) and SHALL render a **compact icon-only** layout when `model.sidebarSize.showsLabels == false`:

- Folder rows show the folder icon centered with NO label text, NO shortcut hint, and NO numeric unread count; each row carries a `.help(folder.name)` tooltip so the icon is still identifiable on hover.
- The compose button shows the pencil icon only (no "Compose" text, no `Kbd("C")`).
- The "LABELS" section header text is hidden; label rows show their colored dot centered with `.help(label.name)` and no text. (The LABELS section is already absent on the `home` folder — `SidebarView.swift:32` — so compact mode needs no extra guard there; it simply has no LABELS block to hide.)
- The footer shows the account/avatar tile only, centered (no name/email text). The help and settings icon buttons are HIDDEN in compact mode — at the ~64pt small width they would overflow the column (tile 28 + two 14pt buttons + gaps exceeds 64), and both remain reachable via the menu bar (Settings `⌘,`, Keyboard Shortcuts `?` / Help menu) and at medium/large size. This is the one element that is removed (not just relabeled) in compact mode.

When `showsLabels == true` (medium, large) the sidebar renders exactly as today (icons + labels + counts), only the column width differing between medium and large. The compact layout SHALL NOT change which folders/labels are shown, their order, selection behavior, or actions — only their visual density.

#### Scenario: Compact sidebar hides labels, keeps tooltips

- **GIVEN** `sidebarSize == .small`
- **WHEN** the sidebar renders
- **THEN** folder rows show icons with no text labels
- **AND** each folder row has a tooltip equal to the folder name
- **AND** the column width equals `SidebarSize.small.width`

#### Scenario: Medium renders today's layout

- **GIVEN** `sidebarSize == .medium`
- **WHEN** the sidebar renders
- **THEN** folder rows show icon + label + count exactly as before
- **AND** the column width is 232

#### Scenario: Large widens without changing content

- **GIVEN** `sidebarSize == .large`
- **WHEN** the sidebar renders
- **THEN** folder rows show icon + label + count (labels still shown)
- **AND** the column width is greater than 232

### Requirement: Sidebar Size control (View menu + ⌘⇧L)

The View menu SHALL contain a "Sidebar Size" submenu — added as a dedicated stateful `Menu` in `MMailApp`'s `CommandGroup` (NOT through `MenuModel`/`buildCommands()`; see Invariants) — with three click-only items — Small, Medium, Large — the current size marked with a checkmark; selecting an item calls `setSidebarSize(_:)`. `⌘⇧L` SHALL cycle the size via a single new case in `handleKeyDown`'s cmd+shift switch (calling `cycleSidebarSize()`), returning `true` (handled). The submenu items SHALL NOT register `.keyboardShortcut` accelerators (so `⌘⇧L` is owned solely by `handleKeyDown` and cannot double-fire). A `.animation(.easeOut(duration: 0.2), value: model.sidebarSize)` modifier SHALL be added alongside the existing `sidebarVisible`/`readingPane` animations at `RootView.swift:37-38` (the same `ZStack` in `body`), so size changes glide consistently with how the existing layout toggles animate.

#### Scenario: Submenu reflects and sets the current size

- **GIVEN** `sidebarSize == .medium`
- **WHEN** the View → Sidebar Size submenu is shown
- **THEN** the Medium item is checkmarked and Small/Large are not
- **AND** clicking Large sets `sidebarSize == .large`

#### Scenario: ⌘⇧L cycles size

- **GIVEN** `sidebarSize == .medium`
- **WHEN** the user presses `⌘⇧L`
- **THEN** `sidebarSize` becomes `.large`
- **AND** pressing `⌘⇧L` twice more cycles `.large → .small → .medium`, returning to `.medium` (full wrap)

#### Scenario: ⌘⇧L fires consistently with the other cmd+shift shortcuts

- **GIVEN** a text field is focused (e.g. the search field or compose body)
- **WHEN** the user presses `⌘⇧L`
- **THEN** `sidebarSize` still cycles (the cmd+shift block runs before the bare-single-key `isTyping` guard, exactly as `⌘⇧S`/`⌘⇧R`/`⌘⇧D` do today)
- **AND** typing a bare `l` in that field inserts a literal `l` (no single-key `l` binding exists)

#### Scenario: Edge case: ⌘⇧L does not collide

- **WHEN** the user presses `⌘⇧S`, `⌘⇧R`, `⌘⇧D`, and `⌘⇧L` in turn
- **THEN** each performs only its own action (sidebar toggle, reading-pane toggle, dark toggle, sidebar-size cycle) and none double-fires

### Requirement: Draggable list ↔ reader divider

In reading-pane mode (`RootView.content`'s `readingPane` branch, where `EmailListView` and `ReaderView` are shown together), a thin draggable handle SHALL sit between the list and the reader. `EmailListView`'s width SHALL be applied as a fixed `.frame(width: model.listWidth)` (replacing the hardcoded `380` at both `EmailListView.swift:30` and `:31` — the `model.readingPane ? 380 : nil` / `? 380 : .infinity` pair becomes `model.readingPane ? model.listWidth : nil` / `? model.listWidth : .infinity`); the reader keeps `maxWidth: .infinity` and fills the remainder.

Drag mechanics SHALL be:

- The handle's gesture SHALL be `DragGesture(minimumDistance: 0)` so the first `onChanged` fires at touch-down with ~zero translation (a non-zero `minimumDistance` would make `onChanged` first fire only AFTER the threshold is crossed, so the start width could never be captured at translation 0 and the list would jump on drag start).
- The list width SHALL be captured ONCE per gesture into a local `@State var dragStartWidth: CGFloat?`: on `onChanged`, `if dragStartWidth == nil { dragStartWidth = model.listWidth }`. This anchors the gesture to the width at its start and prevents translations accumulating across successive drags. (A `@GestureState` that auto-resets between gestures is an acceptable equivalent; the broken pattern to AVOID is gating capture on `translation.width == 0`, which never holds once `onChanged` fires under a non-zero `minimumDistance`.)
- On each `onChanged`, after the nil-capture, `model.listWidth = clampListWidth(<captured start width> + value.translation.width)` using the SAFELY-unwrapped captured width — the implementation MUST `guard let` the captured value and MUST NOT force-unwrap (a cancelled/restarted gesture can deliver `onChanged` with the capture still unset). This mutates the `@Published` value for LIVE layout only and SHALL NOT write to UserDefaults.
- On `onEnded`, the model SHALL persist exactly once by calling `setListWidth(model.listWidth)` (its clamp is a harmless no-op here since `onChanged` already clamped; the call's purpose is the single targeted `mmail.listWidth` write) and then reset `dragStartWidth = nil`.

The handle SHALL show a horizontal-resize cursor on hover. The handle SHALL NOT appear when the reading pane is off, in `readerFullScreen`, or in the `home`/`outbox` branches. On a window too narrow to hold rail + sidebar + `listWidth` + reader, the reader (the flex `maxWidth: .infinity` column) compresses — no special collapse logic (see Non-Goals); this matches today's behavior with the fixed 380 list.

#### Scenario: Dragging resizes the list and reflows the reader

- **GIVEN** reading-pane mode with `listWidth == 380`
- **WHEN** the user drags the handle 60pt to the right
- **THEN** `listWidth` becomes 440 (clamped within bounds)
- **AND** the reader pane narrows by the same amount

#### Scenario: Drag is clamped at the bounds

- **GIVEN** reading-pane mode with `listWidth == 380`
- **WHEN** the user drags the handle far to the left (beyond the 300 minimum)
- **THEN** `listWidth` stops at 300 and the list never collapses below it
- **AND** dragging far right stops at 600

#### Scenario: New width persists across relaunch

- **GIVEN** the user dragged the list to 500 and released
- **WHEN** the app relaunches
- **THEN** the mail list opens at width 500

#### Scenario: Edge case: no handle when reading pane is off

- **GIVEN** `readingPane == false` (single-pane list)
- **WHEN** the layout renders
- **THEN** no drag handle is present and the mail list fills the available width as today

### Requirement: Backward-compatible, orthogonal to existing toggles

The feature SHALL NOT alter the behavior of `sidebarVisible`/`setSidebar` (`⌘⇧S`), `readingPane`/`setReadingPane` (`⌘⇧R`), or any existing layout code beyond the documented width/render seams. Hiding the sidebar SHALL still hide it regardless of `sidebarSize`; toggling the reading pane SHALL still show/hide the reader and SHALL NOT reset `listWidth` or `sidebarSize`.

#### Scenario: Hiding the sidebar is independent of its size

- **GIVEN** `sidebarSize == .large` and `sidebarVisible == true`
- **WHEN** the user presses `⌘⇧S`
- **THEN** the sidebar hides
- **AND** pressing `⌘⇧S` again restores it at `large` width

#### Scenario: Toggling reading pane preserves widths

- **GIVEN** `listWidth == 500` and `sidebarSize == .small`
- **WHEN** the user toggles the reading pane off and back on
- **THEN** `listWidth` is still 500 and `sidebarSize` is still `.small`

## Success Criteria

- **SC-001**: From a cold launch with no stored preferences, the layout is pixel-identical to today — sidebar at 232 with icons+labels, mail list at 380 in reading-pane mode. (Additive/backward-compatible.)
- **SC-002**: The View menu shows a "Sidebar Size" submenu whose three items (Small/Medium/Large) reflect the current size with a checkmark; clicking an item changes the sidebar width/density live and persists across relaunch.
- **SC-003**: `⌘⇧L` cycles the sidebar size small → medium → large → small with no double-fire and no interference with `⌘⇧S`/`⌘⇧R`/`⌘⇧D`; bare `L` typed in a focused text field inserts a literal `l` (existing `isTyping` guard unaffected).
- **SC-004**: At `small`, the sidebar is an icon-only column (no folder/label text, tooltips present on hover); at `medium` it is today's icons+labels at 232; at `large` it shows icons+labels at a visibly wider column. (Live-verified.)
- **SC-005**: In reading-pane mode the user can drag the list↔reader handle to resize the mail list, the reader reflows accordingly, and the new width persists across relaunch. (Live-verified.)
- **SC-006**: The mail list cannot be dragged narrower than 300 or wider than 600; the reader is never fully covered and the list never collapses. A corrupt/out-of-range persisted `listWidth` resolves to a clamped, usable value on launch.
- **SC-007**: The pure-seam scenarios pass under the project's Swift test target — `SidebarSize` width/`showsLabels`/`next`/rawValue; `clampListWidth` bounds; and the **load path** via the injectable persistence accessors (`loadSidebarSize`/`loadListWidth` over a throwaway `UserDefaults` suite, using the canonical key constants): defaults when unset, clamp-on-load of out-of-range widths, and unknown-size → `.medium`. The **write path** (that `persistTweaks`/`setListWidth` actually write those keys) and the full set→relaunch→read round-trip are verified by **live relaunch** (manual-exploration gate, T018) — the established norm for this project's persistence features — not by constructing a full `AppModel` in a unit test (its init has bootstrap side-effects). Type-check + manual-exploration gates green.
- **SC-008**: With the feature installed, every existing layout control behaves identically — `⌘⇧S` hides/shows the sidebar at its current size, `⌘⇧R` toggles the reading pane without resetting widths, and no shortcut double-fires.

## Non-Goals

- No drag-resizing of the avatar rail, the folder sidebar, or the sidebar↔list boundary. The sidebar is preset-only (S/M/L); the rail is fixed at 56. The ONLY draggable divider is list↔reader.
- No migration to `HSplitView` / `NavigationSplitView`. The custom thin handle preserves the existing fixed-frame `HStack` architecture deliberately (split-view divider persistence and min-width control are fragile against the custom rail/sidebar).
- No unread-count substitute in the compact (small) sidebar — numeric counts are simply hidden in icon-only mode (no dot-badge in this iteration). *(Flagged for readback: if losing the at-a-glance unread signal in compact mode is unacceptable, a small unread dot can be added — say so and it becomes a requirement.)*
- No user-editable preset width *values* and no Settings UI — the S/M/L numbers are fixed in code, and the controls live only in the View menu + `⌘⇧L` (per the chosen design).
- No per-account or per-folder layout memory — `sidebarSize` and `listWidth` are global.
- No min-window auto-relayout beyond the fixed `[300, 600]` list clamp — on a very narrow window the reader (the flex column) simply compresses; no special collapse logic.
- No change to the pure `MenuModel`/`buildCommands()` projection — the "Sidebar Size" submenu is added directly in `MMailApp`'s `CommandGroup` as stateful view code (it carries a live checkmark), so `MenuModel` stays a flat, unit-tested group projection and is not extended to support nested submenus.
