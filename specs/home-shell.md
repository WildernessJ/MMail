# Home Shell Specification

## Purpose

The Home area (shown when `AppModel.folder == "home"`, rendered by `MMail/Views/HomeView.swift`) SHALL be a calm "glance at your day" dashboard composed of individually toggleable widgets. The user SHALL control which widgets appear via a new **Settings → Home** section; Home SHALL render only the enabled widgets and reflow around hidden ones. This sub-feature (#1 of the Home redesign) also adds one new widget — an **Inbox glance** (a read-only unread summary + a short peek at the latest unread mail) — and a visual reskin of the Home surface. The Date and Weather widgets are carried over as-is (their forecast expansion and Calendar/EventKit replacement are sub-features #2 and #3 and are out of scope here).

## Invariants

- Hiding a widget SHALL NEVER delete or mutate that widget's underlying data (journal text, todos, weather city, contacts). Visibility is presentation-only.
- Widget-visibility preferences SHALL be persisted **additively**: each is a new `UserDefaults` key read via `object(forKey:) as? Bool ?? true` (the absent-key-defaults-ON pattern already used at `LayoutSizing.swift:96`). The loader SHALL NOT use `bool(forKey:)`, which returns `false` for an absent key and would wrongly default a widget OFF.
- On upgrade, an existing install SHALL retain all five carried-over widgets (Date, Weather, People, Journal, To-do) ON. The **one** intentional first-run change is that the new Inbox-glance widget appears ON by default — this is the single approved new surface. No carried-over widget's visibility flips and no widget's underlying data changes silently.
- The Inbox-glance widget SHALL be strictly **read-only** over `model.emails`: it performs NO triage, NO flag/state mutation, and NO network fetch. Its only side effect is navigating to and opening an already-existing message via the existing open path.
- Home SHALL NEVER crash or render broken/empty chrome when every widget is disabled — it SHALL show a calm empty state instead.
- This feature SHALL add NO new network egress and NO new system permission. It is a pure read of already-loaded mail plus the already-fetched weather.
- The reskin SHALL preserve every existing widget action (weather-city set, People compose / View all, Journal edit + autosave + archive, To-do add / toggle / remove).

## Requirements

### Requirement: Per-widget visibility toggles

A new **Settings → Home** section SHALL present one persisted on/off toggle for each Home widget — **Date, Weather, Inbox glance, People, Journal, To-do** — each defaulting to ON and persisted across launches via an additive `UserDefaults` key (same pattern as `railSize` / `sidebarLabelsVisible`), read with the absent-key-defaults-ON API above.

Each widget's key SHALL be namespaced, e.g. `mmail.home.show.date`, `…weather`, `…inboxGlance`, `…people`, `…journal`, `…todo`. The `…date` key is named for the **widget slot** (top-left "your day" tile), NOT the literal date content, so sub-feature #3 (Date → Calendar) can reuse it without a key migration or an orphaned default — see Non-Goals.

#### Scenario: Toggle persists across relaunch

- **GIVEN** Home shows all six widgets
- **WHEN** the user turns the **To-do** toggle off in Settings → Home
- **AND** quits and relaunches the app
- **THEN** Home renders without the To-do widget
- **AND** the To-do toggle in Settings reads off

#### Scenario: Absent key defaults ON

- **GIVEN** an install whose `UserDefaults` has no Home-visibility keys (fresh or upgraded)
- **WHEN** Home is shown
- **THEN** all six widgets are visible
- **AND** the content set is identical to today's Home (Date, Weather, People, Journal, To-do) plus the new Inbox glance

#### Scenario: Hiding a widget preserves its data

- **GIVEN** the To-do list contains 3 items
- **WHEN** the user turns To-do off and then on again
- **THEN** the same 3 todos are present and unchanged

### Requirement: Home renders only enabled widgets and reflows

`HomeView` SHALL render exactly the set of enabled widgets and SHALL reflow its layout so a hidden widget leaves **no empty gap or placeholder** where it used to be.

#### Scenario: Both bottom widgets off collapses the row

- **GIVEN** Journal and To-do are both disabled
- **WHEN** Home is shown
- **THEN** the Journal/To-do row is absent entirely (no blank space reserved for it)

#### Scenario: Edge case: all widgets disabled

- **GIVEN** all six widget toggles are off
- **WHEN** Home is shown
- **THEN** a calm empty state is displayed (e.g. a short "Your Home is empty — enable widgets in Settings → Home" message)
- **AND** the app does not crash and shows no broken/blank card frames

#### Scenario: Arbitrary subset reflows coherently

- **GIVEN** only Weather and Inbox glance are enabled
- **WHEN** Home is shown
- **THEN** only those two widgets render, arranged coherently with no gaps left by the disabled Date/People/Journal/To-do

### Requirement: Inbox-glance summary

The Inbox-glance widget SHALL display a quiet unread summary computed over the **current account's inbox** (unified across all accounts when `currentAccount == "all"`, otherwise the selected account, mirroring `homeEmails` at `HomeView.swift:33`), showing the total unread count and a "new today" count. "New today" SHALL be computed with `Calendar.current.isDateInToday(sortDate)` (local time zone, matching the existing convention at `AppModel.swift:2941`).

#### Scenario: Summary counts

- **GIVEN** the current account's inbox has 12 unread messages, 3 of which have a `sortDate` on the current calendar day
- **WHEN** the Inbox glance renders
- **THEN** it shows "12 unread" and "3 new today" (wording may vary; both numbers SHALL be present)

#### Scenario: Respects current account

- **GIVEN** two accounts are configured and `currentAccount` is a single account (not "all")
- **WHEN** the Inbox glance renders
- **THEN** the counts reflect only that account's inbox

#### Scenario: Edge case: inbox zero

- **GIVEN** the current account's inbox has 0 unread messages
- **WHEN** the Inbox glance renders
- **THEN** it shows a calm caught-up state (e.g. "All caught up") and no thread rows

#### Scenario: Edge case: messages with no sortDate

- **GIVEN** some unread inbox messages have a nil `sortDate`
- **WHEN** the "new today" count is computed
- **THEN** nil-dated messages are NOT counted as new-today
- **AND** they still count toward the total unread

#### Scenario: Edge case: demo / pre-account state

- **GIVEN** no real account is configured (`realConfigs` empty)
- **AND** `model.emails` is empty — it is NOT seeded with sample mail (unlike People/Weather, which fall back to `SampleData`; the glance gets no such fallback and SHALL NOT add one)
- **WHEN** the Inbox glance renders
- **THEN** it shows the same calm caught-up / inbox-zero state as the inbox-zero scenario above (zero unread, zero new-today, no rows), no crash

### Requirement: Inbox-glance thread peek

The Inbox-glance widget SHALL take all of the current account's unread inbox messages, **sort them by the existing `orderNewerFirst` seam, then take the first 5** (`.prefix(5)`), each row showing sender, subject, and a short timestamp. The cap applies after sorting, never to an arbitrary pre-sort order.

#### Scenario: Shows newest unread, capped

- **GIVEN** the current account's inbox has 8 unread messages
- **WHEN** the Inbox glance renders
- **THEN** it lists exactly the 5 newest (by `orderNewerFirst`), each with sender, subject, and time

#### Scenario: Fewer than the cap

- **GIVEN** the inbox has 2 unread messages
- **WHEN** the Inbox glance renders
- **THEN** it lists exactly those 2

### Requirement: Open a message from the inbox glance

Clicking an Inbox-glance row SHALL navigate to that message's folder and open it in the reader using the **existing** open path (`setFolder` to its folder, then `activate(id)`), with no triage and no new open behavior. The `setFolder` side effects are intentional and compose safely: it calls `clearSelection()` (which clears only the bulk `selectedIds` set, NOT the scalar `selectedId` that `activate`→`select` sets next) and resets `readerFullScreen = false` (which `activate` re-sets to `true` for the reading-pane-off case). Order matters: `setFolder` MUST precede `activate`.

#### Scenario: Click opens the message

- **GIVEN** Home is shown and the Inbox glance lists an unread message `M` that is present in `model.emails`
- **WHEN** the user clicks `M`'s row
- **THEN** `folder` becomes `M`'s folder (inbox)
- **AND** `M` is selected (`selectedId == M.id`) and shown in the reader (via the standard `activate` path)
- **AND** no triage/move/delete occurs

#### Scenario: Edge case: message not yet loaded

- **GIVEN** the Inbox glance is showing (it can only list rows for messages already in `model.emails`)
- **WHEN** a row is clicked but the corresponding message is no longer present in `model.emails` (e.g. expunged between render and click)
- **THEN** `folder` may switch to inbox, but the glance itself triggers NO triage and force-opens no stale/unrelated message, and the app does not crash
- **AND** any read-mark side-effect comes only from the standard `select`/`activate` path (e.g. `markSelectedReadSoon` acting on the new folder's first visible message) — pre-existing `select` behavior, not a new mutation the glance introduces

### Requirement: Reskin preserves existing widget behavior

The reskinned Date, Weather, People, Journal, and To-do widgets SHALL retain their current actions and data bindings.

#### Scenario: People still composes

- **WHEN** the user clicks a person in the (enabled) People widget
- **THEN** `startCompose` opens a draft addressed to that person, exactly as today

#### Scenario: Journal still autosaves and opens its archive

- **WHEN** the user edits the (enabled) Journal and clicks the saved-journal control
- **THEN** the text autosaves (`persistJournal`) and `journalArchiveOpen` is set, exactly as today

#### Scenario: To-do still mutates

- **WHEN** the user adds, toggles, and removes an item in the (enabled) To-do widget
- **THEN** `addTodo` / `toggleTodo` / `removeTodo` behave exactly as today

#### Scenario: Weather city setter intact

- **WHEN** the user sets a city in the (enabled) Weather widget
- **THEN** `setWeatherCity` runs and the not-found alert path is unchanged

## Success Criteria

- **SC-001**: Each of the six widget toggles hides/shows its widget, and the state survives an app relaunch.
- **SC-002**: With any widget disabled, Home shows no empty placeholder where it was. Verified by manual-exploration: disable each widget (and combinations) and confirm visually there is no blank card frame, reserved gap, or zero-height row where the hidden widget was — the surrounding widgets close up. Reflow is a conditional include/exclude of SwiftUI views, not a frame whose contents are blanked.
- **SC-003**: Disabling then re-enabling a widget leaves its underlying data unchanged (todos, journal text, weather city).
- **SC-004**: The Inbox-glance summary shows unread and "new today" counts that match the current account's inbox (unified for "all"); a pure projection seam over `emails` computes both and passes unit tests, including the nil-`sortDate` and inbox-zero edge cases.
- **SC-005**: The Inbox glance lists the ≤5 newest unread inbox messages newest-first, and clicking one navigates to its folder and opens it in the reader via the existing `activate` path (no triage).
- **SC-006**: A fresh install (no Home-visibility keys) shows all widgets ON — Date, Weather, People, Journal, To-do (today's set) plus the new Inbox glance.
- **SC-007**: With all six widgets disabled, Home shows a calm empty state and does not crash.
- **SC-008**: The pure seams (Home widget-visibility model with additive/absent-key-defaults-ON decoding, and the inbox-glance projection) pass `swift-testing` unit tests; the type-check build is green; manual-exploration and review gates pass.

## Non-Goals

- **No** weather hourly/weekly forecast — that is sub-feature #2.
- **No** macOS Calendar / EventKit events, no Calendar widget, and no Calendar toggle — that is sub-feature #3. To avoid a key-orphan there, the Date slot's visibility key is named for the slot (`mmail.home.show.date`), so #3 reuses it when Date → Calendar; #3 owns the *separate* off-by-default EventKit **consent** gate (a distinct concern from this widget-visibility toggle).
- **No** master "old Home vs new Home" switch (the per-widget toggles cover the need).
- **No** change to the mail list, reader, triage actions, or sync behavior.
- **No** per-widget configuration beyond on/off (e.g. choosing the number of glance rows, or which contacts appear) — the glance row cap is fixed at 5.
- **No** multi-recipient/CC display, user-facing sort control, or text scaling (separate backlog items).
- **No** threading/conversation grouping in the glance — it lists individual unread messages ("threads" used loosely).
