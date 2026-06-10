# menu-bar Implementation Plan

**Goal:** Add a native macOS menu bar (Message + Go menus, View-category items in the system View menu, Settings ⌘,) that is a read-only discovery + click layer over `buildCommands()`, registering no new accelerator except ⌘,.

**Architecture:** A pure, SwiftUI-free `MenuModel` (new file `MMail/State/MenuModel.swift`) projects the `[Command]` list from `AppModel.buildCommands()` into ordered menu placements (Message, Go, View-insertion), preserving source order within each group and routing `settings`/`help` out of the View group. The SwiftUI `.commands` block in `MMailApp.swift` renders those placements — `CommandMenu("Message")`, `CommandMenu("Go")`, a `CommandGroup` inserted into the system View menu, and `CommandGroup(replacing: .appSettings)` for Settings ⌘, — with each item's title carrying its shortcut as TEXT and only the Settings item bound to an accelerator. `buildCommands()` gains a `palette` command (App group, end) and a ⌘, hint on `settings`. The key engine `handleKeyDown` is untouched except for the documented ⌘, fallback.

**Test Methodology:** e2e-first (from `.harness.yaml`). The pure `MenuModel` carries the automatable behavioral coverage (swift-testing, mirroring the spec scenarios); the SwiftUI menu rendering, ⌘,, no-double-fire, single-View-menu, and dynamic-account behaviors are live/manual verification (macOS GUI, not unit-testable) — confirmed in /verify.

**Test commands:**
- Type-check / build: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- Unit tests: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- New `.swift` files require `xcodegen generate` first, then commit the regenerated `MMail.xcodeproj/project.pbxproj` (project.yml globs the folders; pbxproj is git-tracked).

---

## Phase A — Pure menu model (automatable)

- [ ] **T001 (SC: 007): Define MenuModel types** — Create `MMail/State/MenuModel.swift` with SwiftUI-free value types: `MenuItem` (`commandId: String`, `label: String`, `hint: String?`), `MenuRow` (an enum: `.item(MenuItem)` or `.divider`), and `MenuModel` exposing `message: [MenuRow]`, `go: [MenuRow]`, `viewInsertion: [MenuItem]`, plus a `static func build(from commands: [Command]) -> MenuModel` declared returning empty placements for now (stub). No `import SwiftUI`/`AppKit` — only `Foundation`. Then `xcodegen generate` (new file) and build.
  - Run: `xcodegen generate && xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles; `project.pbxproj` now lists `MenuModel.swift`)
  - **Files:** `MMail/State/MenuModel.swift` (new), `MMail.xcodeproj/project.pbxproj` (regenerated)

- [ ] **T002 (SC: 007): Failing unit tests from spec scenarios** — Create `MMailTests/MenuModelTests.swift` (`import Testing`, `@testable import MMail`, `@Suite struct MenuModelTests`). Encode the spec's pure-model scenarios against `MenuModel.build(from:)`, building input `[Command]` arrays directly (do NOT depend on a live `AppModel`): (a) Message menu = Compose, Reply, Reply All, Forward, divider, Archive, Done, Snooze, Delete, Mark Unread, Star — with hints `C/R/A/F` and `E/H/Z/#/U/S`; (b) Go menu with two accounts = Inbox…Drafts (hints `G I`…`G D` — assert the space is preserved verbatim, e.g. `"G I"` not `"GI"`, matching the `buildCommands()` strings at `AppModel.swift:1463`), divider, All Inboxes `⌘0`, Switch-to ⌘1/⌘2, Add Account… (nil hint); (c) View-insertion = Search `/`, Dark `⌘⇧D`, Sidebar `⌘⇧S`, Reading `⌘⇧R`, Command palette `⌘K` in that source order, and assert `settings` + `help` are ABSENT from `viewInsertion`; (d) edge case: a command with `shortcut == nil` yields `hint == nil` and no placeholder; (e) order-preservation: shuffle is not applied — items follow input order within group. Then `xcodegen generate` (new test file) and run tests.
  - Run: `xcodegen generate && xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
  - Expected: FAIL — assertions fail because `build(from:)` returns empty placements ("not implemented")
  - **Files:** `MMailTests/MenuModelTests.swift` (new), `MMail.xcodeproj/project.pbxproj` (regenerated)

- [ ] **T003 (SC: 001, 004, 007): Implement the pure builder + commit** — Implement `MenuModel.build(from:)` as a faithful group projection: filter `commands` by `group`, preserve relative order, map each `Command` → `MenuItem(commandId: id, label: label, hint: shortcut)`; compose Message = Mail-group rows + `.divider` + Triage-group rows; Go = `Go to`-group rows + `.divider` + Accounts-group rows; `viewInsertion` = App-group items EXCLUDING ids `settings` and `help`. No reordering. Make all T002 assertions green, then commit.
  - Run: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (all MenuModelTests green; existing 154 tests still green)
  - **Files:** `MMail/State/MenuModel.swift`

- [ ] **T004 (SC: 001, 004): Add `palette` command + ⌘, hint to buildCommands + commit** — In `AppModel.buildCommands()` (`MMail/State/AppModel.swift:1451`): append `Command(id: "palette", group: "App", label: "Command palette", icon: "command", shortcut: "⌘K") { [weak self] in self?.palette.toggle() }` at the END of the App group (immediately after the `reading` command, before the `Accounts` block). Set `shortcut: "⌘,"` on the existing `settings` command. Add a `MenuModelTests` assertion (or extend an existing one) that the built model from the REAL `buildCommands()` output places `palette` in `viewInsertion` (last) and that BOTH `settings` AND `help` are absent from `viewInsertion` — i.e. `#expect(!model.viewInsertion.map(\.commandId).contains("settings"))` and `#expect(!model.viewInsertion.map(\.commandId).contains("help"))` (guards against a future regroup/rename of either routed-elsewhere command). Commit.
  - Run: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS
  - **Files:** `MMail/State/AppModel.swift`, `MMailTests/MenuModelTests.swift`

