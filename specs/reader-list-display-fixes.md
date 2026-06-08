# Reader/List Display Fixes Specification

## Purpose

The reader and message-list views SHALL display the true delivered-to recipient, use the available reader-pane width, and order messages newest-first within each day group. This is a batch of three independent, display-layer corrections: today the reader shows the account's own address instead of the address a message was sent to (hiding which alias received it), the message body is capped at a fixed width that wastes pane space, and messages within a day appear oldest-first while the day sections themselves are newest-first. The within-day order uses the existing per-message `uid` (the arrival proxy the app already sorts by elsewhere), so no message data is added or persisted. The recipient-selection and sort-ordering logic SHALL be implemented as pure functions so they can be unit-tested without a SwiftUI host.

## Invariants

- These changes SHALL be display-layer only: no change to which messages are fetched, filtered, threaded, or stored, and NO change to the `Email` model schema or the `MailCache` serialization format. The within-day sort reuses the existing `uid: UInt32?` field — it adds no new persisted data.
- The set of visible messages MUST remain identical; only their on-screen recipient text, content width, and within-day order change.
- The recipient line MUST NEVER fabricate an address. When no delivered-to recipient is known (`email.to` empty/absent — including envelopes whose To is a group address that the existing parser leaves empty) it falls back to the account's address, or `me` when even that is absent. This is the current fallback, not a guess.
- Recipient display for `sent` / `drafts` / `outbox` folders MUST remain unchanged (those already render `email.to`).
- The within-day sort MUST be total and deterministic: messages with a missing `uid` (e.g. demo data) retain a stable, repeatable order relative to one another, and no message is dropped or duplicated.
- The within-day sort MUST be applied at one place in `AppModel` — the non-search sequence exposed by `visibleEmails` / `filteredEmails` — and MUST NOT be applied in the view layer (`groupByDay`). The list rendering, the `selectedEmail` fallback, `navigate()`, and triage all read that one sequence, so the displayed order, auto-selection, and keyboard navigation can never disagree.

## Requirements

### Requirement: Reader shows the delivered-to recipient

For a received message, the reader's recipient line SHALL display the address the message was delivered to (`email.to`, already populated from the IMAP envelope) rather than the active account's canonical address. It SHALL fall back to the account address only when `email.to` is empty or absent. The recipient-selection logic SHALL be extracted into a standalone pure function (taking the message and the account, returning the line); the production `toLine` (`ReaderView.swift:646`) SHALL be deleted or reduced to a thin call to that function, so the unit-tested code IS the code that runs in production — not a parallel untested copy. The function SHALL be unit-testable without instantiating a SwiftUI view.

#### Scenario: Received mail shows the alias it was sent to

- **GIVEN** a received inbox message whose parsed recipient (`email.to`) is `hiltl@sl.holdy.org`
- **AND** the active account's canonical address is `j_holdy@mailbox.org`
- **WHEN** the message is opened in the reader
- **THEN** the recipient line shows `hiltl@sl.holdy.org`
- **AND** it does NOT show `j_holdy@mailbox.org`

#### Scenario: Edge case: received mail with no parsed recipient

- **GIVEN** a received message whose `email.to` is empty or absent (e.g. a group-address To the envelope parser leaves blank)
- **WHEN** the message is opened in the reader
- **THEN** the recipient line falls back to the account's address
- **AND** if no account address is available it shows `me`

#### Scenario: Sent-folder recipient display is unchanged

- **GIVEN** a message in the `sent` folder addressed to one or more recipients
- **WHEN** the message is opened in the reader
- **THEN** the recipient line shows those recipients exactly as it does today

### Requirement: Reader content uses the available pane width

The reader's message content SHALL use the width available in the reader pane rather than a fixed 820pt cap, so the body fills the pane instead of leaving a large empty right gutter. The change targets the inner content `.frame(maxWidth: 820, alignment: .leading)` (`ReaderView.swift:71`); the outer `.frame(maxWidth: .infinity, alignment: .leading)` (`ReaderView.swift:73`) that lets the scroll view fill the pane stays.

#### Scenario: Wide pane fills the available width

- **GIVEN** the reader pane is wider than the former 820pt cap
- **WHEN** a message is displayed
- **THEN** the message content extends to use the available pane width
- **AND** no large fixed-width empty gutter remains on the right

#### Scenario: Edge case: narrow pane stays readable

- **GIVEN** the reader pane is narrower than typical (e.g. a small or split window)
- **WHEN** a message is displayed
- **THEN** the content fits the available width without horizontal overflow

### Requirement: Messages are ordered newest-first within each day group

