# reader-list-polish Specification

## Purpose

The reader/list display SHALL be polished along three independent, user-approved axes: (A) the reader pane SHALL drop its heavy floating-card chrome and match the mail list's flat inset so the two content panes read consistently and the email body reclaims horizontal space; (B) the mail list SHALL expose a user-selectable, persisted sort over Date / Sender / Subject in either direction, replacing the hardcoded newest-first order; and (C) the message model SHALL capture all `To` and `Cc` recipients (today only the first `To` survives) and the reader header SHALL display them with a collapse-and-expand affordance, with the `Cc` line always shown when present. The three pieces share one feature branch but are behaviorally independent.

## Invariants

- New persisted/cache fields MUST be additive and `Codable` such that a pre-feature on-disk cache decodes without a wipe (absent field → `nil`), consistent with the project's prior additive-Codable migrations (`Email.bodyComplete`, `Email.sortDate`, `MailAccountConfig.avatarColorHex`).
- The active-search result list MUST NEVER be reordered by the sort setting — server (or live-filter) order is preserved exactly as today.
- The reader's horizontal content inset MUST equal the mail list's horizontal content inset, enforced by a single shared constant so the two cannot drift.
- All decision logic (sort comparators, group-by-day choice, recipient collapse) MUST live in pure, SwiftUI-free, deterministic seams that are unit-testable in isolation, mirroring the existing `orderNewerFirst` / `LayoutSizing` pattern.
- Pieces A, B, and C MUST NOT change the body WebView's own white/dark render substrate, the privacy/proxy/CID image paths, or any IMAP behavior beyond reading additional envelope address fields.

## Requirements

### Requirement: Flat reader pane matching the list inset

The reader pane SHALL render its content on a flat `bg1` surface inset by the shared content constant (the mail list's `20pt` horizontal inset), with NO floating card — no rounded-card clip, border stroke, drop shadow, or `bg2`-pane-versus-`bg1`-card contrast. The reader's top action toolbar SHALL use the same horizontal inset.

#### Scenario: Reader content is flat and list-aligned

- **GIVEN** an email is selected and the reading pane is shown
- **WHEN** the reader renders
- **THEN** the email content (subject, recipients, body, reply strip) sits on a flat `bg1` surface
- **AND** its horizontal inset equals the mail list's content inset (the shared constant, `20pt`)
- **AND** there is no rounded card, border, or drop shadow around the content
- **AND** the reader's top toolbar uses the same horizontal inset

#### Scenario: Body reclaims horizontal width

- **GIVEN** the prior layout reserved `40pt` outer margin plus `40pt` card padding per side (≈`80pt`)
- **WHEN** the flattened reader renders at the same pane width
- **THEN** the usable content width increases by ≈`60pt` per side (inset drops from ≈`80pt` to `20pt`)

#### Scenario: Edge case: narrowest reader pane

- **GIVEN** the list↔reader divider is dragged so the reader is at its minimum width (`listWidth` at its `600pt` max)
- **WHEN** the reader renders
- **THEN** content lays out within the `20pt` inset without clipping or negative-width layout

### Requirement: Shared pane content inset constant

A single shared constant SHALL define the horizontal content inset (`20pt`). The mail list's content call sites (header, day-section headers, rows), the reader's content, and the reader's top toolbar (today a divergent `24pt`) SHALL all reference this one constant, so the inset cannot drift between the panes or between the list's own call sites.

#### Scenario: All inset call sites reference the one constant

- **WHEN** the mail list content, the reader content, and the reader toolbar compute their horizontal inset
- **THEN** each reads the single shared constant (`20pt`), with no residual hard-coded `40` / `24` horizontal inset left on those surfaces
- **AND** a unit test asserts the shared constant's value, and manual exploration confirms the left and right panes' content edges align

### Requirement: User-selectable list sort

The mail list SHALL provide a sort control on the list header offering keys Date, Sender, and Subject, each with a direction (Date: Newest-first / Oldest-first; Sender & Subject: A–Z / Z–A). The selection SHALL be a single global setting persisted across launches and applied to every folder's non-search list. The Sender key SHALL be the sender display name (the sender's name if non-empty, else the from-address, else the empty string), compared case-insensitively; the Subject key SHALL be the subject, lowercased, with a single leading `Re:` / `Fwd:` (any case, optional surrounding whitespace) stripped.

#### Scenario: Default is unchanged newest-first by date

