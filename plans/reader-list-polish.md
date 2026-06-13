# reader-list-polish Implementation Plan

**Goal:** Polish the reader/list display along three independent axes — flatten the reader to match the list's inset (Piece A / SC-001), add a Date·Sender·Subject sort control (Piece B / SC-002, SC-004), and capture + display all To/CC recipients (Piece C / SC-003).

**Architecture:** Three behaviorally-independent phases. Decision logic goes in pure, SwiftUI-free seams (`LayoutSizing.paneContentInset`, a new `EmailSort`, a new `RecipientDisplay`) mirroring the existing `orderNewerFirst`/`LayoutSizing`/`MoveStrategy` pure-seam pattern; SwiftUI views and the IMAP parser consume them. Cache additions are additive `Codable` (no wipe). The hardcoded sort and the single recipient line are replaced at their existing seams.

**Test Methodology:** e2e-first — adapted for this Swift/SwiftUI macOS app:
- **Per-task gate = the type-check build** in the worktree: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- **Pure-seam logic** gets `swift-testing` unit tests (`@Test`/`#expect`, mirroring `MoveStrategyTests`/`LayoutSizingTests`). **The test RUN is deferred to the verify phase from the MAIN checkout** (`xcodebuild ... test`) — the XCTest runner hangs from a git worktree (bundle-id/LaunchServices collision; documented). Tests are authored in-phase but executed at verify, NOT in the worktree.
- **UI/behavioral** correctness is confirmed by **manual exploration** at the verify phase (build into the pinned-Dock DerivedData, ⌘Q + relaunch).

**Conventions (per CLAUDE.md):**
- Build is dispatched to a **single Opus subagent**; reviews are **opposite-model Sonnet**, looped to APPROVED.
- Adding a new `.swift` file (app OR test target) requires `xcodegen generate` **before** the next build/test, then **commit the regenerated `MMail.xcodeproj/project.pbxproj`**. Re-run it after EACH new file — `EmailSort.swift` (T006), `EmailSortTests.swift` (T007), `RecipientDisplay.swift` (T013), `RecipientDisplayTests.swift` (T014) are four separate additions; skipping a regen silently drops the file from the project (a new test file would then "run" zero tests). Editing existing files needs no regen.
- **Pause at each Phase boundary** (A→B→C) and offer a handoff before continuing.

**Main-checkout caveat:** the main checkout is currently on `feat/home-shell` (dirty, mid-build), so the deferred test RUN needs the main checkout free of home-shell (or a throwaway checkout of this branch) at verify time. Flagged, not blocking — the per-task build gate stands on its own.

---

## Phase A — Flat reader padding (SC-001)

Drop the reader's floating card; route the list, reader content, and reader toolbar through one 20pt inset constant.