Within each day group (Today, Yesterday, Earlier, Snoozed), messages SHALL be ordered most-recent-first — by descending `uid`, the arrival proxy already used for sorting elsewhere in the app (the search-results sort at `AppModel.swift:2051` and the prefetch sort at `2304`) — consistent with the existing newest-first ordering of the day sections themselves. The sort SHALL be applied to the non-search path of `visibleEmails` / `filteredEmails` in `AppModel` (NOT in `groupByDay`), so the production list reads through one already-sorted sequence rather than a separate sort in the view. To guarantee a deterministic, render-stable order when `uid` values are equal or absent, the comparator SHALL break ties by the message `id`. The comparator SHALL be a standalone pure function over `Email` so it is unit-testable without a view or the model. Search results are exempt: when a search is active, the server-provided result order is preserved unchanged.

#### Scenario: Newest message appears at the top of its day group

- **GIVEN** the Today group contains three messages whose arrival order (ascending `uid`) corresponds to 08:00, 10:00, then 11:24
- **WHEN** the list renders
- **THEN** they appear top-to-bottom in the order 11:24, 10:00, 08:00 (highest `uid` first)

#### Scenario: Day sections remain newest-first

- **GIVEN** messages spanning Today and Yesterday
- **WHEN** the list renders
- **THEN** the Today section precedes the Yesterday section
- **AND** within each section messages are newest-first

#### Scenario: Edge case: missing or equal sort key

- **GIVEN** two messages in the same day group, one or both with a missing `uid`
- **WHEN** the list renders
- **THEN** ordering is deterministic and stable across re-renders
- **AND** both messages remain present (none dropped or duplicated)

### Requirement: Selection and navigation follow the displayed order

The sort SHALL be applied at a single shared seam (the filtered list the view, the selected-message fallback, and keyboard navigation all read), so that after the change every consumer agrees on order. Opening a folder SHALL auto-select the topmost (newest) message; arrow-key navigation SHALL move through messages in the displayed (newest-first) order; and after a triage action the selection SHALL land on a still-visible adjacent message in that same order — never on a hidden or removed message.

#### Scenario: Opening a folder selects the newest message

- **GIVEN** the inbox has unread and read messages across several days
- **WHEN** the folder is opened
- **THEN** the auto-selected message is the topmost (newest) message in the list

#### Scenario: Keyboard navigation matches the visible order

- **GIVEN** a message is selected in the list
- **WHEN** the user presses the down-arrow / next-message key
- **THEN** selection moves to the message immediately below it in the displayed order

#### Scenario: Selection survives a triage action

- **GIVEN** a message is selected and others remain in the folder
- **WHEN** the selected message is archived/deleted/marked done and leaves the list
- **THEN** selection moves to an adjacent still-visible message in the displayed order
- **AND** selection never points at a message no longer shown

## Success Criteria

- **SC-001**: For a received message delivered to a SimpleLogin alias, the reader's recipient line shows that alias and not the account's canonical address — confirmed by live verification against the mailbox.org account.
- **SC-002**: At a typical full-screen window size the reader message content fills the pane with no large fixed-width empty right gutter — confirmed by live visual inspection.
- **SC-003**: Within every day group the topmost message is the most recent (highest `uid`) and order descends to the oldest, while day sections stay newest-first — confirmed by live verification.
- **SC-004**: The two extracted pure functions — delivered-to recipient selection and the within-day `uid` comparator (with `id` tiebreaker) — live in non-view code that the production reader/list paths call (no parallel untested copy), are covered by tests in the `MMailTests` target that pass under the project's Swift test runner, and all three display behaviors are confirmed by manual exploration in the running app.
- **SC-005**: After the sort lands, opening a folder selects the newest message, arrow-key navigation follows the visible order, and a triage action leaves selection on a still-visible adjacent message — confirmed by live verification.

## Non-Goals

- No multi-recipient or CC display — the IMAP envelope currently keeps only the first To address; surfacing additional recipients is a separate follow-on.
- No user-facing sort control — this batch fixes the default within-day order to newest-first; a persisted/toggleable sort UI (by date/sender/subject) is out of scope.
- No configurable reader-width setting — the fixed cap is raised/removed; a user-adjustable width control is out of scope.
- No true cross-account arrival-time interleaving — within-day order uses per-account `uid`, so in the unified "All inboxes" view messages from different accounts in the same day group are each ordered by their own `uid` and may not interleave by exact receipt time. Accurate cross-account ordering needs a stored `Date` (and the `Email`/cache migration that implies) and is a separate follow-on.
- No changes to fetching, filtering, threading, snoozing, the fetch/merge ordering of the underlying `emails` store, the `Email` model schema, or the `MailCache` format.
