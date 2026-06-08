# imap-move-fallback Implementation Plan

**Goal:** Make server-side triage (Done/Archive/Spam/Delete) actually relocate messages on IMAP servers that lack the `MOVE` extension (e.g. mailbox.org), and surface failures instead of silently swallowing them.

**Architecture:** Introduce a pure, capability-driven decision function (`IMAPService.moveStrategy(capabilities:)`) returning a `MoveStrategy` enum — the only unit-testable seam. `IMAPService` captures the server capability set on connect and `move()` switches on the strategy: native `UID MOVE`, or `UID COPY` + `UID STORE +FLAGS (\Deleted)` + `UID EXPUNGE` (UIDPLUS-gated, targeted), or a thrown "unsupported" error. The `AppModel` triage paths stop using `try?`, surface errors, and restore visibility; the per-account folder map is populated eagerly so cold-inbox triage resolves its destination.

**Test Methodology:** e2e-first (from `.harness.yaml`). The automated layer targets the pure `moveStrategy` seam via swift-testing (SC-002, SC-004); the live-network behavior (SC-001, SC-003) is manual-exploration against mailbox.org, since CI has no IMAP server. SC-005 = build + `xcodebuild test` green with non-zero executed count.

**Build execution note:** Per the user's workflow, the FULL build is performed by a single Opus subagent following these tasks in order, then an opposite-model review loop. Keep `MoveStrategy` and capability code INSIDE existing files (no new app-target `.swift` → no `xcodegen generate` for production code). The ONE new file is the test file in T002, which requires `xcodegen generate` + committing `MMail.xcodeproj/project.pbxproj`.

**NIO API symbols (VERIFIED against the pinned `swift-nio-imap` revision `01de1f9a` during plan review — re-confirm before use, but these are correct as of review):**
- `Command.uidCopy(LastCommandSet<UID>, MailboxName)` — construct the set as `.range(MessageIdentifierRange<UID>(UID(rawValue: uid)...UID(rawValue: uid)))`, mailbox via the existing `mailbox(to)` helper.
- `Command.uidExpunge(LastCommandSet<UID>)` — construct via `.range(range)` exactly like the existing `.uidMove`/`.uidStore` calls (`IMAPService.swift:388-394`). ⚠️ Do NOT use the `uidExpunge(messages:mailbox:)` convenience — its `mailbox:` parameter is IGNORED by the library; `UID EXPUNGE` operates on the currently-SELECTed mailbox, which `ensureSelected(from)` already handles.
- Capability parsing — capabilities arrive in TWO places, both must be handled:
  - untagged: `Response.untagged(.capabilityData(let caps))` where `caps` is `[NIOIMAPCore.Capability]`.
  - tagged login OK: `case .tagged(let t) = response, case .ok(let text) = t.state, case .capability(let caps) = text.code`.
  - Each `Capability` has `.rawValue: String` (NOT pre-uppercased by the library). Extract `cap.rawValue.uppercased()`.
- `Command.capability` exists for the explicit `CAPABILITY` command.

If any symbol has drifted since review, read the package's actual symbols and adapt; note the deviation in the commit body. NEVER substitute a blind (non-UID) `EXPUNGE`.

---

## Tasks

- [ ] **T001 (SC: 002,004): Define `MoveStrategy` type + stub** — In `IMAPService.swift`, add `enum MoveStrategy: Equatable { case nativeMove, copyThenUidExpunge, unsupported }` and a `static func moveStrategy(capabilities: Set<String>) -> MoveStrategy` that (for now) returns `.unsupported`. Capabilities are compared in a single canonical case (uppercased). Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` Expected: PASS (compiles).
  - **Files:** `MMail/Mail/IMAPService.swift`

- [ ] **T002 (SC: 002,004): Failing unit tests for `moveStrategy`** — Add `MMailTests/MoveStrategyTests.swift` (swift-testing: `import Testing`, `@testable import MMail`). Cover every spec scenario: `["MOVE"]`→`.nativeMove`; `["UIDPLUS"]`→`.copyThenUidExpunge`; `["MOVE","UIDPLUS"]`→`.nativeMove`; `[]`→`.unsupported`; `["IDLE"]` (neither)→`.unsupported`; case-insensitive `["move"]`→`.nativeMove`, `["Uidplus"]`→`.copyThenUidExpunge`, and combined mixed-case `["move","UIDPLUS"]`→`.nativeMove`. Then `xcodegen generate` (new test file) and stage `MMail.xcodeproj/project.pbxproj`. Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug test CODE_SIGNING_ALLOWED=NO` Expected: FAIL (stub returns `.unsupported`, so the MOVE/UIDPLUS cases fail) with a non-zero executed-test count.
  - **Files:** `MMailTests/MoveStrategyTests.swift`, `MMail.xcodeproj/project.pbxproj` (regenerated)