- [ ] **T001 (SC: 001): Add the shared inset constant** — Introduce a new namespace `enum LayoutSizing { static let paneContentInset: CGFloat = 20 }` (SwiftUI-free). NOTE: the layout-sizing file currently holds only free functions (`clampListWidth`, `loadListWidth`, …) + `enum RailSize` + `enum LayoutDefaultsKey` — there is NO `LayoutSizing` type yet, so CREATE it (don't extend a non-existent type). Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/State/LayoutSizing.swift`

- [ ] **T002 (SC: 001): Unit test pins the constant** — Add a `swift-testing` test asserting `LayoutSizing.paneContentInset == 20` (the single-source guard; structural drift prevention is enforced by every site referencing it in T003/T004). Run (DEFERRED to verify, from MAIN checkout): `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug test -only-testing:MMailTests/LayoutSizingTests CODE_SIGNING_ALLOWED=NO` Expected: `** TEST SUCCEEDED **`
  **Files:** `MMailTests/LayoutSizingTests.swift` (existing — append a `@Test`)

- [ ] **T003 (SC: 001): Flatten the reader content surface** — In `ReaderView.swift`: (a) change the pane background `bg2 → bg1` (line ~18) to match the list; (b) on `primaryCard` (lines ~382–388) remove `.background(p.bg1)`, `.clipShape(RoundedRectangle…20…)`, `.overlay(…stroke…)`, `.shadow(…)`, and the `EdgeInsets(top:32,leading:40,bottom:28,trailing:40)` (keep `.frame(maxWidth:.infinity, alignment:.leading)` and `.zIndex`); (c) on the outer ScrollView VStack (line ~80) set `.padding(.horizontal, LayoutSizing.paneContentInset).padding(.top, 16).padding(.bottom, 32)` (top 28→16, bottom 96→32 are deliberate, tunable at live-verify; horizontal is the spec'd 20pt). Net content inset = 20pt, flat. Run: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/Views/ReaderView.swift`

- [ ] **T004 (SC: 001): Route toolbar + list sites through the constant** — Replace literals with `LayoutSizing.paneContentInset`: reader toolbar `.padding(.horizontal, 24)` → constant (`ReaderView.swift:158`); EmailListView header (~96), day-section header (~177), and row (~442) `.padding(.horizontal, 20)` → constant. No residual `40`/`24` on these surfaces. Run: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/Views/ReaderView.swift`, `MMail/Views/EmailListView.swift`

- [ ] **T005 (SC: 001): Commit Phase A** — `git add -A && git commit`. Run: `git log --oneline -1` Expected: the Phase-A commit. Manual exploration deferred to verify (reader flat, no card, left/right content edges align, body ~60pt wider per side).
  **Files:** (commit only)

**↳ Phase A boundary — build green; pause + offer handoff before Phase B.**

---

## Phase B — Sort control (SC-002, SC-004)

Pure `EmailSort` seam → user-selectable, persisted Date/Sender/Subject sort; Date keeps (direction-aware) day sections, Sender/Subject go flat; search exempt.

- [ ] **T006 (SC: 002): Define the EmailSort types + seam signatures** — New file: `enum SortKey { case date, sender, subject }`, `enum SortDirection { case forward, reverse }`, and a unified `ListSort` value (key + direction) that is `RawRepresentable`/string-encodable for UserDefaults, with `static let default = ListSort(.date, .forward)`. Seam signatures (all `static`, SwiftUI-free): `comparator(for: ListSort) -> (Email, Email) -> Bool`, `groupsByDay(for: ListSort) -> Bool`, and `orderedSections(for: ListSort) -> [String]` — the day-bucket keys in render order. `orderedSections` REPLACES a `reversesSections` bool so the section-order DECISION is a pure, testable seam, not View logic (per the spec invariant). Then `xcodegen generate` + commit `project.pbxproj`. Run: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/State/EmailSort.swift` (new), `MMail.xcodeproj/project.pbxproj` (regen)

- [ ] **T007 (SC: 004): Author failing EmailSort unit tests** — New `swift-testing` suite covering: **Date/forward == current `orderNewerFirst`** (sortDate desc, uid desc, id asc) — default must be byte-identical to today; **Date/reverse == the negation** (oldest-first within section, tie-breaks still deterministic); **missing/garbage persisted rawValue → `ListSort.default` (Date/forward)** with no trap; Sender key = name→from-address→"" lowercased; Subject key = lowercased + leading `Re:`/`Fwd:` stripped; **strict weak ordering** for every (key,direction) over a list with equal keys, empty sender, and `nil` sortDate (no comparator-contract trap); `groupsByDay` true only for Date; **`orderedSections`** = `["today","yesterday","earlier","snoozed"]` for Date/forward and all non-Date keys, and `["earlier","yesterday","today","snoozed"]` for Date/reverse (snoozed always last). IMPORTANT: re-run `xcodegen generate` AFTER adding this new test file + commit pbxproj. Run (DEFERRED to verify, MAIN checkout): `xcodebuild … test -only-testing:MMailTests/EmailSortTests …` Expected (when run): FAIL ("not implemented"). In-worktree gate: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMailTests/EmailSortTests.swift` (new), `MMail.xcodeproj/project.pbxproj` (regen)

- [ ] **T008 (SC: 002, 004): Implement EmailSort** — Date/forward comparator = `orderNewerFirst` verbatim (byte-identical default); **Date/reverse = the negated comparator** (swap operands → oldest-first within section, same uid/id tie-breaks) — do NOT reuse `orderNewerFirst` unchanged for reverse; Sender/Subject comparators on their derived keys with `uid` then `id` tie-breaks. `groupsByDay = (key == .date)`. `orderedSections` returns the fixed array for everything except Date/reverse, and the all-but-`snoozed`-reversed array for Date/reverse. **NO DOUBLE-REVERSE:** the comparator owns within-section order; `orderedSections` owns bucket order — independent axes, neither flips the other's. Run (DEFERRED, MAIN): same EmailSortTests Expected: `** TEST SUCCEEDED **`. In-worktree gate: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/State/EmailSort.swift`

- [ ] **T009 (SC: 002): Persisted setting + wire into the sort seam** — Add `@Published var listSort` on `AppModel` (default `ListSort.default` = Date/forward = today's behavior), UserDefaults key `mmail.listSort` (add the constant to `LayoutDefaultsKey` in `LayoutSizing.swift`). Load with the nil-coalescing pattern `loadListWidth` uses (`d.object(forKey:) as? String` → `ListSort(rawValue:) ?? .default`) so a MISSING key yields Date/forward (no empty-string parse-fail); persist in `didSet`/setter. Replace `base.sorted(by: AppModel.isNewerFirst)` at `AppModel.swift:~470` with `base.sorted(by: EmailSort.comparator(for: listSort))` — that one line sorts BOTH the inbox and the label-filter `base` (~459), which is correct (global sort governs all folders, per Non-Goal "no per-folder sort"). ONLY the search-result branch (`visibleEmails` ~446–455) keeps server/live-filter order — leave it alone; do NOT confuse it with the label-filter branch, which DOES get the new sort. Run: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/State/AppModel.swift`, `MMail/State/LayoutSizing.swift`

- [ ] **T010 (SC: 002): Direction-aware grouping + sort-control UI** — In `EmailListView`: (a) when `EmailSort.groupsByDay(for: model.listSort)` is FALSE → render a flat list (no day-section headers, no letter headers); when TRUE → bucket with the existing `groupByDay` logic but drive the section order from `EmailSort.orderedSections(for: model.listSort)` instead of the hardcoded `["today","yesterday","earlier","snoozed"]` array (the View renders the order the seam decides — NO reversal logic in the View). Guard: flat is the `groupsByDay == false` branch — do not invert. (b) Add a sort `Menu` to the header (key + direction) bound to `model.listSort`, shown only when `!isSearch` (mirrors the `!isSearch` filter-chip gate at `EmailListView.swift:86`). Run: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/Views/EmailListView.swift`

- [ ] **T011 (SC: 002): Commit Phase B** — `git add -A && git commit` (includes the regen'd pbxproj). Run: `git log --oneline -1` Expected: the Phase-B commit. Manual (verify): switch keys/directions, confirm persistence across relaunch, Date keeps sections, Sender/Subject flat, search hides the control.
  **Files:** (commit only)

**↳ Phase B boundary — build green; pause + offer handoff before Phase C.**

---

## Phase C — Recipients / CC (SC-003)

Capture all To + CC; replace the single recipient line with To (first-3 + expand) and an always-visible CC line.

- [ ] **T012 (SC: 003): Add the additive `cc` field** — Add `var cc: [String]? = nil` as a stored property on `Email`, mirroring the existing additive `sortDate`/`bodyComplete`/`attachments` pattern (`Models.swift:76,77,83`): declare it WITH the `= nil` default and do NOT add it to the hand-written `init` at `Models.swift:90` (that init deliberately omits `sortDate`/`bodyHTML`/`attachments`, which are set post-construction) — so NO `Email(...)` call site changes. `Codable` synthesis decodes a pre-feature cache (no `cc` key) as `nil`. Run: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/Models/Models.swift`

- [ ] **T013 (SC: 003): Define the recipient-collapse seam** — New file: a pure `RecipientDisplay.collapsed(_ all: [String], limit: Int) -> (shown: [String], overflow: Int)` (SwiftUI-free). `xcodegen generate` + commit pbxproj. Run: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/State/RecipientDisplay.swift` (new), `MMail.xcodeproj/project.pbxproj` (regen)

- [ ] **T014 (SC: 003): Author failing recipient tests** — New `swift-testing` suite: `collapsed(5, limit:3)` → 3 shown + overflow 2; `collapsed(≤3, limit:3)` → all shown + overflow 0; plus an additive-`Codable` test decoding a pre-feature `Email` JSON (no `cc` key, single-element `to`) → `cc == nil`, `to` preserved. `xcodegen generate` + commit pbxproj. Run (DEFERRED, MAIN): `… test -only-testing:MMailTests/RecipientDisplayTests …` Expected (when run): FAIL. In-worktree gate: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMailTests/RecipientDisplayTests.swift` (new), `MMail.xcodeproj/project.pbxproj` (regen)

- [ ] **T015 (SC: 003): Implement the collapse seam** — Implement `RecipientDisplay.collapsed`. Run (DEFERRED, MAIN): same RecipientDisplayTests Expected: `** TEST SUCCEEDED **`. In-worktree gate: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/State/RecipientDisplay.swift`

- [ ] **T016 (SC: 003): Capture all To + CC in the parser** — `IMAPMessage` (non-Codable, `IMAPService.swift:~25–38`): replace singular `toName`/`toEmail` with recipient-array field(s) + add a `cc` array. This changes the SYNTHESIZED memberwise init, so update its SOLE construction site in lock-step: `parseMessages` at `IMAPService.swift:639` (`out.append(IMAPMessage(uid:…toName:toEmail:…))`). Envelope parse (`IMAPService.swift:~623–628`): map ALL `env.to` (not `.first`) + all `env.cc` (confirmed: `NIOIMAPCore.Envelope.cc: [EmailAddressListElement]` exists). `makeEmail` (`AppModel.swift:~2924–2926`): populate `to` with all recipients and set `cc` POST-CONSTRUCTION on the `var` Email (exactly as `sortDate` is set today — not via the init). Run: build Expected: `** BUILD SUCCEEDED **` (the build gate catches any missed construction site).
  **Files:** `MMail/Mail/IMAPService.swift`, `MMail/State/AppModel.swift`

- [ ] **T017 (SC: 003): Reader header To/CC lines** — In `ReaderContent.metaRow` (`ReaderView.swift:516`) DELETE the single `Text(toLine).lineLimit(1)` AND remove the now-orphaned `toLine` computed property (`ReaderView.swift:765`) — grep confirmed line 516 is its only reference. Render in its place: a To: line using `RecipientDisplay.collapsed(email.to ?? [], limit: 3)` + a tappable `+N` revealing the full list, preserving the empty-To fallback (account address / "(no recipient)" — reuse `recipientLine`'s fallback logic); and a Cc: line rendered ONLY when `email.cc` is non-empty (guard: non-empty → show; do NOT invert), same collapse+`+N`. Per-message `@State var toExpanded`/`ccExpanded`, reset by the existing `.id(email.id)` on `ReaderContent` (`ReaderView.swift:12`). Run: build Expected: `** BUILD SUCCEEDED **`
  **Files:** `MMail/Views/ReaderView.swift`

- [ ] **T018 (SC: 003): Commit Phase C** — `git add -A && git commit` (includes regen'd pbxproj). Run: `git log --oneline -1` Expected: the Phase-C commit. Manual (verify): a multi-recipient mail shows first-3 + expand; a CC'd mail always shows the CC line; switching messages collapses; a no-CC mail shows no CC line.
  **Files:** (commit only)

**↳ Phase C boundary — build green; pause before verify.**

---

## Verify (SC-005)

- [ ] **T019 (SC: 005): Full suite + final build from the MAIN checkout** — On a main checkout that has this branch checked out (home-shell permitting) or a throwaway checkout: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug test CODE_SIGNING_ALLOWED=NO`. Expected: `** TEST SUCCEEDED **` with `EmailSortTests`, `RecipientDisplayTests`, and the appended `LayoutSizingTests` all green. Then the worktree type-check build green.
  **Files:** (test run only)

- [ ] **T020: Verify-phase gates** — Run the harness `/verify` flow: type-check build, full test suite (above), opposite-model Sonnet review of the merged diff → APPROVED, and live manual exploration of all three pieces (SC-001/002/003 behaviors). Write `.verified/reader-list-polish` on all-green.
  **Files:** `.verified/reader-list-polish` (marker)
