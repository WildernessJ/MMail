# body-truncation Implementation Plan

**Goal:** Opening a message always loads its complete body, so long emails (>64 KB raw) no longer render truncated.

**Architecture:** Make body completeness explicit on `Email` via an additively-decodable optional flag. Two pure functions decide (a) whether a fetch result is complete (uncapped ⇒ always; capped ⇒ returned-bytes < cap) and (b) whether opening a message must trigger a full fetch (absent or incomplete body). Wire those into the four touchpoints: the 64 KB preview prefetch (sets complete only when the message fit), the open path in `loadBodyIfNeeded` (now an **uncapped** fetch that marks complete + copies the flag to the search-results mirror), and `mergeRealFolder` (carries the flag across a folder refresh). The prefetch pool filter and `BODY.PEEK` warming are unchanged.

**Test Methodology:** e2e-first — for this macOS SwiftUI app, "E2E" is the XCTest suite run via `xcodebuild test` plus a manual-exploration pass in the real app (the true end-to-end gate; the IMAP fetch can't be exercised headlessly). Pure-logic behaviors get failing XCTests first, then implementation drives them green.

**Conventions for the cues below:**
- BUILD = `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- TEST  = `xcodebuild test -project MMail.xcodeproj -scheme MMail -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- New `.swift` files require `xcodegen generate` before they compile, then commit the regenerated `MMail.xcodeproj/project.pbxproj` (per CLAUDE.md). Anchors like `AppModel.swift:2520` are from the pre-change tree; re-grep before editing.

**Out of scope (verified, intentionally not touched):** `openAttachment` (`AppModel.swift:2625`) already does an uncapped `fetchMessageData(byteLimit: nil)` to extract an attachment but discards the parsed body without setting `bodyLoaded`/`bodyComplete`. It is only reachable from the reader's attachment section, which means the message body was already opened (and thus made complete) first — so it cannot leave a message stuck incomplete, and opportunistically populating the body from it would be scope creep beyond this bug. Left as-is.

**All `bodyLoaded = true` sites (swept):** `2472` prefetch (T005), `2555` open success (T006), `2564` search mirror (T006), `2311` merge carry-over (T007), `1330` locally-recorded sent mail (T008). Every site that asserts a loaded body now also sets completeness.

---

## Phase A — Pure completeness core (types + failing tests + green)

- [ ] **T001 (SC: 004): Add explicit completeness state to `Email`** — Add `var bodyComplete: Bool?` to the `Email` struct (optional so it is additively decodable: a cache written before this feature has no key → decodes as `nil` → treated as not-complete, NOT a decode failure that discards the folder). Add a computed convenience `var hasCompleteBody: Bool { bodyLoaded && (bodyComplete ?? false) }`.
  - **Files:** `MMail/Models/Models.swift` (Email struct, ~47-91)
  - Run: BUILD — Expected: PASS (compiles; existing call sites unaffected since the field has a default-nil optional).

- [ ] **T002 (SC: 004, 002): Create the pure decision core (stubbed)** — New file `MMail/Mail/BodyCompleteness.swift` with an enum `BodyFetch` exposing two pure static functions, bodies stubbed to a placeholder that the tests will reject:
  - `static func isComplete(returnedBytes: Int, byteLimit: Int?) -> Bool` — uncapped (`byteLimit == nil`) ⇒ `true`; capped ⇒ `returnedBytes < byteLimit!`.
  - `static func needsFullFetch(bodyLoaded: Bool, bodyComplete: Bool?) -> Bool` — `true` when `!bodyLoaded || !(bodyComplete ?? false)`.
  - Stub both bodies to `return false` (a deliberately wrong placeholder the T003 tests will reject for the true-expecting cases).
  - Then `xcodegen generate` to add the file to the project; stage `project.pbxproj`.
  - **Files:** `MMail/Mail/BodyCompleteness.swift` (new), `MMail.xcodeproj/project.pbxproj` (regenerated)
  - Run: BUILD — Expected: PASS (stubs compile).

- [ ] **T003 (SC: 004, 002): Failing unit tests for the core** — New `MMailTests/BodyCompletenessTests.swift` covering:
  - `isComplete`: under-cap (`returnedBytes < cap` ⇒ true, message fit), at-cap (`returnedBytes == cap` ⇒ false — possibly-truncated; the exact-boundary message of size == cap is a benign false-incomplete costing one harmless extra fetch), uncapped (`byteLimit == nil` ⇒ true regardless of size).
  - `needsFullFetch`: absent (`bodyLoaded:false` ⇒ true), incomplete (`bodyLoaded:true, bodyComplete:false` ⇒ true), unknown legacy (`bodyLoaded:true, bodyComplete:nil` ⇒ true), complete (`bodyLoaded:true, bodyComplete:true` ⇒ false).
  - `xcodegen generate` to add the test file; stage `project.pbxproj`.
  - **Files:** `MMailTests/BodyCompletenessTests.swift` (new), `MMail.xcodeproj/project.pbxproj` (regenerated)
  - Run: TEST — Expected: FAIL on the new `BodyCompletenessTests` (stubs return placeholder), existing tests still pass.

- [ ] **T004 (SC: 004, 002): Implement the core + commit** — Replace the stubs with the real one-line bodies. Commit (`feat: explicit body-completeness core + tests`) including the regenerated `project.pbxproj`.
  - **Files:** `MMail/Mail/BodyCompleteness.swift`
  - Run: TEST — Expected: PASS (all `BodyCompletenessTests` green; 144 prior tests still green).

## Phase B — Wire the core into fetch/merge paths

- [ ] **T005 (SC: 004): Prefetch records completeness** — In `prefetchBodies`' parse loop (`for (uid, data) in datas`, ~2461), compute `let complete = BodyFetch.isComplete(returnedBytes: data.count, byteLimit: 65_536)` (`data` is the raw reassembled IMAP bytes — the correct comparand, confirmed against `IMAPService.swift:452-453`). Extend the `parsedByUID` dictionary value type from the current 5-tuple `(text:, html:, atts:, unsub:, cal:)` to a 6-tuple adding `complete: Bool`. In the assignment loop (~2467-2477) set `self.emails[i].bodyComplete = p.complete` alongside the existing `bodyLoaded = true`. Do NOT change the 64 KB cap, the pool filter (`2437`), or `BODY.PEEK`.
  - **Files:** `MMail/State/AppModel.swift` (`parsedByUID` decl ~2460; parse loop ~2461-2464; assignment block ~2467-2477)
  - Run: BUILD — Expected: PASS.

- [ ] **T006 (SC: 001, 002): Open path = uncapped fetch that marks complete** — In `loadBodyIfNeeded`: (a) change the early-return guard term from `!e.bodyLoaded` to `BodyFetch.needsFullFetch(bodyLoaded: e.bodyLoaded, bodyComplete: e.bodyComplete)` — **no leading `!`**: a `guard` proceeds only when every term is true, and we want to proceed (fetch) precisely when a full fetch IS needed (body absent OR incomplete), so the bare predicate is correct; `needsFullFetch == false` (loaded AND complete) makes the guard bail, which is the desired fast path. (b) change the open fetch `byteLimit` from `262_144` to `nil` (uncapped — whole message); (c) on success set `self.emails[i].bodyComplete = true`; (d) set `bodyComplete = true` on the `serverSearchResults` mirror copy too. Leave the `bodyLoadInFlight` / `bodyLoadFailed` dedupe and the 35s timer untouched.
  - **Files:** `MMail/State/AppModel.swift` (`loadBodyIfNeeded` ~2519-2569; fetch call ~2545; success block ~2552-2566)
  - Run: BUILD — Expected: PASS.

- [ ] **T007 (SC: 005): Merge preserves completeness across refresh** — In `mergeRealFolder`, where an already-loaded body is carried over, add `merged[i].bodyComplete = old.bodyComplete` so a complete body is not downgraded (and re-fetched) after a background refresh.
  - **Files:** `MMail/State/AppModel.swift` (`mergeRealFolder` carry-over block ~2308-2317)
  - Run: BUILD — Expected: PASS.

- [ ] **T008 (SC: 005): Locally-recorded sent mail is complete** — In `recordSentLocally` (`AppModel.swift:1323-1335`), the constructed `Email` has `bodyLoaded: true` with the full composed body inline. Set `bodyComplete = true` on it (it has no `uid`, so no refetch fires today, but this keeps the invariant "loaded ⇒ completeness known" uniform and prevents a needless refetch if a uid is later attached). Set it via the constructor or a follow-up assignment, consistent with the surrounding `e.` mutations.
  - **Files:** `MMail/State/AppModel.swift` (`recordSentLocally` ~1325-1335)
  - Run: BUILD — Expected: PASS.

- [ ] **T009 (SC: 003, 005): Regression test pass + commit** — Run the full suite; confirm no regressions. Commit (`fix: load complete body on open; preserve completeness across prefetch/merge/search/sent`).
  - **Files:** (none new)
  - Run: TEST — Expected: PASS (all tests green, including Phase A).

## Phase C — Manual exploration (true e2e gate)

- [ ] **T010 (SC: 001): Live-verify the truncated email renders fully** — Build into the DerivedData path the pinned Dock `MMail.app` uses, `⌘Q` the running app, relaunch. Open **"Trade the SpaceX pre-IPO perp"** in the inbox. Confirm: the reader now shows the "Web3 protocols are accessible through the Blockchain.com DeFi Wallet…" disclaimer footer that was previously cut off, and the pane scrolls to the true end of the message. Spot-check a normal short email still opens instantly (no visible refetch / regression).
  - **Files:** (none — runtime verification)
  - Run: open the app, open the SpaceX email — Expected: full body incl. the Web3 disclaimer footer is visible and scrollable; short emails unaffected.
  - Note: this email's cached body is already truncated on disk; opening it triggers the new uncapped refetch (its `bodyComplete` is nil/absent ⇒ `needsFullFetch` true), which is exactly the path under test.

---

**Stop after Phase C is green** (build approved by the looped Sonnet review + SC-001 live-confirmed), per the user directive to pause once the build is approved.
