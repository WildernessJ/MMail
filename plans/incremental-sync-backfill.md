# incremental-sync-backfill Implementation Plan

**Goal:** Make incremental inbox sync backfill messages that are present on the server within the already-loaded UID window but missing from the local cache, so holes self-heal and unread counts stay correct.

**Architecture:** Add a pure `AppModel.backfillWindowUIDs(loaded:present:range:limit:)` seam (mirrors the existing `expungedWindowUIDs`) that returns `present − loaded` inside the window, newest-first, capped at a named constant `backfillCap`. The two incremental call sites (the 15s poll via `loadFolder`, and the user-refresh button via `performUserRefresh`) run `syncFolder` + the base `mergeIncremental` exactly as today, then — decoupled and best-effort — compute the missing set from the flags response (`sync.flags.keys` = the server's present UIDs for the window), fetch those envelopes via a new `IMAPService.fetchEnvelopes(mailbox:uids:)`, and merge them through a NEW lean `insertBackfill(_:accountId:folderId:)`. `insertBackfill` does dedup + append + `registerLabels` + persist ONLY — deliberately none of `mergeIncremental`'s tail effects (`applyRules`, `selectedId` reset, `prefetchBodies`) and no notification and no `autoTrashBlocked`, so backfilled (historical) rows merge silently and stay put. Because backfill never enters `mergeIncremental`, the `autoTrashBlocked` signature is untouched. Separately, `mergeIncremental`'s `lastSeenUID` is scoped to new arrivals (via a `newMailHighWater` seam) so a backfilled UID can never advance the notification high-water. Expunge-reconciliation is unchanged. The Dock unread badge updates automatically via the `emails` `didSet` → `refreshDockBadge`.

**Test Methodology:** e2e-first (per `.harness.yaml`). The project has no Python E2E harness; the established equivalent is Swift Testing unit suites over pure seams (run via `xcodebuild … test`) plus a live manual run for the full heal. All new tests live in the existing `MMailTests/MoveStrategyTests.swift` (alongside `ExpungeReconciliation`) so no `.swift` file is added and `xcodegen generate` is NOT required.

**Conventions:**
- Type-check / build: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- Tests: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug test CODE_SIGNING_ALLOWED=NO`
- Ignore SourceKit/LSP "No such module 'Testing'" / "Cannot find type" noise — `xcodebuild` is authoritative.
- Branch: `fix/incremental-sync-backfill`. Re-assert it (`git checkout fix/incremental-sync-backfill`) immediately before every commit — subagent Bash can switch the shared working tree.

---

## Phase A — Pure backfill seam (types → failing tests → impl)

- [ ] **T001 (SC: 002): Types — add `backfillCap` constant and `backfillWindowUIDs` stub.** Add `private static let backfillCap = 200` and a `static func backfillWindowUIDs(loaded: [UInt32], present: Set<UInt32>, range: ClosedRange<UInt32>, limit: Int) -> [UInt32]` that returns `[]` (stub), placed next to `expungedWindowUIDs` (AppModel.swift:406). Run: `xcodebuild … build CODE_SIGNING_ALLOWED=NO` Expected: PASS.
  **Files:** `MMail/State/AppModel.swift`

- [ ] **T002 (SC: 002): Failing unit tests for `backfillWindowUIDs`.** Add `@Suite struct BackfillReconciliation` to `MMailTests/MoveStrategyTests.swift`, mirroring `ExpungeReconciliation`. Cover the spec scenarios: (a) hole inside window selected newest-first — `loaded:[7866,7830,7524] present:[7524,7600,7700,7830,7866] range:7524...7866 limit:10` ⇒ `[7700,7600]`; (b) cap truncates — `loaded:[7866] present:[7000,7100,7200,7300,7866] range:7000...7866 limit:2` ⇒ `[7300,7200]`; (c) nothing missing ⇒ `[]`; (d) present UID above range ignored — `loaded:[7866] present:[7400,7900] range:7524...7866 limit:10` ⇒ `[7400]`; (e) hole below `oldestLoaded` not selected — `loaded:[7800,7866] present:[7500,7800,7866] range:7800...7866 limit:10` ⇒ `[]`. Run: `xcodebuild … test CODE_SIGNING_ALLOWED=NO` Expected: FAIL at the suite level — with the `[]` stub, cases (a)(b)(d) FAIL; cases (c)(e) already PASS (both expect `[]`).
  **Files:** `MMailTests/MoveStrategyTests.swift`

- [ ] **T003 (SC: 002): Implement `backfillWindowUIDs` + commit.** Body: `let loadedSet = Set(loaded); return present.filter { range.contains($0) && !loadedSet.contains($0) }.sorted(by: >).prefix(limit).map { $0 }`. Run: `xcodebuild … test CODE_SIGNING_ALLOWED=NO` Expected: PASS (all BackfillReconciliation + existing suites green). Then `git checkout fix/incremental-sync-backfill` and commit.
  **Files:** `MMail/State/AppModel.swift`

- [ ] **T004 (SC: 004): Disjointness test (backfill ∩ expunge = ∅).** Add a `@Test` asserting that for a mixed window — `loaded:[7524,7700,7866] present:[7600,7700,7866] range:7524...7866` — `backfillWindowUIDs(limit:10)` ⇒ `[7600]`, `expungedWindowUIDs` ⇒ `[7524]`, and `Set(backfill).isDisjoint(with: Set(expunge))` holds. Run: `xcodebuild … test CODE_SIGNING_ALLOWED=NO` Expected: PASS.
  **Files:** `MMailTests/MoveStrategyTests.swift`

## Phase B — High-water scoping seam (types → failing test → impl)

- [ ] **T005 (SC: 003): Failing test for new-arrival-scoped high-water helper.** Add `static func newMailHighWater(current: UInt32, newArrivalUIDs: [UInt32]) -> UInt32` stub returning `current` (AppModel.swift, near the seams). Add `@Test`s: backfilled UID below current does not advance — `current:7866 newArrivalUIDs:[]` ⇒ `7866`; a genuine new arrival advances — `current:7866 newArrivalUIDs:[7900]` ⇒ `7900`; a (hypothetical) high-UID NOT in the new-arrival list does NOT advance — `current:7866 newArrivalUIDs:[]` ⇒ `7866` (proves backfill, which is never passed here, can't move it). Run: `xcodebuild … test` Expected: FAIL.
  **Files:** `MMail/State/AppModel.swift`, `MMailTests/MoveStrategyTests.swift`

- [ ] **T006 (SC: 003): Implement `newMailHighWater` + commit.** Body: `max(current, newArrivalUIDs.max() ?? current)`. Run: `xcodebuild … test` Expected: PASS. Re-assert branch and commit Phase A+B seams together if not already committed.
  **Files:** `MMail/State/AppModel.swift`

- [ ] **T006b (SC: 005): Idempotence no-op test.** Add a `@Test` (in `BackfillReconciliation`) asserting a steady-state cycle is a no-op at the seam level: `backfillWindowUIDs(loaded:[7700,7830,7866], present:[7700,7830,7866], range:7700...7866, limit:200)` ⇒ `[]` AND `newMailHighWater(current: 7866, newArrivalUIDs: [])` ⇒ `7866`. Together these prove that when the cache already equals the server window and no new mail arrived, backfill adds nothing and the high-water does not move. Run: `xcodebuild … test` Expected: PASS.
  **Files:** `MMailTests/MoveStrategyTests.swift`

## Phase C — IMAP envelope fetch (types/impl; IMAP I/O verified live)

- [ ] **T007 (SC: 001): Add `fetchEnvelopes(mailbox:uids:)` to IMAPService + IMAPSession wrapper.** In `IMAPService`, add `func fetchEnvelopes(mailbox name: String, uids: [UInt32]) async throws -> [IMAPMessage]`: `ensureSelected`, build a `MessageIdentifierSetNonEmpty` from the UID list, `uidFetch(.set(set), [.uid, .flags, .envelope, .internalDate], [])`, `parseMessages(...).sorted { $0.date > $1.date }`; return `[]` for an empty `uids`. Add the matching `run { … }` wrapper in `IMAPSession` (mirror the `syncFolder` wrapper at IMAPSession.swift:66). Run: `xcodebuild … build CODE_SIGNING_ALLOWED=NO` Expected: PASS. (No unit test — IMAP I/O is exercised by the live verify in T012.)
  **Files:** `MMail/Mail/IMAPService.swift`, `MMail/Mail/IMAPSession.swift`

## Phase D — Wire backfill into the merge + call sites (impl)

- [ ] **T008 (SC: 003): Scope `mergeIncremental`'s `lastSeenUID` to new arrivals.** Replace the recompute at AppModel.swift:2424-2426 (`max(all inbox UIDs)`) with `lastSeenUID[accountId] = newMailHighWater(current: lastSeenUID[accountId] ?? 0, newArrivalUIDs: sync.newMessages.map { $0.uid })`. This is the only change to `mergeIncremental`; everything else (flags, expunge, new-message append, notifications, tail effects) is untouched. Run: `xcodebuild … test CODE_SIGNING_ALLOWED=NO` Expected: PASS (full suite green — behavior identical in steady state, since the newest message IS a new arrival).
  **Files:** `MMail/State/AppModel.swift`

- [ ] **T009 (SC: 001, 003): Add the lean `insertBackfill` merge method.** Add `private func insertBackfill(_ msgs: [IMAPMessage], accountId: String, folderId: String)`: guard non-empty; map via `AppModel.makeEmail`; dedup against the existing folder rows by both `uid` and `id`; `emails.append(contentsOf:)` the survivors; `registerLabels(from:)`; `MailCache.save(emails.filter { $0.account == accountId && $0.folder == folderId }, account:, folder:)`. Deliberately DOES NOT: post notifications, touch `lastSeenUID`, call `autoTrashBlocked`, call `applyRules`, reset `selectedId`, or call `prefetchBodies` — backfilled historical rows merge silently and stay put (the Dock badge updates via the `emails` `didSet`). Run: `xcodebuild … build CODE_SIGNING_ALLOWED=NO` Expected: PASS.
  **Files:** `MMail/State/AppModel.swift`

- [ ] **T010 (SC: 001): Best-effort backfill-fetch helper (decoupled from the base sync).** Add a private `func fetchWindowBackfill(session:, box: String, loadedUIDs: [UInt32], sync: IMAPFolderSync) async -> [IMAPMessage]`: if `sync.flagRange == nil` return `[]`; compute `missing = AppModel.backfillWindowUIDs(loaded: loadedUIDs, present: Set(sync.flags.keys), range: sync.flagRange!, limit: Self.backfillCap)`; if empty return `[]`; else `return (try? await withTimeout(15) { try await session.fetchEnvelopes(mailbox: box, uids: missing) }) ?? []`. **Best-effort by design:** any failure/timeout returns `[]` so the base sync is never affected; the hole simply heals on a later poll. Run: `xcodebuild … build CODE_SIGNING_ALLOWED=NO` Expected: PASS.
  **Files:** `MMail/State/AppModel.swift`

- [ ] **T011 (SC: 001): Wire both incremental call sites — base merge first, backfill as a decoupled second pass + commit.** In `loadFolder`'s incremental branch (AppModel.swift:2103-2113) and `performUserRefresh`'s incremental branch (AppModel.swift:1691-1700): keep the existing `sync = try await withTimeout(20) { syncFolder(...) }` and `MainActor.run { mergeIncremental(sync, accountId:, folderId:) }` (base sync, unchanged — must NOT be gated on backfill). THEN, after the base merge, run the decoupled second pass: `let bf = await fetchWindowBackfill(session:, box:, loadedUIDs:, sync:)`; `if !bf.isEmpty { await MainActor.run { self.insertBackfill(bf, accountId:, folderId:) } }`. Use the same `loadedUIDs` list already computed for the `syncFolder` call (the pre-base-merge window; this is correct because hole UIDs are below `afterUID` and new-arrival UIDs are above it, so the sets never overlap). Rationale: base new-mail/flag/expunge updates land every cycle regardless of backfill latency; backfill converges separately and silently. **Watch the early `return`:** the `loadFolder` incremental branch currently `return`s right after the base merge (AppModel.swift:2113) and `performUserRefresh` after its merge (~1700) — the backfill second pass must run BEFORE that `return` (or the `return` must move below it), otherwise backfill never executes at that site. Run: `xcodebuild … test CODE_SIGNING_ALLOWED=NO` Expected: PASS (full suite green). Re-assert branch and commit.
  **Files:** `MMail/State/AppModel.swift`

## Phase E — Live verification

- [ ] **T012 (SC: 001): Live heal on the real account (manual e2e).** Build into the Dock app's DerivedData path, `⌘Q` + relaunch the pinned `MMail.app`, watch the mailbox.org inbox: the UID `7525–7829` hole fills in and the Dock unread badge corrects from `1` to `6` within a few 15s poll cycles — no cache-clear. Also confirm no notification storm for the backfilled (historical) mail. This is the SC-001 / SC-006 manual gate handled by `/verify`; capture the observed result (badge value, hole filled) with file/UID evidence.
  **Files:** none (runtime verification)

---

**Notes for the builder:**
- Dispatch implementation to a single Opus subagent (per project convention). Reviews run opposite-model (Sonnet).
- `sync.flagRange` is `nil` when the flags fetch didn't run (no loaded window); in that case skip backfill (missing = `[]`).
- Do NOT modify `expungedWindowUIDs` or the expunge call's semantics (Non-Goal). Do NOT touch `fetchRecent`/`mergeRealFolder`/load-older paging.
- No new `.swift` files — all edits are to existing files, so do NOT run `xcodegen generate`.
