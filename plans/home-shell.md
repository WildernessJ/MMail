# home-shell Implementation Plan

**Goal:** Turn the Home area into a calm dashboard of individually toggleable widgets plus a new read-only Inbox-glance widget, with a visual reskin — no behavior change for existing widgets, all data preserved.

**Architecture:** Two pure, unit-testable seams in a new `MMail/Models/HomeShell.swift` — (a) `HomeWidgetVisibility` (six Bools with absent-key-defaults-ON `UserDefaults` load/persist) and (b) `InboxGlance.project(emails:account:now:)` → `(unread, newToday, peek)`. `AppModel` holds `@Published homeWidgets` + a computed glance + an `openHomeMessage(_:)` helper (`setFolder` then `activate`). `SettingsView` gains a "Home" section of `MMToggle`s. `HomeView` conditionally renders each widget (reflow, no reserved frames; calm empty state) and adds the Inbox-glance view.

**Test Methodology:** e2e-first — adapted for SwiftUI. The automated gate is **swift-testing unit tests on the two pure seams** (the type-driven layer). SwiftUI view behaviors (reskin, reflow, click-to-open, toggle wiring) are covered by **manual-exploration** (always-on), since this project has no headless SwiftUI E2E runner. **Unit tests run from the MAIN checkout** (worktree XCTest hang — `.harness.yaml` / project_worktree-xctest-hang). Type-check is the plain `xcodebuild build CODE_SIGNING_ALLOWED=NO`. New `.swift` files require `xcodegen generate` + committing the regenerated `project.pbxproj` (per CLAUDE.md).

---

## Phase A — Pure seams (type-driven, automated gate)

