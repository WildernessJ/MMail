# menu-bar Specification

## Purpose

MMail SHALL present a native macOS menu bar (a Message menu and a Go menu, plus View-category items integrated into the system-provided View menu, alongside the system App / Edit / Window / Help menus) that acts as a **read-only discovery-and-click layer** over the commands defined in `AppModel.buildCommands()`. Each menu item SHALL run the exact same action as its command-palette counterpart and SHALL display that command's shortcut as text in the item's title. The existing keyboard engine (`AppModel.handleKeyDown`) SHALL remain the owner of every existing shortcut; the menu SHALL NOT introduce any NEW keyboard accelerator except `⌘,` for Settings (which has no existing key binding). The feature exists to make MMail's commands and their (mostly vim-style, single-key) shortcuts discoverable without a cheat-sheet, and to provide the standard macOS `⌘,` entry point to Settings.

## Invariants

- The menu SHALL NOT register any NEW keyboard accelerator except Settings (`⌘,`). Every existing shortcut is rendered as **text in the item title**, never as a new SwiftUI `.keyboardShortcut` accelerator, so the menu can never compete with `handleKeyDown` or double-fire an action. (The one pre-existing accelerator — `?` on the existing Help item, `MMailApp.swift:21` — is retained unchanged; see the Help requirement.)
- The menu SHALL NOT define a second copy of the command list. Its contents derive entirely from `AppModel.buildCommands()` — the single source of truth — so palette and menu cannot drift apart.
- Clicking a menu item SHALL invoke the same `Command.run` closure that the command palette would invoke for that command id.
- `AppModel.handleKeyDown` behavior SHALL NOT change for any existing shortcut: no existing shortcut is altered, removed, or re-owned by the menu. Pressing a key (e.g. `E` to archive) SHALL perform its action exactly once. (`handleKeyDown` MAY gain a single new `⌘,` case only as the documented fallback in the Settings requirement.)
- The menu bar SHALL NOT create a top-level menu whose name duplicates a system-provided menu (App / File / Edit / View / Window / Help). View-category commands integrate into the existing View menu via `CommandGroup` insertion; only non-colliding names (Message, Go) are introduced as new `CommandMenu`s.
- The Settings command SHALL be reachable from the macOS application menu via `⌘,` and from the command palette, and both paths SHALL open the same in-app Settings surface (`AppModel.settings = true`).

## Requirements

### Requirement: Source command list additions

`buildCommands()` SHALL gain one new command so the command palette (⌘K) is itself discoverable, and the Settings command SHALL carry a shortcut hint, keeping the palette and the menu as one source of truth:

- A new command `id: "palette"`, `group: "App"`, label "Command palette", `shortcut: "⌘K"`, whose `run` toggles the command palette (the same action `handleKeyDown` performs for ⌘K). It is display-only in both surfaces (⌘K stays owned by `handleKeyDown`). It SHALL be appended at the END of the existing App group (immediately after the `reading` command, before the `Accounts` group).
- The existing `settings` command (`id: "settings"`) SHALL set `shortcut: "⌘,"` so both the palette and the menu show the Settings shortcut consistently.

No other command in `buildCommands()` changes: same ids, groups, labels, relative order, and actions. After these additions the App group's source order is: `search`, `help`, `settings`, `dark`, `sidebar`, `reading`, `palette`.

#### Scenario: Palette command present and discoverable

- **GIVEN** the updated `buildCommands()`
- **WHEN** the command list is enumerated
- **THEN** it contains a command `id == "palette"` in group `App` with shortcut `⌘K`
- **AND** the `settings` command has shortcut `⌘,`

### Requirement: Pure menu model derived from commands

A pure, SwiftUI-independent function SHALL transform the `[Command]` list from `buildCommands()` into an ordered set of menu placements: the **Message** menu, the **Go** menu, and the **View-insertion** group (items destined for the system View menu). Each placement carries an ordered list of items (label, optional shortcut-hint text, command id). This function SHALL be unit-testable without instantiating any view, and SHALL be the single place that decides which command goes where and how its shortcut hint is formatted. Within every placement the function SHALL **preserve the relative order of commands as they appear in `buildCommands()`** (it is a faithful group projection — filter by group, keep source order, exclude the two routed-elsewhere App commands); it SHALL NOT reorder.

The routing SHALL be:

- `Mail` group → **Message** menu (first section).
- `Triage` group → **Message** menu (second section, after a divider).
- `Go to` group → **Go** menu (first section).
- `Accounts` group → **Go** menu (second section, after a divider).
- `App` group → **View-insertion** group, **excluding** the `settings` command (routed to the application menu) and the `help` command (routed to the Help menu, already registered). Preserving source order, the View-insertion items are: Search `/`, Dark Mode `⌘⇧D`, Sidebar `⌘⇧S`, Reading Pane `⌘⇧R`, Command palette `⌘K`.

#### Scenario: Message menu composition and order

