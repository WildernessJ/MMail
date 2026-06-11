# inbox-date-sort Specification

## Purpose

The message list — and especially the unified "All inboxes" scope — SHALL order messages by their actual received date, so a multi-account merge interleaves correctly by time. Today `AppModel.isNewerFirst` (AppModel.swift:477) sorts by UID descending. UID is a per-mailbox identifier, so across accounts the ranges are unrelated (e.g. mailbox.org ~1.6k–7.9k vs Gmail ~98k–132k); the merged "all" list therefore puts every message from the high-UID account above every message from the low-UID account, sinking recent mail below older mail. `Email` carries no timestamp (only the `time`/`day` display strings), which is why UID was used as a date proxy. This feature gives `Email` a real, persisted `sortDate`, populated from the IMAP message date, and rewrites the sort comparator to order by date (with a deterministic UID/id tiebreak). Within a single account date and UID agree, so single-account views are unchanged.

## Invariants

- The sort comparator MUST be a valid strict weak ordering: total, transitive, and irreflexive on the "before" relation, with a well-defined equivalence — including when one or both operands have a `nil` `sortDate`. (Swift's `sort`/`sorted` can trap or produce garbage on an inconsistent comparator, and this comparator is on the path every non-search list view funnels through, AppModel.swift:347.)
- Adding `sortDate` to `Email` MUST be additively decodable: a cache file written before this feature (no `sortDate` key) MUST still decode (the field reads as `nil`), never causing the cached folder to be discarded. (Same pattern as `bodyComplete`, Models.swift:75.)
- For normally-received messages in the SAME account, the new ordering matches the prior UID-descending ordering — UID is assigned in arrival order, which for normal delivery tracks received date — so single-account list order, selection fallback, and navigation are effectively unchanged. Where they differ (a message APPEND'd or moved into the mailbox, or delivered late, gets a high UID but an older envelope date), the date-based sort places it at its true chronological position. That is the MORE-correct result and an accepted, intended change — NOT a regression.
- The comparator MUST be deterministic: equal `sortDate` falls back to UID descending, then to `id`, so ties never reorder nondeterministically between renders.

## Requirements

### Requirement: Date-based ordering comparator

`AppModel.isNewerFirst(_:_:)` SHALL order two emails newest-first by `sortDate` descending; when both `sortDate`s are equal (or absent), it SHALL fall back to UID descending, then to `id` ascending. A `nil` `sortDate` SHALL be treated as `Date.distantPast` so the comparison is total and consistent.

#### Scenario: Cross-account order is by date, not UID

- **GIVEN** email A (account `m`, uid `7800`, sortDate `2026-06-09`)
- **AND** email B (account `g`, uid `130000`, sortDate `2025-08-08`)
- **WHEN** the two are ordered by `isNewerFirst`
- **THEN** A sorts before B (newer date wins despite A's far-lower UID)

#### Scenario: Single-account order matches the prior UID-descending order

- **GIVEN** emails in one account with sortDates that increase with UID (uid `10`→older, uid `20`→newer)
- **WHEN** sorted by `isNewerFirst`
- **THEN** the uid `20` email precedes the uid `10` email (identical to the old UID-only result)

#### Scenario: Edge case: a moved/delayed single-account message sorts by date, not UID

- **GIVEN** within one account, email A (uid `7900`, sortDate `2026-06-01`) and email B (uid `7800`, sortDate `2026-06-05`) — B has the older UID but the newer date (delivered late / moved in)
- **WHEN** ordered by `isNewerFirst`
- **THEN** B sorts before A (date wins; this differs from the old UID-descending order and is the intended, more-correct result)

#### Scenario: Edge case: nil sortDate sinks below dated mail and stays consistent

- **GIVEN** email A (sortDate `2026-06-09`, uid `7800`) and email B (sortDate `nil`, uid `131000`)
- **WHEN** ordered by `isNewerFirst`
- **THEN** A (dated) sorts before B (nil → treated as distantPast), regardless of B's higher UID

#### Scenario: Edge case: equal dates tiebreak by UID then id (deterministic)

- **GIVEN** emails A and B with the same `sortDate`, uids `50` and `40`
- **WHEN** ordered by `isNewerFirst`
- **THEN** the uid `50` email precedes the uid `40` email
- **AND** if uids are also equal, the lexicographically smaller `id` precedes

#### Scenario: Edge case: comparator is a strict weak ordering over a mixed set

- **GIVEN** a set mixing dated and nil-date emails across two accounts with overlapping/disjoint UID ranges
- **WHEN** the set is sorted by `isNewerFirst`
- **THEN** sorting completes without trapping
- **AND** the result is stable across repeated sorts (no cycles / nondeterminism)

### Requirement: Email carries a persisted received date

`Email` SHALL have an optional stored property `sortDate: Date?` defaulting to `nil`, populated by `AppModel.makeEmail` from the IMAP message's received date (`internalDate`/envelope date) as a **post-init assignment** (mirroring how `messageID`/`attachments` are set — the `Email` initializer is unchanged), and persisted in the on-disk cache. Every fetch path that builds an `Email` (`fetchRecent`, incremental new messages, backfill, `fetchOlder`/search) routes through `makeEmail` and SHALL therefore set it.

#### Scenario: A freshly-fetched message carries its date

- **GIVEN** an IMAP message with a known received date
- **WHEN** `makeEmail` builds the `Email`
- **THEN** the `Email.sortDate` equals that received date

#### Scenario: Edge case: pre-existing cache decodes without a date

- **GIVEN** a cache file written before this feature (no `sortDate` field)
- **WHEN** it is decoded
- **THEN** decoding succeeds and `sortDate` is `nil` (the folder is not discarded)

## Success Criteria

- **SC-001 (manual verification, e2e)**: On the live app with both accounts configured, after relaunching the updated build the unified "All inboxes" view shows the recent mailbox.org messages (Jun 3–9) in correct date position — above the older 2025 Gmail mail — instead of buried beneath it. (The existing cold-launch `fetchRecent` re-fetches each inbox's newest ~50 with `sortDate` populated, so the visible window re-dates on the next launch without a cache clear.)
- **SC-002**: `isNewerFirst` orders a cross-account pair by date, not UID — unit-tested.
- **SC-003**: `isNewerFirst` reproduces the prior UID-descending order within a single account for normally-received mail, and orders a moved/delayed single-account message by its date (not UID) — both unit-tested.
- **SC-004**: `isNewerFirst` is a strict weak ordering over a mixed dated/nil set (sorts without trapping, deterministic) — unit-tested.
- **SC-005**: All scenarios pass under `xcodebuild … test`, and the full suite stays green.

## Non-Goals

- No bespoke migration/backfill code for `sortDate`. Existing cached entries acquire a date via the normal cold-launch `fetchRecent` refresh and `loadOlder` paging (both route through `makeEmail`); any entry still lacking a date sorts via the UID fallback (sinking below dated mail, which for un-refreshed deep history is acceptable). The deliberate trade-off is "no new load-path machinery" over "instantly re-date every cached row."
- No change to the `time`/`day` display strings or the Today/Yesterday/Earlier section bucketing — only the within/cross-section sort order.
- No change to search-result ordering (search is already exempt from this comparator, AppModel.swift:323).
- No reordering of demo/`SampleData` emails (no uid, no date) beyond the existing `id` fallback.
- No change to the IMAP fetch attributes already retrieved (`internalDate` is already fetched on the relevant paths).