- [ ] **T001 (SC: 008): Scaffold seam file + test file + project** — Create `MMail/Models/HomeShell.swift` with type stubs only: `enum HomeWidget: CaseIterable { case date, weather, inboxGlance, people, journal, todo }`; `struct HomeWidgetVisibility { var date/weather/inboxGlance/people/journal/todo: Bool }` with `static func load(_:UserDefaults) -> HomeWidgetVisibility` and `func persist(_:UserDefaults)` returning/doing nothing yet (e.g. `fatalError`-free stubs that compile); `struct InboxGlanceResult { let unread: Int; let newToday: Int; let peek: [Email] }` and `enum InboxGlance { static func project(emails: [Email], account: String, now: Date) -> InboxGlanceResult }` stub returning zero-value results (`.init(unread: 0, newToday: 0, peek: [])`) — no `fatalError`. Create empty `MMailTests/HomeShellTests.swift` (`import Testing` + `@testable import MMail`). Then `xcodegen generate` and commit the regenerated project.
  - **Run:** `xcodegen generate && xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - **Expected:** `** BUILD SUCCEEDED **`; `git status` shows `project.pbxproj` regenerated (commit it).
  - **Files:** `MMail/Models/HomeShell.swift` (new), `MMailTests/HomeShellTests.swift` (new), `MMail.xcodeproj/project.pbxproj` (regenerated)

- [ ] **T002 (SC: 001, 003, 006): Failing tests — HomeWidgetVisibility** — Write swift-testing tests: (1) `load` on a fresh empty `UserDefaults(suiteName:)` returns all-true (absent-key-defaults-ON); (2) round-trip — persist a mixed set, re-load, equal; (3) one key absent + others present → the absent one is true, others as stored; (4) explicitly assert the loader does NOT treat absent-as-false.
  - **Run (MAIN checkout):** `xcodebuild test -project MMail.xcodeproj -scheme MMail -only-testing:MMailTests/HomeShellTests`
  - **Expected:** FAIL (stub returns wrong values) — clear assertion failures, not a compile error.
  - **Files:** `MMailTests/HomeShellTests.swift`

- [ ] **T003 (SC: 001, 003, 006): Implement HomeWidgetVisibility + commit** — `load` reads each key `mmail.home.show.{date,weather,inboxGlance,people,journal,todo}` via `d.object(forKey:) as? Bool ?? true` (NEVER `d.bool(forKey:)`); `persist` writes all six with `d.set(_:forKey:)`. Add a `subscript(HomeWidget) -> Bool` get/set for ergonomic binding.
  - **Run (MAIN checkout):** same as T002
  - **Expected:** `** TEST SUCCEEDED **` for HomeShellTests. Commit.
  - **Files:** `MMail/Models/HomeShell.swift`

- [ ] **T004 (SC: 004, 005): Failing tests — InboxGlance.project** — Tests over hand-built `[Email]`, passing a fixed `now`: (1) unread count = unread inbox messages for the account; (2) `newToday` counts only unread inbox whose `sortDate` is the same calendar day as `now` (`Calendar.current.isDate(sortDate, inSameDayAs: now)`); (3) nil-`sortDate` message is counted in `unread` but NOT `newToday`; (4) `peek` = unread inbox sorted by `AppModel.isNewerFirst` then `.prefix(5)` — give 8 unread, assert exactly the 5 newest in order; (5) `account == "all"` aggregates across accounts, a single account filters; (6) inbox-zero → `(0,0,[])`; (7) `folder != "inbox"` and read messages are excluded.
  - **Run (MAIN checkout):** `xcodebuild test -project MMail.xcodeproj -scheme MMail -only-testing:MMailTests/HomeShellTests`
  - **Expected:** FAIL (stub returns zeros).
  - **Files:** `MMailTests/HomeShellTests.swift`
  - **Note:** the seam takes `now` so it is **pure and deterministic** — build `sortDate`s relative to the test's `now` (e.g. `now`, `now.addingTimeInterval(-86400*3)`). `isDate(_:inSameDayAs: now)` with `now == Date()` is exactly equivalent to the spec's `isDateInToday`, but uses the injected `now` instead of the device clock so tests are stable.

- [ ] **T005 (SC: 004, 005): Implement InboxGlance.project + commit** — Filter `emails` to `folder == "inbox"` and (account=="all" ? all : `email.account == account`) and `unread`; `unread` = count; `newToday` = count where `sortDate.map { Calendar.current.isDate($0, inSameDayAs: now) } == true`; `peek` = sorted by `AppModel.isNewerFirst` then `prefix(5)` as `Array`.
  - **Run (MAIN checkout):** same as T004
  - **Expected:** `** TEST SUCCEEDED **`. Commit.
  - **Files:** `MMail/Models/HomeShell.swift`

## Phase B — AppModel wiring

- [ ] **T006 (SC: 001, 003): homeWidgets state + cached glance + commit** — Add `@Published var homeWidgets: HomeWidgetVisibility`, initialized in `AppModel.init` via `HomeWidgetVisibility.load(.standard)` (place beside `railSize = loadRailSize(d)`). Add the setter with a **full-struct reassign** so the `@Published` change publishes unambiguously and persists: `func setHomeWidget(_ w: HomeWidget, on: Bool) { var v = homeWidgets; v[w] = on; homeWidgets = v; v.persist(.standard) }`.
  - **Cache the glance, don't compute-on-read** (perf: a bare computed property re-scans `emails` on every unrelated `objectWillChange`). Add `@Published var homeGlance: InboxGlanceResult = .init(unread: 0, newToday: 0, peek: [])` and a private `refreshHomeGlance()`. **Thread safety is mandatory**: `AppModel` is NOT `@MainActor` and `emails.didSet` fires on background IMAP callback threads (see `AppModel.swift:568`), so the `@Published` write MUST hop to main — mirror `refreshDockBadge` (`AppModel.swift:570-574`):
    ```swift
    func refreshHomeGlance() {
        let g = InboxGlance.project(emails: emails, account: currentAccount, now: Date())
        DispatchQueue.main.async { self.homeGlance = g }
    }
    ```
    Call `refreshHomeGlance()` from the **existing `emails` didSet** (the one that drives the dock badge), from a `currentAccount` didSet (add one if absent), and once at end of `init`. The main-hop covers all three call sites uniformly (the `currentAccount`/`init` paths are already main-thread; the `emails` path is the one that genuinely needs it). This mirrors the model-driven dock-badge pattern (`dockBadgeLabel`/`unreadInboxCount`).
  - **Run:** `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - **Expected:** `** BUILD SUCCEEDED **`. Commit.
  - **Files:** `MMail/State/AppModel.swift`

- [ ] **T007 (SC: 005): openHomeMessage helper + commit** — Add, with a **single-pass** lookup: `func openHomeMessage(_ id: String) { guard let email = emails.first(where: { $0.id == id }) else { return }; setFolder(email.folder); activate(id) }`. Order: `setFolder` BEFORE `activate` (clearSelection only clears bulk `selectedIds`, not scalar `selectedId`). The `guard` makes a click on an expunged/missing message a safe no-op.
  - **Run:** type-check build (as T006)
  - **Expected:** `** BUILD SUCCEEDED **`. Commit.
  - **Files:** `MMail/State/AppModel.swift`

## Phase C — SwiftUI: Settings toggles, HomeView reflow, Inbox-glance, reskin (manual-exploration)

- [ ] **T008 (SC: 001): Settings → Home section** — Add a "Home" group/section in `SettingsView` containing six `MMToggle` rows (Date, Weather, Inbox glance, People, Journal, To-do), each bound via `Binding(get: { model.homeWidgets[w] }, set: { model.setHomeWidget(w, on: $0) })`. Match the existing section styling (see the Appearance `Picker` block).
  - **Run:** type-check build
  - **Expected:** `** BUILD SUCCEEDED **`; manual: Settings shows the new Home section with six working toggles.
  - **Files:** `MMail/Views/SettingsView.swift`

