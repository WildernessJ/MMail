# incremental-sync-backfill Specification

## Purpose

Incremental inbox sync SHALL converge the local cache to the server's contents *within the already-loaded UID window* `[oldestLoaded…afterUID]`, not merely append messages newer than the local high-water mark. Today's sync (`syncFolder` + `mergeIncremental`) is append-only above `afterUID = max(cached UID)` and refreshes flags below it; it fetches the server's full present-UID set for the window on every poll but discards that set for additions. As a result, any inbox message whose UID falls inside the window but is absent locally is **never** re-requested, producing a permanent hole and an undercounted unread total. This feature makes incremental sync **gap-aware**: it backfills messages present on the server within the window but missing from the cache, delivered as a channel distinct from new arrivals, bounded per cycle so a large hole cannot exceed the sync timeout, converging over successive polls.

The verified live hole — mailbox.org inbox, UIDs `7525–7829` missing between `7830`/`7866` (today) at the top and `7524` (Jun 2) below — sits **inside** the loaded window: the oldest loaded UID is `5056` (Mar 12) and `afterUID` is `7866`, so the flags range `5056…7866` already covers `7525–7829`. Backfill therefore heals this hole without any change to paging.

## Invariants

- Backfill scope MUST be confined to the loaded window `[oldestLoaded…afterUID]`. Backfill MUST NEVER fetch UIDs older than the oldest loaded message — it respects the user's "load older" paging boundary and does not silently expand it. (A hole entirely below `oldestLoaded` is out of scope here; see Non-Goals.)
- For any sync cycle, the set of UIDs backfilled (present on server, absent locally, within range) and the set of UIDs evicted by the existing expunge-reconciliation (absent on server, present locally, within range) are disjoint by construction. Both sets MUST be derived from the **same** present-UID snapshot (`sync.flags.keys`) within one cycle — `backfill = present − loaded` and `expunge = loaded − present` over the same range and same `present` are set-theoretically disjoint. A single UID MUST NEVER be both fetched and removed in the same cycle.
- Backfilled messages are historical, not new arrivals. The sync result MUST deliver them in a channel separate from new-arrival messages so that notification and high-water logic — which key off new arrivals only — never treat a backfilled message as new. Specifically:
  - Backfill MUST NEVER emit a macOS notification.
  - Backfill MUST NEVER advance the new-mail high-water mark `lastSeenUID`. To make this enforceable, `mergeIncremental` MUST compute `lastSeenUID` from the **new-arrival channel only** (the UIDs fetched as new messages above `afterUID`), NOT from `max(all inbox UIDs)` after the merge — otherwise a backfilled UID could silently advance it (e.g. after a server-side reimport that placed an old message at a high UID).
  - Backfill MUST NEVER cause a message to be auto-trashed in the same cycle it is backfilled (historical mail follows the bulk-fetch convention in `mergeRealFolder`, which leaves blocked-sender mail in place). To make this enforceable, the per-cycle backfill UID set MUST be excluded from the `autoTrashBlocked` pass that `mergeIncremental` runs (`AppModel.swift:2428`) — either by passing the backfill UID set to `autoTrashBlocked` as an exclusion parameter, or by structuring the merge so backfilled rows are not in scope for that call in the same cycle.
- The number of envelopes backfilled in a single sync cycle MUST be bounded by a fixed per-cycle cap — a named compile-time constant (the convergence scenarios below use illustrative values such as 200/500; the actual constant is chosen in the plan).
- Sync MUST remain idempotent: a cycle in which the cache already equals the server's windowed contents MUST add nothing, remove nothing, and notify nothing.

## Requirements

### Requirement: Backfill windowed UID set

A pure function SHALL compute, from the locally-loaded UIDs, the server's present UIDs, the window range, and a per-cycle cap, the list of UIDs to fetch: those inside the range and present on the server but not loaded locally, ordered newest-first (descending UID) and truncated to the cap.

#### Scenario: Hole inside the window is selected newest-first

- **GIVEN** loaded UIDs `[7866, 7830, 7524]`
- **AND** server-present UIDs in range `[7524, 7600, 7700, 7830, 7866]`
- **AND** range `7524…7866` and cap `10`
- **WHEN** the backfill set is computed
- **THEN** the result is `[7700, 7600]` (present − loaded, descending UID)
- **AND** no loaded UID appears in the result

