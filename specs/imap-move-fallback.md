# IMAP MOVE Fallback Specification

## Purpose

The mail client SHALL reliably relocate a message between server mailboxes during triage (Done→Archive, Archive, Spam→Junk, Delete→Trash, manual move) even when the connected IMAP server does not advertise the `MOVE` extension (RFC 6851), and SHALL surface any relocation failure to the user instead of silently discarding it. On mailbox.org — which advertises `UIDPLUS` but not `MOVE` — every server-side triage action currently no-ops silently: the message is removed from the local view (optimistic UI) but never moves on the server, so it reappears on the next sync or persists in the Inbox.

## Invariants

- A move action MUST NEVER complete (remove the source message) unless the server-side relocation actually succeeded; if it fails, the failure MUST be surfaced to the user — never a silent no-op.
- The COPY-based fallback MUST NEVER issue a non-UID (blind) `EXPUNGE`. Only a UID-targeted expunge of the exact source UID is permitted, so unrelated `\Deleted`-flagged messages in the source mailbox are never removed.
- If a server supports neither native `MOVE` nor `UIDPLUS` (no safe targeted expunge), the move MUST fail loudly with no side effects — it MUST NOT copy-then-leave a duplicate, and MUST NOT blind-expunge.
- A move that REPORTS success MUST end with the message present in the destination and absent from the source. A partial failure (the `UID COPY` succeeded but the source could not be `\Deleted`-flagged or expunged) MUST surface an error and MUST NOT be reported as success; a transient duplicate that self-heals on the next sync is acceptable, but it MUST NEVER be cleaned up with a blind `EXPUNGE`.

## Requirements

### Requirement: Capability-aware move strategy

A pure decision function SHALL map the connection's advertised IMAP capabilities to exactly one move strategy: native MOVE when available, a COPY + `\Deleted` + UID-EXPUNGE sequence when MOVE is absent but UIDPLUS is present, and an explicit "unsupported" result otherwise. This function is the testable seam: it contains the policy and has no I/O. Capability atoms SHALL be normalized to a single case at capture time (RFC 9051 §2.3 defines capability atoms as case-insensitive), so the decision function compares against a canonical form.

#### Scenario: Native MOVE available

- **GIVEN** a capability set containing `MOVE`
- **WHEN** the move strategy is computed
- **THEN** the result is the native-move strategy

#### Scenario: MOVE absent, UIDPLUS present

- **GIVEN** a capability set containing `UIDPLUS` and not `MOVE`
- **WHEN** the move strategy is computed
- **THEN** the result is the copy-then-UID-expunge strategy

#### Scenario: Edge case: neither MOVE nor UIDPLUS

- **GIVEN** a capability set containing neither `MOVE` nor `UIDPLUS`
- **WHEN** the move strategy is computed
- **THEN** the result is the unsupported strategy

#### Scenario: Edge case: empty capability set

- **GIVEN** an empty capability set
- **WHEN** the move strategy is computed
- **THEN** the result is the unsupported strategy

#### Scenario: Edge case: capability atoms are case-insensitive

- **GIVEN** a capability set containing `move` (lowercase) or `Uidplus`
- **WHEN** the move strategy is computed
- **THEN** matching treats IMAP capability atoms case-insensitively (native-move / copy strategy respectively)

### Requirement: Server capabilities discovered on connect

`IMAPService` SHALL capture the server's capability set as part of `connectAndLogin()` and retain it (normalized per the strategy requirement) for the lifetime of the connection so move decisions consult it without an extra round-trip per move. Capability data MAY arrive in the login response's `OK [CAPABILITY ...]` (RFC 3501 §6.2.3 — optional), so `connectAndLogin()` SHALL issue an explicit `CAPABILITY` command whenever the login response does not carry capability data, guaranteeing a populated set on every server.

#### Scenario: Capabilities populated after login

- **GIVEN** a freshly connected and authenticated `IMAPService`
- **WHEN** `connectAndLogin()` returns
- **THEN** the service exposes a non-empty capability set

#### Scenario: Edge case: login response omits capability data

- **GIVEN** a server whose login `OK` response carries no `[CAPABILITY ...]`
- **WHEN** `connectAndLogin()` runs
- **THEN** an explicit `CAPABILITY` command is issued
- **AND** the service still exposes a non-empty capability set

#### Scenario: mailbox.org profile

- **GIVEN** a connection to a server that advertises `UIDPLUS` but not `MOVE`
- **WHEN** capabilities are read
- **THEN** the set contains `UIDPLUS` and does not contain `MOVE`

### Requirement: COPY-based fallback move

When the computed strategy is copy-then-UID-expunge, `IMAPService.move(uid:from:to:)` SHALL: (1) `UID COPY` the source UID to the destination mailbox, (2) `UID STORE +FLAGS (\Deleted)` on the source UID, (3) `UID EXPUNGE` the source UID only. Steps 2–3 SHALL run only if step 1 succeeds. (`to:` is the resolved server mailbox path, as today — not a canonical folder id.)

#### Scenario: Fallback relocates the message

- **GIVEN** a MOVE-less, UIDPLUS-capable server and a message in the source mailbox
- **WHEN** `move(uid:from:to:)` is called
- **THEN** the message exists in the destination mailbox
- **AND** the message no longer exists in the source mailbox
- **AND** no other `\Deleted` message in the source mailbox is removed

#### Scenario: Edge case: COPY fails

