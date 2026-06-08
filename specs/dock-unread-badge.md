# Dock Unread Badge Specification

## Purpose

The app SHALL display the total number of unread inbox messages across all accounts as the macOS Dock icon badge, keeping it in sync as mail is read, received, or triaged, and clearing it when the total is zero. Today the app requests `.badge` notification authorization (`Notifier.swift:10`) and computes unread counts internally (`AppModel.unreadByAccount`, `AppModel.swift:353`), but nothing ever sets the Dock badge — there is no `NSApp.dockTile.badgeLabel` / `applicationIconBadge` call anywhere, so the badge is simply never wired up.

## Invariants

- The Dock badge MUST reflect the total of unread INBOX messages across accounts — the SAME value the in-app account rail already shows (`AccountRailView.totalUnread = sum(unreadByAccount.values)`, `AccountRailView.swift:7`) — never per-folder or current-account-scope counts. (`emails` is only ever populated from real-account IMAP loads — it starts `[]` and is never seeded with demo data, verified — so this total already counts only real accounts; no extra `isRealAccount` filter is needed, and mirroring the rail's exact source guarantees the Dock and in-app counts never diverge.)
- When the unread total is 0 (or negative, defensively), the badge MUST be cleared (empty string), never the literal "0".
- All Dock badge mutations MUST occur on the main thread (AppKit `NSApp.dockTile` is main-thread-only). Because `AppModel` is NOT `@MainActor` (`AppModel.swift:87`) and `emails` can be mutated from background IMAP callbacks, the badge-setting code MUST defensively hop to the main thread (`DispatchQueue.main.async` / `MainActor`) rather than assume its caller is main-isolated.

## Requirements

### Requirement: Unread inbox total

`AppModel` SHALL expose the total unread inbox count across all accounts as a single integer. The counting logic SHALL live in a pure, static function over a list of emails (the testable seam — no `AppModel` instantiation required), counting messages where `unread == true && folder == "inbox"`; the computed `AppModel` property delegates to it over `emails`. This yields the same value as `sum(unreadByAccount.values)` (`AccountRailView.swift:7`), keeping the Dock and in-app counts identical.

#### Scenario: Sum across accounts

- **GIVEN** emails containing 3 unread inbox messages on account A and 2 on account B
- **WHEN** the pure unread-inbox count is computed over that list
- **THEN** it is 5

#### Scenario: Read and non-inbox messages excluded

- **GIVEN** emails containing 2 unread inbox messages, 1 read inbox message, and 4 unread archive messages
- **WHEN** the pure unread-inbox count is computed
- **THEN** it is 2

#### Scenario: Edge case: nothing unread

- **GIVEN** no unread inbox messages on any account
- **WHEN** the unread inbox total is read
- **THEN** it is 0

#### Scenario: Edge case: non-inbox unread excluded

- **GIVEN** unread messages exist only in non-inbox folders (e.g. archive)
- **WHEN** the unread inbox total is read
- **THEN** it is 0

### Requirement: Dock badge label formatting

A pure function SHALL map an unread count to the Dock badge label string: the count rendered as a decimal string when positive, and an empty string when the count is zero or negative. This is the testable seam (no I/O).

#### Scenario: Positive count

- **WHEN** the badge label for unread `5` is computed
- **THEN** the result is `"5"`

#### Scenario: Single unread

- **WHEN** the badge label for unread `1` is computed
- **THEN** the result is `"1"`

#### Scenario: Edge case: zero clears the badge

- **WHEN** the badge label for unread `0` is computed
- **THEN** the result is `""` (empty — clears the badge, never `"0"`)

#### Scenario: Edge case: negative defends to empty

- **WHEN** the badge label for unread `-1` is computed
- **THEN** the result is `""`

#### Scenario: Large count is not capped

- **WHEN** the badge label for unread `1234` is computed
- **THEN** the result is `"1234"` (no `"99+"` capping)

### Requirement: Badge stays in sync

The Dock badge SHALL be set on launch and SHALL update whenever the unread inbox total changes — new mail arriving, marking read/unread, or triage moving a message out of the inbox. The update MUST be driven by the model's data (the `emails` source of truth), NOT by a SwiftUI view's lifecycle: a Dock badge must update even while the app's window is in the background or minimized (new mail arrives on the 15s background poll), and a backgrounded window's SwiftUI body may not re-render — so a view `.onChange` is NOT a reliable trigger. Implementation: observe `emails` at the model level (a `didSet` on the `@Published emails` property, or a Combine subscription on `$emails`) and set `NSApp.dockTile.badgeLabel` from there; also set it once on startup. The setter MUST run on the main thread per the invariant (the trigger can fire on whatever thread mutated `emails`).

#### Scenario: Badge set on launch

- **GIVEN** the app launches with 4 unread inbox messages
- **WHEN** the main window appears
- **THEN** the Dock icon shows badge `"4"`

#### Scenario: Edge case: no accounts (onboarding)

- **GIVEN** the app launches with no accounts connected (onboarding)
- **WHEN** the main window appears
- **THEN** the Dock badge is clear (no badge), because the unread total is 0

#### Scenario: Reading the last unread clears the badge

- **GIVEN** the Dock shows `"1"`
- **WHEN** the user reads that last unread message
- **THEN** the Dock badge clears

#### Scenario: New mail increments the badge

- **GIVEN** the Dock shows `"2"`
- **WHEN** a new unread inbox message arrives on a background sync
- **THEN** the Dock badge becomes `"3"`

#### Scenario: Triaging an unread message out of the inbox decrements the badge

- **GIVEN** the Dock shows `"3"` and the top inbox message is unread
- **WHEN** the user archives/deletes it
- **THEN** the Dock badge becomes `"2"`

## Success Criteria

- **SC-001**: The Dock icon shows the total unread inbox count across all accounts, matching the in-app unified-inbox unread count. (manual-exploration)
- **SC-002**: The badge clears (shows nothing, never `"0"`) when there are no unread inbox messages. (manual-exploration; formatter portion automated)
- **SC-003**: The pure badge-label function returns the correct string for positive, zero, negative, and large inputs. (automated, via the swift-testing `MMailTests` suite so `xcodebuild test` picks it up; non-zero executed count)
- **SC-004**: The pure unread-inbox count function returns the correct count over a constructed list of `Email` values (unread inbox counted; read and non-inbox excluded). (automated — the static seam means no `AppModel` instantiation is needed)
- **SC-005**: `xcodebuild ... build` succeeds and `xcodebuild test` passes with a non-zero executed-test count. (automated)

## Non-Goals

- No per-account Dock badges — macOS has a single Dock icon; the badge is the unified total.
- No badging for non-inbox folders (sent/drafts/archive/etc.).
- No `"99+"`-style capping — show the full number (matches Apple Mail).
- No change to the notification authorization flow — `.badge` is already requested (`Notifier.swift:10`); this feature only sets the badge value.
- No separate "notification count" badge — the Dock badge is the unread inbox total, nothing else.
