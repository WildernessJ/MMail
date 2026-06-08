# reader-list-display-fixes Implementation Plan

**Goal:** Fix three reader/list display defects — show the delivered-to recipient (not the account address), let the reader body use the full pane width, and order messages newest-first within each day group — without touching fetch, filter, storage, or the `Email`/cache schema.

**Architecture:** Two pure helpers are added as `static func`s on `AppModel` (the codebase's established testable-seam pattern, matching `makeEmail`/`dayAndTime`/`dockBadgeLabel`): `recipientLine(for:account:)` and `isNewerFirst(_:_:)`. `ReaderView.toLine` is reduced to a call to the first; the production list reads through a single `.sorted(by: AppModel.isNewerFirst)` applied to the **non-search** branches of `AppModel.visibleEmails` (NOT in `EmailListView.groupByDay`), so the rendered order, `selectedEmail` fallback, `navigate()`, and triage all agree. The reader width fix is a one-line frame change. Both helpers live in the existing `AppModel.swift` (no new production file → no xcodegen for production code); the one new **test** file requires `xcodegen generate` + a committed project regen.

**Test Methodology:** e2e-first (from `.harness.yaml`). For this macOS SwiftUI app the behavioral coverage is: unit tests in `MMailTests` over the two extracted pure functions (they encode the spec scenarios), plus `manual-exploration` for the view-layout/selection behaviors that cannot be unit-tested. Always-on per `.harness.yaml`: type-driven, manual-exploration, review.

**Commands (Swift, not the skill's Python templates):**
- Build / type-check: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- Tests: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- New `.swift` file added → first run `xcodegen generate`, then commit the regenerated `MMail.xcodeproj/project.pbxproj` (per CLAUDE.md).

---

## Fix 1 — Reader shows the delivered-to recipient (Req: "Reader shows the delivered-to recipient")

- [ ] **T001 (SC: 001): Types — add `recipientLine` seam (stub = current behavior)** — Add `static func recipientLine(for email: Email, account: Account?) -> String` to `AppModel`, body initially returning the CURRENT behavior (`"to \(account?.email ?? "me")"` for non-sent folders, existing `email.to` branch for sent/drafts/outbox) so the project compiles and the next task goes red on the alias case. Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` Expected: BUILD SUCCEEDED.
  **Files:** `MMail/State/AppModel.swift`

- [ ] **T002 (SC: 001): Failing unit tests for recipient selection** — Create `MMailTests/DisplayFormattingTests.swift` (`@testable import MMail`) covering the three Req1 scenarios: (a) received mail with `email.to = ["hiltl@sl.holdy.org"]` and account `j_holdy@mailbox.org` → line contains the alias, not the account; (b) received mail with empty/nil `email.to` → falls back to account address, and `me` when account is nil; (c) `sent`-folder message with recipients → unchanged. Run `xcodegen generate` (registers the new test file) and stage the regenerated project. Run: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` Expected: FAIL on scenario (a) — the meaningful red. (Scenarios (b) and (c) may already be GREEN against the stub, since the stub keeps the current account-fallback and sent-folder behavior; that's fine — (a) is the one that proves the fix.)
  **Files:** `MMailTests/DisplayFormattingTests.swift`, `MMail.xcodeproj/project.pbxproj`

- [ ] **T003 (SC: 001): Implement `recipientLine` + commit** — Replace the stub with the real rule: take non-empty `email.to` first → `"to " + recips.prefix(3).joined(separator: ", ")`; if empty, `sent`/`drafts`/`outbox` → `"to (no recipient)"`, otherwise (received) → `"to \(account?.email ?? "me")"`. Run: `xcodebuild test ...` Expected: PASS (all three recipient scenarios green; existing 52 tests still green). Commit.
  **Files:** `MMail/State/AppModel.swift`

- [ ] **T004 (SC: 001): Wire production `toLine` to the seam + commit** — Reduce `ReaderView.toLine` (`MMail/Views/ReaderView.swift:646`) to `return AppModel.recipientLine(for: email, account: account)`; delete the old inline branching so the tested code IS the production path (no parallel copy). Leave the sole callsite (`ReaderView.swift:402`) untouched. Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` Expected: BUILD SUCCEEDED. Commit. (Live alias check happens in T010.)
  **Files:** `MMail/Views/ReaderView.swift`

## Fix 2 — Newest-first within each day group (Req: "Messages are ordered newest-first within each day group")

- [ ] **T005 (SC: 003): Types — add `isNewerFirst` comparator seam (stub)** — Add `static func isNewerFirst(_ a: Email, _ b: Email) -> Bool` to `AppModel`, stubbed to return `false` (no ordering) so it compiles and the next task goes red. Run: `xcodebuild ... build ...` Expected: BUILD SUCCEEDED.
  **Files:** `MMail/State/AppModel.swift`

- [ ] **T006 (SC: 003): Failing unit tests for the comparator** — Add to `MMailTests/DisplayFormattingTests.swift` (same file — no second xcodegen): (a) higher `uid` sorts before lower (`isNewerFirst` true); (b) equal `uid` → deterministic tiebreak by `id`; (c) `nil` vs `nil` `uid` → tiebreak by `id`, stable; (d) `sortedNewestFirst` of a mixed list drops/duplicates nothing (count preserved, set preserved). Run: `xcodebuild test ...` Expected: FAIL (stub returns false).
  **Files:** `MMailTests/DisplayFormattingTests.swift`

- [ ] **T007 (SC: 003): Implement comparator + apply at the single AppModel seam + commit** — Implement `isNewerFirst`: compare `(a.uid ?? 0)` vs `(b.uid ?? 0)` descending; on equality break ties by `a.id < b.id` (total, render-stable order). Then restructure `AppModel.visibleEmails` (`MMail/State/AppModel.swift:306`). NOTE: it currently has THREE independent non-search `return`s — `labelFilter` (~318), `folder == "snoozed"` (~320), and the default folder filter (~321) — plus the `searchIsActive` early-return (~307). Do NOT just append `.sorted` to the last one (that silently leaves the label and snoozed views unsorted). Instead restructure so the three non-search branches assign into a single local (e.g. `let base: [Email] = …`) that is sorted exactly once with `.sorted(by: AppModel.isNewerFirst)` before return; leave the `searchIsActive` early-return UNSORTED (search exemption). Do NOT sort in `EmailListView.groupByDay`. Run: `xcodebuild test ...` Expected: PASS (comparator tests + existing suite green). Commit.
  **Files:** `MMail/State/AppModel.swift`

## Fix 3 — Reader uses the full pane width (Req: "Reader content uses the available pane width")

- [ ] **T008 (SC: 002): Raise the reader content width cap + commit** — In `MMail/Views/ReaderView.swift:71`, change the inner `.frame(maxWidth: 820, alignment: .leading)` to use the available width (`.frame(maxWidth: .infinity, alignment: .leading)` or remove the cap). Keep the outer `.frame(maxWidth: .infinity, alignment: .leading)` at line 73 unchanged. Run: `xcodebuild ... build ...` Expected: BUILD SUCCEEDED. Commit. (Verification is visual — see T010; this change is view-layout only and is covered by manual-exploration, not a unit test.)
  **Files:** `MMail/Views/ReaderView.swift`

## Selection consistency + final verification

- [ ] **T009 (SC: 005): Confirm selection/nav follow the sorted seam** — Because the sort is applied inside `visibleEmails`/`filteredEmails`, the `selectedEmail` fallback (`AppModel.swift:346`), `navigate()` (`~521`), and triage-selection (`~534`, `~590`, and the `filteredEmails.first` sites `~502/731/777/1906/2233/2290`) already read the sorted sequence — expect NO code change. Read those sites to confirm none re-sort or read a different collection; only if one bypasses `filteredEmails` and could select a hidden message, fix it at the same seam. Run: `xcodebuild ... build ...` Expected: BUILD SUCCEEDED. (Behavioral check in T010.)
  **Files:** `MMail/State/AppModel.swift` (read-only unless a bypass is found)

- [ ] **T010 (SC: 001, 002, 003, 005): Full suite + live manual exploration** — Run the entire test suite, then build into the pinned-Dock `MMail.app` DerivedData path, `⌘Q` + relaunch, and live-verify against the mailbox.org account: (1) an aliased message's to-line shows the SimpleLogin alias, not `j_holdy@mailbox.org`; (2) the reader body fills the pane with no large right gutter; (3) within Today the newest message is at the top, descending to oldest; (4) opening the inbox selects the newest message, arrow-keys move in visible order, and archiving the selected message lands selection on an adjacent still-visible message. Run: `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` Expected: TEST SUCCEEDED (existing 52 + new tests), then all four manual checks pass. (The `.verified/` marker is written by `/verify`, not here.)
  **Files:** none (verification only)

---

**Notes for the builder**
- Only T002 adds a new `.swift` file (`DisplayFormattingTests.swift`); run `xcodegen generate` once there and commit the regenerated `project.pbxproj`. T006 reuses that same test file — no second regen. All production code lands in existing files (`AppModel.swift`, `ReaderView.swift`).
- Honor the spec's hard constraints: sort ONLY at the `AppModel` non-search seam (never in `groupByDay`); the production `toLine` must delegate to `recipientLine` (no untested duplicate); comparator must break `uid` ties by `id`; search results stay in server order; no `Email`/`MailCache` schema change.