- **GIVEN** no sort preference has ever been set
- **WHEN** the inbox list renders
- **THEN** the sort key is Date and direction is Newest-first
- **AND** the order is identical to the pre-feature behavior (newest `sortDate` first, `uid` then `id` as tie-breakers)

#### Scenario: Switching sort key and direction reorders the list

- **GIVEN** the list is showing the inbox
- **WHEN** the user selects Sender / A–Z from the sort control
- **THEN** the visible emails are ordered by sender display name ascending (case-insensitive)

#### Scenario: Sort selection persists across relaunch

- **GIVEN** the user has selected Subject / Z–A
- **WHEN** the app is quit and relaunched
- **THEN** the list renders sorted by Subject / Z–A without re-selecting

#### Scenario: Date / Newest-first keeps day sections in calendar order

- **GIVEN** sort key is Date and direction is Newest-first
- **WHEN** the list renders
- **THEN** emails are grouped under day-section headers in the order Today → Yesterday → Earlier
- **AND** within each section the newest message is first
- **AND** any Snoozed section is pinned last

#### Scenario: Date / Oldest-first reverses both section and within-section order

- **GIVEN** sort key is Date and direction is Oldest-first
- **WHEN** the list renders
- **THEN** the day-section headers appear in the reversed order Earlier → Yesterday → Today
- **AND** within each section the oldest message is first
- **AND** the list therefore reads oldest → newest from top to bottom
- **AND** any Snoozed section is still pinned last (Snoozed is excluded from the date timeline in both directions)

#### Scenario: Sender or Subject sort renders a flat list

- **GIVEN** sort key is Sender (or Subject)
- **WHEN** the list renders
- **THEN** no day-section headers are shown
- **AND** no alphabetical letter-section headers are shown
- **AND** the emails appear as one flat alphabetically-ordered list

#### Scenario: Subject sort strips reply/forward prefixes

- **GIVEN** sort key is Subject / A–Z
- **AND** two messages have subjects `"Re: Budget"` and `"Budget review"`
- **WHEN** the list renders
- **THEN** `"Re: Budget"` sorts as `"budget"` (leading `Re:` / `Fwd:` stripped, case-insensitive), grouping it with `"Budget review"`

#### Scenario: Search results are exempt from the sort setting

- **GIVEN** a search is active with results present
- **WHEN** the list renders
- **THEN** the results keep their server (or live-filter) order
- **AND** the sort setting has no effect
- **AND** the sort control is hidden from the list header while search is active

### Requirement: Pure sort seam

A pure `EmailSort` seam SHALL map a (key, direction) pair to both a comparator over `Email` and a boolean indicating whether the result groups by day, with no SwiftUI or model dependencies.

#### Scenario: Comparator is a valid strict weak ordering

- **WHEN** the comparator for any (key, direction) is applied across a list including equal-key elements and `nil` fields (empty sender, `nil` `sortDate`)
- **THEN** it yields a total, irreflexive, transitive ordering with deterministic tie-breaking (by `uid` then `id`)
- **AND** sorting does not trap or produce a "comparator violates its contract" runtime fault

#### Scenario: Group-by-day flag tracks the key

- **WHEN** `EmailSort` is asked whether a key groups by day
- **THEN** it returns true only for Date and false for Sender and Subject

### Requirement: Capture all To and Cc recipients

Envelope parsing SHALL populate `Email.to` with ALL `To` addresses (today only the first is kept) and a new additive `Email.cc: [String]?` with all `Cc` addresses. Both fields SHALL round-trip through the `Codable` cache; a cache written before this feature SHALL decode with `cc == nil` and no data loss.

#### Scenario: All To recipients captured

- **GIVEN** an incoming message addressed to three `To` recipients
- **WHEN** its envelope is parsed
- **THEN** `Email.to` contains all three addresses in envelope order

#### Scenario: Cc recipients captured

- **GIVEN** an incoming message with two `Cc` recipients
- **WHEN** its envelope is parsed
- **THEN** `Email.cc` contains both addresses

#### Scenario: Edge case: no Cc

- **GIVEN** a message with no `Cc` header
- **WHEN** its envelope is parsed
- **THEN** `Email.cc` is `nil` (or empty) and no `Cc` line is later shown

#### Scenario: Edge case: pre-feature cache decodes

- **GIVEN** an on-disk cache entry serialized before this feature (no `cc` key, single-element `to`)
- **WHEN** it is decoded
- **THEN** decoding succeeds with `cc == nil` and the existing `to` preserved (no wipe)

### Requirement: Reader header recipient display with collapse/expand