- [ ] **T009 (SC: 002, 007): HomeView reflow + empty state** — Gate each existing widget (`dateCard`, `weatherCard`, `peopleCard`, `journalCard`, `todoCard`) on `model.homeWidgets[.x]`. **Reflow strategy:** the current `HomeView` uses a fixed 3-column `LazyVGrid` (Date/Weather/People) + a manual `HStack` bottom row — a fixed 3-col grid leaves empty columns / odd widths when items are hidden. Restructure into a **vertical stack of conditionally-included sections** so reflow is automatic (a hidden widget's `if` simply contributes nothing — no reserved frame). Where a row still groups multiple widgets side-by-side, build that row's children array from the enabled widgets and size columns to the enabled count, OR drop to a single column. When ALL widgets are off, render a calm empty state ("Your Home is empty — enable widgets in Settings → Home"). Keep the greeting header always.
  - **SC-003 guard (architecture, no automated test):** visibility is presentation-only — a widget's `if` gates ONLY whether its view renders, NEVER a data write. Do NOT gate `persistJournal`/`addTodo`/`setWeatherCity`/etc. on visibility. (SC-003 is enforced by this architectural rule + the manual disable→enable check in T013; there is no unit test because there is no write path to test.)
  - **Run:** type-check build
  - **Expected:** `** BUILD SUCCEEDED **`; manual: disabling each widget (and combinations) leaves no blank gap; all-off shows the empty state, no crash.
  - **Files:** `MMail/Views/HomeView.swift`

- [ ] **T010 (SC: 004, 005): Inbox-glance widget view** — Add an `inboxGlanceCard` (gated on `.inboxGlance`) rendering `model.homeGlance`: a summary line ("<unread> unread · <newToday> new today"), then up to 5 peek rows (sender, subject, short time) each a `.plain` Button calling `model.openHomeMessage(row.id)`. Inbox-zero → a calm "All caught up" state, no rows. Place it as the focal widget per the approved layout.
  - **Run:** type-check build
  - **Expected:** `** BUILD SUCCEEDED **`; manual: counts match the inbox; clicking a row navigates to inbox and opens that message in the reader.
  - **Files:** `MMail/Views/HomeView.swift`

- [ ] **T011 (SC: 002): Visual reskin pass** — Produce a cohesive first-pass layout matching the approved brainstorming mockup: greeting header at top; **Inbox glance as the focal widget** (most visual weight); Date + Weather retained as cards; People as a compact strip; Journal + To-do as the lower row. Concrete constraints (reuse, don't reinvent): keep the existing `card`/`cardHead` builders and palette tokens (`p.bg1` surface, `p.border` 1px stroke, 14pt continuous corner radius, the existing 18/16 padding); keep `maxWidth: 1100` + 40pt horizontal padding; use `Theme` palette tokens for ALL colors (no hardcoded hex except the existing `WeatherGlyph`) so light + dark both work. Preserve every existing widget action (People compose / View all → `peopleOpen`; Journal autosave + archive → `journalArchiveOpen`; To-do add/toggle/remove; Weather city setter + not-found alert).
  - **Note:** this is a first pass — the user tunes spacing/sizing **live** at T013 (precedent: resizable-columns tile sizes were tuned live). Aim for sensible defaults, not pixel-finality.
  - **Run:** type-check build
  - **Expected:** `** BUILD SUCCEEDED **`; manual: Home looks cohesive in both light + dark; all existing widget actions still work.
  - **Files:** `MMail/Views/HomeView.swift`

## Phase D — Full verification

- [ ] **T012 (SC: 001–008): Full suite + type-check green** — Run the entire test suite from the MAIN checkout and the type-check build; ensure no regression in the existing suites.
  - **Run (MAIN checkout):** `xcodebuild test -project MMail.xcodeproj -scheme MMail` then `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
  - **Expected:** `** TEST SUCCEEDED **` (HomeShellTests + all prior suites green) and `** BUILD SUCCEEDED **`.
  - **Files:** —

- [ ] **T013 (SC: 001–008): Manual-exploration verify (the verify-gate live pass)** — Build into the Dock app's DerivedData, ⌘Q + relaunch, and walk every SC: per-widget toggle + relaunch persistence (SC-001); reflow no-gaps + all-off empty state (SC-002/007); disable→enable preserves todos/journal/weather-city (SC-003); glance counts match the real inbox incl. new-today + nil-sortDate (SC-004); ≤5 newest peek + click opens in reader, no triage (SC-005); fresh-keys all-on parity (SC-006); existing widget actions intact (reskin). This is the `/verify` manual gate; the plan lists it for completeness.
  - **Run:** launch the rebuilt `MMail.app`
  - **Expected:** every SC check passes against the live mailbox.org (+ Gmail) accounts.
  - **Files:** `.verified/home-shell` (marker, written at verify)