- [ ] **T003 (SC: 002,004): Implement `moveStrategy` + commit** — Replace the stub: normalize each capability via `.uppercased()` into a Set; if it contains `MOVE` → `.nativeMove`; else if it contains `UIDPLUS` → `.copyThenUidExpunge`; else `.unsupported`. Run: same `xcodebuild ... test` Expected: PASS, non-zero executed count. Commit (`spec`-approved seam + tests): `feat: capability-driven IMAP move strategy + unit tests`.
  - **Files:** `MMail/Mail/IMAPService.swift`

- [ ] **T004 (SC: 001,002): Capture capabilities on connect** — Add `private(set) var capabilities: Set<String> = []` to `IMAPService`. Capabilities MUST be populated INSIDE `connectAndLogin()` (`IMAPService.swift:149`), NOT lazily in `move()` — this is what makes reconnect safe: `IMAPSession.run()` creates a fresh `IMAPService` on reconnect and always calls `connectAndLogin()` on it, so populating there means capabilities survive idle-timeout reconnects (a lazy fetch in `move()` would also work but is more fragile — do it in `connectAndLogin()`). Steps: (1) capture the `.login` response and scan for the tagged `OK [CAPABILITY ...]` code (`case .ok(let text) = t.state, case .capability(let caps) = text.code`) and any untagged `.capabilityData(caps)`; insert `cap.rawValue.uppercased()` for each. (2) If the set is still empty, send `Command.capability` and parse its untagged `.capabilityData(caps)` the same way. See the verified NIO symbols above. Run: `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` Expected: PASS. (Live population is manual-exploration — SC-001.)
  - **Files:** `MMail/Mail/IMAPService.swift`

- [ ] **T005 (SC: 001,003): Rewrite `move()` to switch on strategy** — In `IMAPService.move(uid:from:to:)` (`IMAPService.swift:391`), after `ensureSelected(from)`, compute `Self.moveStrategy(capabilities:)` and switch:
  - `.nativeMove` → existing `.uidMove(.range(range), mailbox(to))`.
  - `.copyThenUidExpunge` → in order: `send(.uidCopy(.range(range), mailbox(to)))`; THEN `send(.uidStore(.range(range), [], .flags(.add(silent: true, list: [.deleted]))))`; THEN `send(.uidExpunge(.range(range)))`. Each `send` throws on a tagged NO/BAD (existing behavior), so a failed COPY naturally prevents the STORE/EXPUNGE (do not catch between steps). If EXPUNGE fails after COPY+STORE, let the error propagate — the source keeps its `\Deleted` flag (acceptable transient duplicate per spec; do NOT add rollback code, and NEVER issue a blind/non-UID EXPUNGE to clean up).
  - `.unsupported` → `throw MailError.commandFailed("Server supports neither MOVE nor UIDPLUS; cannot move message")`.

  Reuse the existing `mailbox(_:)` helper and the `range` construction style from `store()`/`move()` (`IMAPService.swift:386-394`). Run: `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` Expected: PASS.
  - **Files:** `MMail/Mail/IMAPService.swift`

- [ ] **T006 (SC: 003): Surface move failures (stop swallowing)** — In `realMove` (`AppModel.swift:2565`), `moveToMailbox` (`:2541`), `bulkMoveToMailbox` (`:2554`), replace `Task { try? await session.move(...) }` with a `do/catch` that surfaces failures. IMPORTANT isolation: `AppModel` is NOT `@MainActor` (confirmed `AppModel.swift:87`), so ALL UI/state mutation in the catch (`showToast`, `accountErrors`, `loadFolder`, `refreshCurrentRealFolder`, mutating `@Published emails`) MUST run on the main actor — wrap the body as `Task { @MainActor in ... }` or use `await MainActor.run { ... }` inside the catch. On failure: (a) show `showToast("Couldn't move: \(error.localizedDescription)")` and/or set `accountErrors[account]`; (b) make the message visible again promptly — call `loadFolder(account, <sourceFolder>, silent: true)` (or `refreshCurrentRealFolder(silent: true)`) so it returns without waiting for the 15s poll. Do NOT change the success path's behavior. Run: `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` Expected: PASS.
  - **Files:** `MMail/State/AppModel.swift`

