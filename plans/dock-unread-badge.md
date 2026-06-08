# dock-unread-badge Implementation Plan

**Goal:** Show the total unread-inbox count across accounts as the macOS Dock icon badge, kept in sync and cleared at zero.

**Architecture:** Two pure static seams on `AppModel` — `dockBadgeLabel(unread:) -> String` (the formatter) and `unreadInboxCount(_:[Email]) -> Int` (the counter). The Dock badge is driven by the MODEL, not a view: a `didSet` on the `@Published emails` property recomputes the count and sets `NSApp.dockTile.badgeLabel` (on the main thread), plus a one-time set at the end of `init()`. This updates the badge even when the window is backgrounded/minimized (where a SwiftUI view `.onChange` would not fire) — essential because new mail arrives on the 15s background poll. `AppModel.swift` already `import AppKit` (line 2), so `NSApp` is available.

**Test Methodology:** e2e-first (from `.harness.yaml`). The two pure seams are unit-tested via swift-testing (SC-003, SC-004). The live Dock display + sync (SC-001, SC-002 display portion) is manual-exploration — there is no Dock in CI. SC-005 = build + `xcodebuild test` green with non-zero executed count.

**Build execution note:** The FULL build is performed by a single Opus subagent following these tasks in order, then an opposite-model review loop. Everything — pure functions, computed property, and the badge wiring (`didSet` + `refreshDockBadge`) — lives INSIDE the existing `MMail/State/AppModel.swift`; no `MMailApp.swift` change is needed. The ONLY new file is the test file in T002 → run `xcodegen generate` once and commit the regenerated `MMail.xcodeproj/project.pbxproj`.

**Constraints (from the APPROVED spec — do not violate):**
- Badge total MUST equal `sum(unreadByAccount.values)` (mirror `AccountRailView.swift:7`); count is `unread == true && folder == "inbox"`. `emails` only ever holds real-account mail (verified — starts `[]`, never seeded), so NO `isRealAccount` filter is needed.
- Zero/negative → empty string `""` (clears badge), never `"0"`.
- `AppModel` is NOT `@MainActor` (`AppModel.swift:87`) and `emails` is mutated from background IMAP callbacks, so the `didSet` can fire OFF the main thread. The `NSApp.dockTile.badgeLabel` assignment MUST therefore be wrapped in `DispatchQueue.main.async` (AppKit is main-only). This is mandatory here, not optional.
- The badge MUST be model-driven (observe `emails`), NOT a view `.onChange` — a backgrounded window's SwiftUI body may not re-render, so a view observer would miss background-poll updates.

---

## Tasks

- [ ] **T001 (SC: 003,004): Define pure seams + stubs** — In `MMail/State/AppModel.swift` add: `static func dockBadgeLabel(unread: Int) -> String` (stub `return ""`); `static func unreadInboxCount(_ emails: [Email]) -> Int` (stub `return 0`); and `var unreadInboxTotal: Int { Self.unreadInboxCount(emails) }`. Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` Expected: PASS (compiles).
  - **Files:** `MMail/State/AppModel.swift`

- [ ] **T002 (SC: 003,004): Failing unit tests** — Add `MMailTests/DockBadgeTests.swift` (swift-testing: `import Testing`, `@testable import MMail`). Cover the formatter: `dockBadgeLabel(unread: 5)`→`"5"`, `1`→`"1"`, `0`→`""`, `-1`→`""`, `1234`→`"1234"`. Cover the counter with constructed `Email` values. The `Email.init` (`Models.swift:77`) REQUIRES these 9 params (no defaults): `id, account, from, subject, preview, body, time, day, folder`; `unread` and `folder` are what we vary. Minimum skeleton:
  ```swift
  Email(id: "1", account: "a", from: "f", subject: "s",
        preview: "", body: "", time: "", day: "today",
        unread: true, folder: "inbox")
  ```
  Cases: 3 unread inbox on account A + 2 unread inbox on B → `5`; a list of 2 unread inbox + 1 read inbox + 4 unread `"archive"` → `2`; empty list → `0`. NOTE: the empty-list→`0` case will PASS against the `0` stub (expected); the non-zero cases are the true RED signal. Then `xcodegen generate` (new test file) and stage `MMail.xcodeproj/project.pbxproj`. Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug test CODE_SIGNING_ALLOWED=NO` Expected: FAIL (formatter non-zero cases + counter non-zero cases fail against stubs), non-zero executed-test count.
  - **Files:** `MMailTests/DockBadgeTests.swift`, `MMail.xcodeproj/project.pbxproj` (regenerated)

- [ ] **T003 (SC: 003,004): Implement pure seams + commit** — `dockBadgeLabel`: `return unread > 0 ? String(unread) : ""`. `unreadInboxCount`: `emails.filter { $0.unread && $0.folder == "inbox" }.count`. Run: same `xcodebuild ... test` Expected: PASS, non-zero executed count. Commit: `feat: dock badge formatter + unread-inbox count + unit tests`.
  - **Files:** `MMail/State/AppModel.swift`

- [ ] **T004 (SC: 001,002): Drive the Dock badge from the model** — In `MMail/State/AppModel.swift`: (1) add a `private func refreshDockBadge()` that computes `let n = Self.unreadInboxCount(emails)` and sets the badge on the main thread: `DispatchQueue.main.async { NSApp.dockTile.badgeLabel = AppModel.dockBadgeLabel(unread: n) }`. (2) Attach a `didSet` to the existing `@Published var emails` declaration (`AppModel.swift:108`): `@Published var emails: [Email] = [] { didSet { refreshDockBadge() } }`. (3) Call `refreshDockBadge()` once at the end of `init()` (`~:272`, after `purgeSeedData()`) so the badge is correct on launch (empty → cleared). `import AppKit` is already present (line 2). Do NOT use a view `.onChange` (backgrounded windows won't fire). Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` Expected: PASS. Commit: `feat: drive Dock unread badge from the model`.
  - **Files:** `MMail/State/AppModel.swift`

- [ ] **T005 (SC: 005): Full verification + manual-exploration** — Run build + test; confirm green with a NON-ZERO executed-test count (not just exit 0). Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO && xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -40` Expected: BUILD SUCCEEDED, TEST SUCCEEDED, non-zero test count. Then record the manual-exploration checklist for the next human run (no Dock in CI): (a) launch with unread inbox mail → Dock shows the count and it matches the account-rail total; (b) read the last unread → badge clears; (c) new mail on background sync → badge increments; (d) archive/delete an unread inbox message → badge decrements; (e) launch with no account (onboarding) → no badge. Document results in the handoff.
  - **Files:** none (verification only)

---

## Notes for the build subagent
- DRY/YAGNI: just the two pure functions + one computed property + the `didSet`/`refreshDockBadge` wiring. No view `.onChange`, no new types, no per-account badges, no `"99+"` cap.
- Do NOT switch `testing.method`; do NOT add `xcodegen generate &&` to the verify command. Run `xcodegen generate` manually ONLY in T002 (new test file), then commit the regenerated `project.pbxproj`.
- Confirm a non-zero executed-test count, not just exit 0 (swift-testing reports "Test run with N tests … passed").
- Do NOT push; do NOT touch `main`. Parent session pushes the branch after an independent review + verify.