The reader header SHALL replace the single one-line recipient string with: a `To:` line showing the first 3 recipients followed by a `+N` expander when more exist; and a `Cc:` line, shown ONLY when `cc` is non-empty but then ALWAYS visible, with the same first-3 + `+N` treatment. Tapping `+N` SHALL reveal the full list for that line. Expansion state SHALL be per-message and SHALL reset when the selected message changes.

#### Scenario: Few recipients shown in full

- **GIVEN** a message with two `To` recipients and no `Cc`
- **WHEN** the reader header renders
- **THEN** both `To` recipients are shown
- **AND** no `+N` expander appears
- **AND** no `Cc:` line appears

#### Scenario: Many recipients collapse with an expander

- **GIVEN** a message with five `To` recipients
- **WHEN** the reader header renders collapsed
- **THEN** the first three are shown followed by a `+2` expander
- **WHEN** the user taps the expander
- **THEN** all five `To` recipients are shown

#### Scenario: Cc line always visible when present

- **GIVEN** a message with any non-empty `Cc`
- **WHEN** the reader header renders
- **THEN** a `Cc:` line is shown (collapsed to first-3 + `+N` if more than three)

#### Scenario: Expansion resets on message change

- **GIVEN** the `To` line is expanded on message A
- **WHEN** the user selects message B
- **THEN** message B's header renders collapsed

#### Scenario: Single-line recipient string is replaced

- **GIVEN** any selected message
- **WHEN** the reader header renders
- **THEN** the previous single one-line recipient string is no longer rendered
- **AND** the `To:` line (and the `Cc:` line when present) render in its place

#### Scenario: Edge case: empty To falls back

- **GIVEN** a message in a sent / drafts / outbox folder whose parsed `to` is empty
- **WHEN** the reader header renders
- **THEN** the `To:` line shows the existing fallback (the account address, else `(no recipient)`), matching the pre-feature `recipientLine` fallback

### Requirement: Pure recipient-collapse seam

A pure seam SHALL compute, from a recipient list and a fixed limit, the shown subset and the overflow count, with no SwiftUI dependency.

#### Scenario: Overflow computed

- **WHEN** the seam is given five recipients and a limit of three
- **THEN** it returns the first three as shown and an overflow count of two

#### Scenario: Edge case: at or under limit

- **WHEN** the seam is given three (or fewer) recipients and a limit of three
- **THEN** it returns all of them as shown and an overflow count of zero

## Success Criteria

- **SC-001**: The reader renders flat (no card, border, or shadow) with content and toolbar horizontal inset equal to the shared constant (`20pt`, the mail list's value) and no residual `40` / `24` inset on those surfaces — confirmed by manual exploration (left and right content edges align) and a unit test asserting the shared constant's value.
- **SC-002**: The user can choose Date / Sender / Subject and a direction from the list header; the choice persists across relaunch; Date keeps day-section grouping, Sender/Subject render a flat list; active-search order is unaffected.
- **SC-003**: All `To` and `Cc` recipients are parsed from the envelope; the reader shows `To` (first 3 + expand) and a `Cc` line that is always visible when `Cc` is present (first 3 + expand); a pre-feature cache loads without a wipe.
- **SC-004**: The `EmailSort` comparator is a valid strict weak ordering for every (key, direction), including `nil`/empty fields, with no comparator-contract runtime fault — unit-tested.
- **SC-005**: The full test suite passes under the project's swift-testing runner (run from the main checkout per the worktree XCTest-runner workaround), and the `type_check_command` build succeeds.

## Non-Goals

- No BCC capture or display.
- No per-folder sort — a single global sort setting governs all folders.
- No user-adjustable reader content max-width cap or reading-width slider; backlog #2 is closed by the padding change, since the existing list↔reader drag already adjusts reader width.
- No true pixel-perfect "as many recipients as fit the available width" layout — a fixed first-3 + `+N` expander is used by design (deterministic and unit-testable).
- No alphabetical letter-section headers for Sender/Subject sorts — the list is flat.
- No sort control within active search results.
- No change to the body WebView's white/dark render substrate or to inner banner styling (remote-image, unsubscribe, image-load indicators keep their existing look); Piece A changes only the outer reader container chrome. The related-thread deck below the primary message keeps its own styling.
- The additive-`Codable` cache guarantee applies to `Email.to` (already `[String]?`) and the new `Email.cc`. `IMAPMessage` is a non-`Codable` in-memory wire struct; extending its singular `toName` / `toEmail` to carry all parsed recipients is an internal change with no cache implication.