- **GIVEN** the default command list from `buildCommands()` with no accounts configured
- **WHEN** the menu model is built
- **THEN** the Message menu contains, in order, the Mail-group items (Compose, Reply, Reply All, Forward) then a divider then the Triage-group items (Archive, Done, Snooze, Delete, Mark Unread, Star)
- **AND** each item's hint text equals its command's `shortcut` string (e.g. Archive → `E`, Compose → `C`)

#### Scenario: Go menu composition with accounts

- **GIVEN** a command list containing the `Go to` group and two configured accounts plus the `acct-all` and `acct-add` commands
- **WHEN** the menu model is built
- **THEN** the Go menu contains the folder navigation items (Inbox `G I`, Home `G H`, Starred `G S`, Snoozed `G Z`, Done `G E`, Sent `G T`, Drafts `G D`), then a divider, then All Inboxes `⌘0`, the two per-account "Switch to …" items (`⌘1`, `⌘2`), and Add Account…

#### Scenario: App-group commands route to View-insertion, excluding settings and help

- **GIVEN** the default command list (including the new `palette` command)
- **WHEN** the menu model is built
- **THEN** the View-insertion group contains exactly, in `buildCommands()` source order: Search `/`, Dark Mode `⌘⇧D`, Sidebar `⌘⇧S`, Reading Pane `⌘⇧R`, Command palette `⌘K`
- **AND** the `settings` command does NOT appear in the View-insertion group
- **AND** the `help` command does NOT appear in the View-insertion group

#### Scenario: Edge case: a command with no shortcut

- **GIVEN** a command whose `shortcut` is `nil` (e.g. Add Account…)
- **WHEN** the menu model is built
- **THEN** that item appears with an empty/absent hint and no trailing shortcut text
- **AND** no crash or placeholder string is emitted

### Requirement: Menu rendering shows shortcuts as text hints

The SwiftUI `.commands` block SHALL render the menu model as native menus whose items show the shortcut hint as **text within the title** (e.g. `Archive    E`, `Dark Mode    ⌘⇧D`), and SHALL NOT attach a `.keyboardShortcut` accelerator to any of these items. Multi-character hints that denote a sequential two-key chord (the `g`-prefix navigation: `G I`, `G H`, etc., handled by the `pendingG` window at `AppModel.swift:3031`) are intentionally shown as their raw two-letter text; the rendering is deliberately non-standard (a sequential tap, not a modifier chord) and SHALL match the command's `shortcut` string verbatim.

#### Scenario: Bare-key command rendered as text hint

- **GIVEN** the Archive command (shortcut `E`)
- **WHEN** the Message menu is shown
- **THEN** the Archive item's visible title includes the text `E`
- **AND** pressing the bare key `E` (handled by `handleKeyDown`) still archives exactly once, with no contribution from the menu

#### Scenario: Existing ⌘ command rendered as text, not accelerator

- **GIVEN** the Toggle Dark Mode command (shortcut `⌘⇧D`)
- **WHEN** the View menu is shown
- **THEN** the item's visible title includes the text `⌘⇧D`
- **AND** the menu does NOT register `⌘⇧D` as an accelerator
- **AND** pressing `⌘⇧D` toggles dark mode exactly once (owned by `handleKeyDown`)

### Requirement: View-category items integrate into the system View menu

The View-insertion items SHALL be added to the existing system **View** menu via `CommandGroup` insertion. The menu bar SHALL show exactly one View menu — no second menu named "View".

#### Scenario: Exactly one View menu

- **GIVEN** the app is running with the menu bar installed
- **WHEN** the menu bar is inspected
- **THEN** there is exactly one top-level menu titled "View"
- **AND** it contains the View-insertion items (Search, Dark Mode, Sidebar, Reading Pane, Command palette) in addition to any system-provided View items

### Requirement: Settings accelerator

The application menu SHALL contain a **Settings…** item that opens the in-app Settings surface (`AppModel.settings = true`) and is bound to `⌘,`. This is the only NEW accelerator the feature introduces. The binding SHALL be implemented via `CommandGroup(replacing: .appSettings)` and live-verified on the target macOS; if that mechanism does not reliably bind `⌘,` on the target OS (a known version-sensitivity when no `Settings {}` scene is present), the fallback SHALL be a single new `⌘,` case in `handleKeyDown` (consistent with how every other shortcut is owned), with the menu item showing `⌘,` as a text hint. Exactly one mechanism SHALL be active so `⌘,` never double-fires.

#### Scenario: ⌘, opens Settings

- **GIVEN** the app is running with no text field focused and no overlay open
- **WHEN** the user presses `⌘,`
- **THEN** the in-app Settings surface opens (`settings == true`) exactly once

#### Scenario: Settings reachable by click

- **GIVEN** the application menu is open
- **WHEN** the user clicks Settings…
- **THEN** the in-app Settings surface opens

### Requirement: Help menu unchanged, help not duplicated