#### Scenario: Cap truncates to the newest missing UIDs

- **GIVEN** loaded UIDs `[7866]`
- **AND** server-present UIDs in range `[7000, 7100, 7200, 7300, 7866]`
- **AND** range `7000…7866` and cap `2`
- **WHEN** the backfill set is computed
- **THEN** the result is `[7300, 7200]` (the two newest missing)
- **AND** the result length equals the cap

#### Scenario: Edge case: nothing missing

- **GIVEN** loaded UIDs `[7866, 7830, 7524]`
- **AND** server-present UIDs in range `[7524, 7830, 7866]`
- **AND** range `7524…7866` and cap `10`
- **WHEN** the backfill set is computed
- **THEN** the result is empty

#### Scenario: Edge case: present UID above the range is ignored

- **GIVEN** loaded UIDs `[7866]`
- **AND** server-present UIDs `[7400, 7900]` where `7900` is above the range top
- **AND** range `7524…7866` and cap `10`
- **WHEN** the backfill set is computed
- **THEN** the result is `[7400]`
- **AND** `7900` is not included (it is handled by the new-message path, not backfill)

#### Scenario: Edge case: hole entirely below the window is not backfilled

- **GIVEN** loaded UIDs `[7800, 7866]` (oldest loaded is `7800`)
- **AND** a server-present UID `7500` that is below `oldestLoaded`
- **AND** range `7800…7866` and cap `10`
- **WHEN** the backfill set is computed
- **THEN** the result is empty
- **AND** `7500` is not fetched (healing a sub-window hole is the job of "load older" / full reload, not backfill)

### Requirement: Backfill is disjoint from eviction

The backfill set (present − loaded) and the expunge set (loaded − present) within the same window range SHALL share no UID in any cycle. (The existing expunge-reconciliation, `expungedWindowUIDs`, is unchanged; this requirement asserts the two operations cannot collide.)

#### Scenario: Mixed window yields disjoint add and evict sets

- **GIVEN** loaded UIDs `[7524, 7700, 7866]`
- **AND** server-present UIDs in range `[7600, 7700, 7866]` (7524 expunged on server, 7600 missing locally)
- **AND** range `7524…7866`
- **WHEN** the backfill set and the expunge set are both computed
- **THEN** the backfill set is `[7600]`
- **AND** the expunge set is `[7524]`
- **AND** the two sets have no UID in common

### Requirement: Backfilled messages merge silently

When a sync result carries backfilled (historical) messages in their dedicated channel, `mergeIncremental` SHALL insert them into the folder, dedup them against existing rows by UID, persist the result, but SHALL NOT notify, SHALL NOT advance `lastSeenUID`, and SHALL NOT auto-trash blocked senders among them in that cycle.

#### Scenario: Backfilled message appears without a notification

- **GIVEN** an inbox cache missing UID `7700` (a week-old unread message present on the server)
- **AND** notifications are enabled
- **WHEN** a sync cycle backfills UID `7700`
- **THEN** UID `7700` is present in the inbox after merge
- **AND** no notification was posted for it
- **AND** the inbox unread count increases to include it

#### Scenario: Backfill does not suppress future new-mail notifications

- **GIVEN** `lastSeenUID` for the account is `7866`
- **WHEN** a sync cycle backfills historical UIDs below `7866`
- **THEN** `lastSeenUID` remains `7866`
- **AND** a subsequent genuinely-new message above `7866` still notifies

#### Scenario: Backfilled blocked-sender message is not auto-trashed

- **GIVEN** a sender is on the block list
- **AND** a historical message from that sender is present in the server inbox but missing locally
- **WHEN** a sync cycle backfills it
- **THEN** the message is added to the local inbox (historical mail stays put, matching `mergeRealFolder`)
- **AND** it is not moved to trash by that sync cycle
- **AND** the window-wide `autoTrashBlocked` pass invoked by `mergeIncremental` MUST NOT target a UID solely because it was backfilled this cycle

### Requirement: Per-cycle bound and convergence