---

## Phase B — SwiftUI menu wiring (live-verified)

- [ ] **T005 (SC: 001, 003, 004): Render Message + Go menus and View-insertion** — In `MMailApp.swift` `.commands { … }`, build the menu model once from `model.buildCommands()` and render: `CommandMenu("Message")` with the `message` rows; `CommandMenu("Go")` with the `go` rows; and `CommandGroup(after: .sidebar) { … }` (inserts into the existing system View menu — verify exactly one "View" menu results) with the `viewInsertion` items. Render each `MenuItem` as `Button(titleWithHint(item)) { model.run(item.commandId) }` where `titleWithHint` appends the hint as trailing text (e.g. `"Archive    E"`) and `model.run(_:)` is a small new `AppModel` helper that looks the command up by id in `buildCommands()` and calls its `run`. Render `.divider` rows as `Divider()`. Attach NO `.keyboardShortcut` to any of these. Keep the existing `CommandGroup(replacing: .help)` untouched. Build (type-check only here).
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles)
  - **Files:** `MMail/MMailApp.swift`, `MMail/State/AppModel.swift` (add `func run(_ id: String)` helper)

- [ ] **T006 (SC: 002): Settings ⌘, via appSettings + commit** — Add `CommandGroup(replacing: .appSettings) { Button("Settings…") { model.settings = true }.keyboardShortcut(",", modifiers: .command) }` to the `.commands` block. This is the ONLY accelerator the feature adds. Build, then commit Phase-B wiring.
  - Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - Expected: PASS (compiles)
  - **Files:** `MMail/MMailApp.swift`

---

## Phase C — Live verification (manual; finalized in /verify)

- [ ] **T007 (SC: 002): ⌘, opens Settings — verify or apply fallback** — Launch the app; press ⌘, from a non-text, no-overlay context. If Settings opens exactly once → done. If the `.appSettings` mechanism does NOT bind ⌘, on this macOS (known version-sensitivity with no `Settings {}` scene), apply the spec's fallback **atomically in a single commit to avoid a double-fire window**: in the SAME edit, FIRST remove `.keyboardShortcut(",", modifiers: .command)` from the Settings button (leaving a `⌘,` text hint) and THEN add a single `if cmd && lower == ","` case in `handleKeyDown` setting `settings = true`. Never land the `handleKeyDown` case while the button accelerator is still present. Re-verify exactly-one-fire. (Reasoning aid: `handleKeyDown` returns `Bool`; the monitor wrapper at `AppModel.swift:2960` converts `true → nil` to consume the event, so a handled ⌘, never reaches the menu accelerator — but only the one mechanism should exist at a time.) Commit if the fallback is applied.
  - Run: manual — launch the test build, press ⌘,
  - Expected: in-app Settings surface opens exactly once
  - **Files:** `MMail/State/AppModel.swift` (only if fallback applied), `MMail/MMailApp.swift` (only if fallback applied)

- [ ] **T008 (SC: 001, 003, 005, 006): Live menu-bar exploration** — With the test build running, confirm: (1) menu bar shows Message, Go, and a SINGLE View menu containing the View-insertion items, plus Settings in the app menu and one Keyboard-Shortcuts item in Help (SC-001); (2) clicking a sampled item from each of Message/Go/View performs the same action as its key/palette counterpart (SC-003); (3) add a second account → its Switch-to item appears in Go without relaunch, then remove it → it disappears (SC-005); (4) no double-fire / regressions: `E` archives once, `⌘⇧D` toggles dark once, `⌘K` toggles palette once, `?` opens help once, and typing `e` in the compose body inserts a literal `e` (SC-006). Record results for the /verify manual gate.
  - Run: manual — exercise each behavior in the running app
  - Expected: all four groups pass as described; no duplicate menus, no double-fire
  - **Files:** none (verification only)

---

## Notes for the build engineer
- **Single source of truth:** never hand-author the menu item list — always go through `MenuModel.build(from: model.buildCommands())`. Adding a future command to `buildCommands()` should surface it in the menu automatically (modulo the group→menu routing).
- **No accelerators except ⌘,:** do not attach `.keyboardShortcut` to Message/Go/View items. `handleKeyDown` remains the sole owner of every existing key; the menu would otherwise risk double-firing.
- **`.sidebar` placement** is the reliable way to land items in the system View menu (one View menu, no duplicate). If it misbehaves, `.toolbar` is the alternative View-menu placement — but verify exactly one View menu either way.
- **xcodegen + pbxproj:** T001 and T002 each add a new `.swift` file → run `xcodegen generate` and commit the regenerated `project.pbxproj` with that task; later tasks edit existing files only (no regenerate needed).
- **Dynamic accounts (SC-005)** depends on SwiftUI re-evaluating `.commands` when `@Published accounts` changes — this is the flagged risk; it has no unit coverage and must be live-verified in T008.
