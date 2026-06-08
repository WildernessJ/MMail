# Special-Use Folder Detection Specification

## Purpose

The client SHALL detect special-use mailboxes — especially the Spam/Junk folder — by their IMAP special-use attributes (RFC 6154, e.g. `\Junk`) rather than relying solely on folder-name heuristics. To guarantee the server returns those attributes, `listMailboxes()` SHALL explicitly request `RETURN (SPECIAL-USE)` in its `LIST` command when the server advertises the `SPECIAL-USE` capability, falling back to the current plain `LIST` (name-based detection) otherwise. This makes "Mark as spam" reliably target the real Spam folder even when its name is non-standard or localized.

## Invariants

- A mailbox's special-use attribute MUST take precedence over name-based heuristics when classifying it (already the order in `classify()`, `IMAPService.swift:519`).
- `RETURN (SPECIAL-USE)` MUST only be sent when the connection's capabilities include BOTH `SPECIAL-USE` (the attributes, RFC 6154) AND `LIST-EXTENDED` (the `LIST … RETURN (…)` mechanism, RFC 5258) — never otherwise. Rationale: `send()` throws on a tagged BAD/NO (`IMAPService.swift:538`), so sending an unsupported `RETURN` option would make `listMailboxes()` throw and break ALL folder discovery — a worse regression than the bug being fixed. Requiring both atoms is the conservative gate. (RFC 6154 §3 says `SPECIAL-USE` implies the return option works, so this is belt-and-suspenders; Dovecot/mailbox.org advertise both.)
- Name-based classification MUST remain intact as the fallback for servers missing either capability or for folders carrying no special-use attribute. This change is strictly additive — it MUST NOT remove or weaken the existing name heuristics.

## Requirements

### Requirement: Request SPECIAL-USE in LIST when the server supports it

`listMailboxes()` SHALL include the `RETURN (SPECIAL-USE)` return option in its `LIST` command when `capabilities` contains BOTH `SPECIAL-USE` and `LIST-EXTENDED`; otherwise it SHALL issue the `LIST` with no return option, exactly as today. The mailbox pattern still matches ALL folders (`*`) — this requests that special-use attributes be *returned*, it does NOT use the `(SPECIAL-USE)` selection option that would filter the list to only special-use folders. The build stage MUST confirm the NIO `ReturnOption.specialUse` encodes as the `RETURN (SPECIAL-USE)` return option (the library's own doc comment misleadingly describes it as a filter; its encoder writes it inside `RETURN (…)`, which is correct — verify, don't assume).

#### Scenario: Capable server

- **GIVEN** a connection whose capabilities include both `SPECIAL-USE` and `LIST-EXTENDED`
- **WHEN** `listMailboxes()` runs
- **THEN** the issued `LIST` carries the `RETURN (SPECIAL-USE)` option
- **AND** all folders are still listed (pattern `*`)

#### Scenario: Incapable server

- **GIVEN** a connection missing `SPECIAL-USE` or `LIST-EXTENDED`
- **WHEN** `listMailboxes()` runs
- **THEN** the issued `LIST` carries no return option (unchanged from today)
- **AND** folder discovery still works via the name heuristics

### Requirement: Classification prefers special-use attributes over names

`classify(name:attributes:)` SHALL map a mailbox to its `MailboxKind` by its special-use attribute when one is present (`\Junk`→`.junk`, `\Sent`→`.sent`, `\Drafts`→`.drafts`, `\Trash`→`.trash`, `\Archive`→`.archive`), and SHALL fall back to name heuristics only when no special-use attribute applies. (This is already implemented; this requirement pins it with tests so the precedence cannot silently regress.)

#### Scenario: Junk flag with a standard name

- **WHEN** `classify(name: "Spam", attributes: [\Junk])` is called
- **THEN** the result is `.junk`

#### Scenario: Junk flag wins over a non-standard name

- **GIVEN** a server that flags a differently-named folder as Junk (e.g. a localized "Werbung")
- **WHEN** `classify(name: "Werbung", attributes: [\Junk])` is called
- **THEN** the result is `.junk` (the flag wins over the name)

#### Scenario: Trash flag wins over a misleading name

- **WHEN** `classify(name: "Papierkorb", attributes: [\Trash])` is called
- **THEN** the result is `.trash` (precedence holds for non-Junk flags too)

#### Scenario: Name fallback when no flag

- **WHEN** `classify(name: "Spam", attributes: [])` is called
- **THEN** the result is `.junk` (name heuristic still works)

#### Scenario: Edge case: unflagged generic folder

- **WHEN** `classify(name: "Projects", attributes: [])` is called
- **THEN** the result is `.other`

The plan's unit tests SHALL cover all five special-use flags (`\Junk`, `\Sent`, `\Drafts`, `\Trash`, `\Archive`) winning over names, so the precedence is genuinely pinned rather than tested only for Junk.

## Success Criteria

- **SC-001**: `classify()` resolves a `\Junk`-flagged folder to `.junk` regardless of its name (the core new guarantee). (automated — this is the real verification of flag-based detection; for mailbox.org specifically the flag and the name "Spam" resolve to the same folder, so the end-to-end win only shows on non-standard names.)
- **SC-002**: `classify()` returns the correct kind with special-use attributes taking precedence over name heuristics, across all five flags. (automated, swift-testing, non-zero executed count)
- **SC-003**: No regression on the live account — after the change, "Mark as spam" still lands the message in mailbox.org's Spam folder, and the other special folders (Sent/Drafts/Trash/Archive) still resolve. (manual-exploration: mark a message as spam in MMail, confirm it appears in Spam on mailbox.org webmail.)
- **SC-004**: `xcodebuild ... build` succeeds and `xcodebuild test` passes with a non-zero executed-test count.

## Non-Goals

- No use of the `(SPECIAL-USE)` LIST *selection* option (which filters the list to only special-use mailboxes) — all folders are still listed.
- No change to the `realMailboxes` folder-id map scheme or how discovered folders are stored/displayed; discovered special folders populate the existing map as before.
- No localization or expansion of the name-heuristic lists.
- No change to the move/triage logic shipped in `imap-move-fallback` — this only improves which mailbox the triage resolves to.