The existing `CommandGroup(replacing: .help)` in `MMailApp.swift:19` (the "MMail Keyboard Shortcuts" button bound to `?`) SHALL be retained unchanged. Because the `help` command is already represented there, the menu model SHALL route `help` to the Help menu by EXCLUDING it from the View-insertion group (per the routing rule) and SHALL NOT add a second Help registration or a duplicate Keyboard-Shortcuts item.

#### Scenario: Single Keyboard-Shortcuts entry

- **GIVEN** the menu bar is installed
- **WHEN** the Help menu is inspected
- **THEN** it contains exactly one "MMail Keyboard Shortcuts" item bound to `?`
- **AND** no Keyboard-Shortcuts item appears in any other menu
- **AND** pressing `?` (consumed by `handleKeyDown` when its guards pass; handled by the retained Help accelerator otherwise) opens the shortcuts help exactly once

### Requirement: Dynamic account items stay in sync

The Go menu's account section SHALL reflect the current set of configured accounts and SHALL update when an account is added or removed, without an app relaunch. This relies on SwiftUI re-evaluating the `App` body's `.commands` block when `AppModel`'s `@Published accounts` changes; it is verified by live test (the pure menu-model unit test covers only the transform, not SwiftUI's re-evaluation — see Success Criteria).

#### Scenario: Adding an account adds a Go-menu item

- **GIVEN** one configured account (Go menu shows All Inboxes `⌘0`, Switch to A `⌘1`, Add Account…)
- **WHEN** a second account is added
- **THEN** the Go menu shows a Switch to B `⌘2` item without relaunch

#### Scenario: Removing an account removes its Go-menu item

- **GIVEN** two configured accounts
- **WHEN** one account is removed
- **THEN** that account's Switch-to item no longer appears in the Go menu without relaunch

### Requirement: Existing keyboard engine unchanged

The feature SHALL NOT modify the behavior of any existing shortcut in `AppModel.handleKeyDown` (the only permitted addition is the optional `⌘,` fallback case). Every shortcut that worked before SHALL work identically after, and no shortcut SHALL fire its action more than once.

#### Scenario: No double-fire on an existing ⌘ shortcut

- **GIVEN** the menu bar is installed
- **WHEN** the user presses `⌘K`
- **THEN** the command palette toggles exactly once (no second toggle from a menu accelerator)

#### Scenario: Bare vim keys still gated while typing

- **GIVEN** a text field is focused (e.g. the compose body)
- **WHEN** the user types `e`
- **THEN** the literal character `e` is inserted and no Archive action fires (menu registers no `E` accelerator, so the existing `isTyping` guard in `handleKeyDown` is still the only arbiter)

## Success Criteria

- **SC-001**: From a cold launch, the macOS menu bar shows a Message menu, a Go menu, and View-category items inside the single system View menu (alongside the system App / Edit / Window / Help menus). Every command from the updated `buildCommands()` appears exactly once across the menus (Settings in the App menu, Keyboard Shortcuts in Help, the rest in Message / Go / View). There is no duplicate top-level menu name.
- **SC-002**: Pressing `⌘,` opens the in-app Settings surface exactly once from a non-text, no-overlay context.
- **SC-003**: Clicking a sampled item from each of Message, Go, and View performs the identical action to its keyboard/palette counterpart (live-verified).
- **SC-004**: Every menu item displays its command's shortcut as text in the title; bare keys (`E`, `G I`, `/`) and ⌘ combos (`⌘⇧D`, `⌘K`, `⌘0`) are all shown as text, and `⌘,` is the only working native accelerator the feature adds.
- **SC-005**: Adding then removing an account updates the Go menu's account list within the same app session (no relaunch). This is a live-test-only criterion (no unit coverage of SwiftUI re-evaluation).
- **SC-006**: No existing shortcut changes behavior and none double-fires — pressing `E` archives once, `⌘⇧D` toggles dark once, `⌘K` toggles the palette once, `?` opens help once, and `e` typed in a focused text field inserts a literal `e`.
- **SC-007**: The pure menu-model scenarios above (Message/Go/View-insertion composition, no-shortcut edge case, palette/settings additions) pass under the project's Swift test target, and the type-check + manual-exploration gates are green.

## Non-Goals

- No graying-out / enable-disable of menu items based on selection or context — clicking an item that has no valid target no-ops exactly as the keyboard shortcut does today.
- No new keyboard shortcuts beyond `⌘,` — the menu does not introduce `⌘N`, `⌘⌫`, or any other conventional Mac accelerator, and does not re-home any existing shortcut from `handleKeyDown` onto a menu accelerator.
- No reordering, renaming, or removal of existing palette commands. The only `buildCommands()` changes are the added `palette` command and the `⌘,` hint on the `settings` command (Requirement: Source command list additions).
- No user-customizable or persisted menu layout (that is backlog #7, toolbar/menu customization).
- No MenuBarExtra / status-bar item — this is the in-window application menu bar only.