- [ ] **T007 (SC: 001): Eager + backstop mailbox discovery; uniform realMove path** — Three coordinated changes so cold-inbox triage never silently no-ops, covering ALL ~12 `realMove` call sites:
  1. **Eager population (primary):** when a real account's inbox is first loaded / on connect, populate `realMailboxes[account]` (run the LIST→map population). Today the `needDiscover` gate (`AppModel.swift:1920`) explicitly skips this for `folderId == "inbox"`. DRY: refactor so both the `needDiscover` branch (`:1929-1943`) and this eager path call the SAME helper as `resolveMailbox` (`:2642`) rather than duplicating the LIST→map switch (there are already two copies of that switch — unify to one).
  2. **realMove backstop + uniform entry (secondary):** restructure `realMove` (`:2565`) so a nil destination does NOT silently `return`. `from` resolves fine from a cold inbox (`mailboxName` special-cases inbox→"INBOX", `:1460`); the problem is the destination. Inside the move `Task { @MainActor in ... }`: resolve `to = mailboxName(account, folderId)`; if nil, `await resolveMailbox(account, kind: <map folderId→MailboxKind>, session:)` to discover; if STILL nil (the folder genuinely doesn't exist) surface an error toast (per spec "destination folder does not exist" scenario) — EXCEPT preserve the existing delete fallback: for `trash`, fall back to `applyRealFlag(.deleted, add: true)` in place (matches current `delete`/`bulkDelete` behavior at `:539-540`,`:444-445`). You'll need a small `folderId → MailboxKind` mapping (archive→.archive, trash→.trash, spam→.junk) — `resolveMailbox` already has the inverse switch.
  3. **Remove the now-redundant pre-guards:** the `if mailboxName(e.account, ...) != nil { realMove(...) }` guards in `archive` (`:522-525`), `markDone` (`:530-533`), `markSpam` (`:546-549`), `delete` (`:538-541`), `bulkDelete` (`:443-446`), `bulkTriage` (`:466`) pre-empt `realMove` on a cold inbox. Since `realMove` now resolves-with-discovery and handles the no-folder/trash-fallback itself, simplify these to call `realMove(e, to: ...)` unconditionally for real accounts (keep the optimistic `moveTo`/local folder change and the `delete`→`\Deleted` fallback semantics, but route them through realMove's new logic — do not leave two competing copies of the fallback).

  Keep it DRY; do not regress the optimistic UI. Run: `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` Expected: PASS. Commit: `fix: COPY-based move fallback, surfaced errors, eager+backstop folder discovery`.
  - **Files:** `MMail/State/AppModel.swift`

- [ ] **T008 (SC: 005): Full verification + manual-exploration** — Run the type-check/build and the test suite; confirm green with a NON-ZERO executed-test count (not just exit 0). Run: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO && xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug test CODE_SIGNING_ALLOWED=NO 2>&1 | tail -40` Expected: BUILD SUCCEEDED, TEST SUCCEEDED, "Executed N tests" with N>0. Then record the manual-exploration checklist for the next human run (cannot be automated — no IMAP server in CI): (a) cold-launch into inbox, Archive the top message → after next sync it is gone from INBOX and present in Archive on mailbox.org; (b) Delete → appears in Trash; (c) Spam → appears in Junk; (d) simulate a failure (e.g. triage to a non-existent destination) → error toast shown and message stays/returns to view. Document results in the verify marker / handoff.
  - **Files:** none (verification only)

---

## Notes for the build subagent
- DRY: one capability-normalization path; one folder-discovery helper.
- YAGNI: only capture/compare the atoms `move` needs (`MOVE`, `UIDPLUS`). No general capability framework.
- Do NOT switch `testing.method`; do NOT add `xcodegen generate &&` to the verify command. Run `xcodegen generate` manually ONLY in T002 (new test file), then commit the regenerated `project.pbxproj`.
- The `MMailTests` scheme runs only `MMailTests`; confirm a non-zero executed-test count, not just exit 0 (harness gotcha).
- If any assumed NIOIMAPCore symbol does not exist, read the package's actual symbols and adapt; note the deviation in the commit body.