- **GIVEN** a server where the destination `UID COPY` is rejected (e.g. nonexistent mailbox)
- **WHEN** `move(uid:from:to:)` is called
- **THEN** the source message is NOT flagged `\Deleted` and is NOT expunged
- **AND** the error propagates to the caller

#### Scenario: Edge case: EXPUNGE fails after COPY+STORE

- **GIVEN** a MOVE-less, UIDPLUS-capable server where `UID COPY` and `UID STORE +FLAGS (\Deleted)` succeed but the subsequent `UID EXPUNGE` is rejected or the connection drops
- **WHEN** `move(uid:from:to:)` is called
- **THEN** the error propagates to the caller (the move is NOT reported as success)
- **AND** no blind (non-UID) `EXPUNGE` is issued to force cleanup
- **AND** the transient duplicate (destination copy plus the `\Deleted`-flagged source) is left for the next sync to reconcile

#### Scenario: Edge case: unsupported server

- **GIVEN** a server advertising neither `MOVE` nor `UIDPLUS`
- **WHEN** `move(uid:from:to:)` is called
- **THEN** the call throws a clear "move unsupported" error
- **AND** no `COPY`, `STORE`, or `EXPUNGE` is issued

### Requirement: Move failures are surfaced, not swallowed

The `AppModel` triage paths (`realMove`, `moveToMailbox`, `bulkMoveToMailbox`) SHALL NOT discard move errors with `try?`. On failure they SHALL surface a user-visible error (toast and/or `accountErrors`) AND ensure the message becomes visible to the user again promptly — by restoring the optimistically-removed row OR triggering an immediate refresh of the source folder — rather than relying solely on the next background poll (which can be up to ~15s away). The message MUST remain recoverable: it is still present in its source mailbox because it was never relocated server-side.

#### Scenario: Failed move reports to the user

- **GIVEN** triage of a message whose server move ultimately fails
- **WHEN** the triage action runs
- **THEN** the user sees an error indication (toast or per-account error)
- **AND** the message becomes visible again promptly (restored row or immediate source-folder refresh), not only after the next background poll
- **AND** the message is not silently lost (still retrievable from its source folder)

#### Scenario: Successful move stays silent-success

- **GIVEN** triage of a message on a MOVE-less, UIDPLUS-capable server
- **WHEN** the triage action runs
- **THEN** the message relocates server-side with no error shown to the user

### Requirement: Eager mailbox discovery for cold-inbox triage

The app SHALL ensure the triage destination mailboxes (archive / trash / spam) are resolvable even when the user triages directly from a freshly-loaded inbox, so a move is actually attempted rather than skipped by a nil `mailboxName(...)` lookup. This SHALL be achieved by populating the per-account folder map (`realMailboxes`) eagerly — when the account's inbox is first loaded / on connect, not only on the existing non-inbox `needDiscover` path (`AppModel.swift:1920`) which is skipped for `folderId == "inbox"`. As a backstop, a triage move whose destination is still unresolved SHALL trigger discovery (the existing `resolveMailbox` lazy-LIST logic, `AppModel.swift:2642`) before giving up, so no triage path silently no-ops. The fix MUST cover every `realMove` call site uniformly (there are ~12), which the eager-population approach does by making the shared `mailboxName(...)` lookup succeed.

#### Scenario: Triage from a cold inbox

- **GIVEN** a cold launch loaded straight into the inbox (the folder map for the account is not yet populated)
- **WHEN** the user archives, deletes, or marks-as-spam the first message
- **THEN** the destination mailbox is resolved (eager population, or discovery as a backstop)
- **AND** the server-side move is attempted, not silently skipped

#### Scenario: Edge case: destination folder does not exist

- **GIVEN** a server that has no Archive (or Trash/Junk) mailbox at all
- **WHEN** the user triages a message to that destination
- **THEN** the action reports it could not complete (rather than a silent no-op)

## Success Criteria

- **SC-001**: On a MOVE-less, UIDPLUS-capable server (mailbox.org), Done/Archive/Spam/Delete relocate the message server-side — after the next sync the message no longer appears in INBOX and appears in the destination folder. (manual-exploration)
- **SC-002**: The pure move-strategy function returns the correct strategy for every capability combination (MOVE; UIDPLUS-only; neither; empty; mixed case) — verified by unit tests in the swift-testing target. (automated, non-zero executed count)
- **SC-003**: When a move cannot be completed, the user receives a visible error and the message remains retrievable from its source folder — no silent loss. (manual-exploration)
- **SC-004**: The strategy gate makes a blind `EXPUNGE` structurally unreachable: when UIDPLUS is absent the move strategy is "unsupported" (never a copy/expunge variant), verified by the pure decision function's unit tests. (automated)
- **SC-005**: `xcodebuild -project MMail.xcodeproj -scheme MMail -configuration Debug build CODE_SIGNING_ALLOWED=NO` succeeds and `xcodebuild test` passes with a non-zero executed-test count. (automated)

## Non-Goals

- No general-purpose IMAP capability framework — only the atoms `move` needs (`MOVE`, `UIDPLUS`) are captured.
- No migration away from the NIO-based IMAP stack; no third-party IMAP dependency.
- No batched/bulk server-side MOVE optimization — move remains per-UID (callers already loop).
- No offline queue or automatic retry of failed moves — failures surface and self-heal on the next sync.
- No change to the optimistic-UI model beyond ceasing to swallow errors (immediate optimistic-restore of the removed row is acceptable but not required, since the next sync restores it).