Each sync cycle SHALL backfill no more than the per-cycle cap. Absent the creation of new holes, successive cycles SHALL monotonically reduce the missing set until the windowed cache equals the server's windowed contents, after which further cycles are no-ops. New holes can only be created transiently by the new-message path's `prefix(newLimit)` truncation (when more than `newLimit` messages arrive between polls); such holes fall inside the window and are recovered by backfill on subsequent cycles. Convergence therefore holds whenever the per-cycle cap is at least the steady-state rate of new-hole creation — which for a personal inbox is effectively zero.

#### Scenario: A large hole heals over multiple cycles without exceeding the cap

- **GIVEN** a window missing 500 server-present UIDs, a per-cycle cap of 200, and no new arrivals
- **WHEN** three sync cycles run in succession
- **THEN** each cycle backfills at most 200 UIDs
- **AND** after the cycles the missing set is empty
- **AND** a fourth cycle backfills nothing

#### Scenario: New-arrival truncation is recovered by backfill

- **GIVEN** `afterUID` is `7866` and a batch of `newLimit + 5` messages arrives above it before the next poll
- **AND** the new-message fetch keeps only the newest `newLimit` (the oldest 5 of the batch are dropped, becoming a hole just below the new `afterUID`)
- **WHEN** the following sync cycle runs
- **THEN** those 5 UIDs are present in the flags range but absent locally
- **AND** they are backfilled (newest-first, within the cap)
- **AND** the missing set returns to empty

### Requirement: Steady-state idempotence

A sync cycle over a window whose cache already equals the server's windowed contents SHALL add nothing, remove nothing, advance no high-water mark, and post no notification.

#### Scenario: No-op cycle on an already-consistent window

- **GIVEN** loaded UIDs equal the server-present UIDs `[7700, 7830, 7866]` for range `7700…7866`
- **AND** no new messages above `7866`
- **WHEN** a sync cycle runs
- **THEN** the backfill set is empty
- **AND** the expunge set is empty
- **AND** `lastSeenUID` is unchanged
- **AND** no notification is posted

## Success Criteria

- **SC-001 (manual verification, e2e)**: On the live mailbox.org account, after installing the fixed build, the UID hole `7525–7829` fills in and the Dock unread badge corrects from `1` to `6` within a few 15-second poll cycles, with no cache-clear and no manual reload. (Observed in the running app, not under the unit-test runner — this is the manual-exploration gate.)
- **SC-002**: The pure backfill function returns exactly `present − loaded` confined to the window, newest-first, capped at the limit — verified by unit tests mirroring the existing `expungedWindowUIDs` tests.
- **SC-003**: A backfilled historical message produces no macOS notification and does not move `lastSeenUID`, verified by test.
- **SC-004**: Backfill and expunge sets are disjoint for every tested window configuration, verified by test.
- **SC-005**: A steady-state window (cache already equal to the server window) yields a no-op cycle (idempotence), verified by test.
- **SC-006**: All scenarios above pass under the project test runner (`xcodebuild … test`), and the full suite stays green.

## Non-Goals

- No change to the newest-N initial fetch (`fetchRecent`) or the "load older" paging model — backfill operates strictly inside the already-loaded window. A hole entirely below `oldestLoaded` is healed by load-older / full reload, not by backfill.
- No modification to expunge-reconciliation (`expungedWindowUIDs`). `send()` awaits the tagged completion of the FETCH, so the flags response is complete when it returns and the present-UID set is accurate; expunge is already correct under that guarantee. Backfill additionally recovers any transient eviction on the next cycle, so no degenerate-response heuristic is added here (adding one would wrongly suppress a legitimate mass-deletion).
- No QRESYNC/CONDSTORE or full-mailbox resynchronization — this is a bounded, poll-driven reconciliation, not a complete IMAP sync engine.
- No attempt to retroactively prove the exact original trigger that created the existing hole. Backfill heals it regardless; pinning the trigger is an optional follow-up.
- No change to the on-disk cache format, the `Email` model, or UID-based storage.
- Out of scope: backlog #12 (transient triage duplicate), the weather widget, and any non-inbox folder behavior beyond what the shared sync path already does.
