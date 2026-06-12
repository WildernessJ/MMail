# Open Email in Own Window Specification

## Purpose

MMail's reader is inline-only: a message is read inside the single main window's reader pane (`ReaderView` reads `model.selectedEmail`, `MMail/Views/ReaderView.swift:10`), so a user cannot read two messages side by side or keep one message open while triaging others. This feature SHALL let a user pop a specific email out into its own detached, native macOS window that is a full-parity reader (body, headers, "Show original", load-images, and all toolbar triage actions) bound to that one email — decoupled from the main window's moving selection — and SHALL close that window automatically when the message it shows is archived, deleted, moved, or expunged by external sync, from any source.

## Invariants

- **INV-1 (id-keyed, not value-keyed):** A detached window SHALL be identified by the email's `id` **String** (`Email.id`, shape `account#folder#uid`, `MMail/Models/Models.swift:49`), NOT by the `Email` value. `Email` is `Identifiable, Codable` but NOT `Hashable` (`MMail/Models/Models.swift:48`), so the windowing scene keys on the id string.
- **INV-2 (single shared model):** Both the main window and every detached window SHALL read the SAME `AppModel` instance (the app's single `@StateObject`, `MMail/MMailApp.swift:5`, injected via `.environmentObject`, line 10). No detached window may hold a separate or copied model. Body cache, the session-only inline-CID-image map (`inlinePartsByEmailID`, `MMail/State/AppModel.swift:2782`, surfaced via `inlineParts(for:)`, line 2791), image-proxy config, and triage actions therefore operate on shared state.
- **INV-3 (decoupled from selection):** A detached window SHALL display the specific email it was opened for, looked up by its fixed id from the shared model. It SHALL NEVER follow `model.selectedId` (`MMail/State/AppModel.swift:115`) or `model.selectedEmail` (line 377), which change as the user clicks around the main window.
- **INV-4 (AppModel stays SwiftUI-window-free):** The open-window and close-window actions SHALL be driven by observable model state that a view layer acts on. `AppModel` SHALL NOT itself call the SwiftUI `openWindow`/`dismissWindow` environment actions; it remains free of SwiftUI window APIs by convention.
- **INV-5 (single ⌘O owner):** The `⌘O` accelerator (currently UNBOUND) SHALL have exactly ONE owner. Pressing `⌘O` once SHALL trigger the open-window action exactly once — never twice (no double-fire between a menu accelerator and `handleKeyDown`).
- **INV-6 (no duplicate window per email — plan must spike):** At most ONE detached window SHALL exist for a given email id at a time. Requesting a window for an id that already has one SHALL focus the existing window, not spawn a second. The EXPECTED mechanism is SwiftUI's native same-value dedup for a `WindowGroup(id:for:)` scene (presenting an already-open value focuses its window rather than spawning a duplicate), BUT the codebase has NO existing `openWindow`/`WindowGroup(id:for:)` usage, so this is an UNVERIFIED SwiftUI/macOS API bet. The PLAN MUST spike/verify this dedup on the target macOS version before relying on it. FALLBACK: if native same-value dedup does not hold, the feature SHALL maintain an explicit registry of open-window email ids and use it to enforce single-window-per-id and focus-the-existing-window. This invariant is satisfied by EITHER native dedup (once verified) OR the explicit registry — not presented as guaranteed by the platform.
- **INV-7 (privacy parity):** Remote-image blocking, the image proxy (`imageProxyConfig`), and CID inlining SHALL behave identically in a detached window and in the inline reader, because both render the same reader-content view against the same shared model.
- **INV-8 (no cache-schema change):** This feature is window/render-time only. The on-disk `MailCache` schema and the `Email` `Codable` shape SHALL be unchanged by it.
- **INV-9 (opener folder governs auto-close):** Each detached window SHALL record the folder its email was in when the window's content FIRST APPEARS — whether the window was freshly opened or restored on app relaunch (its "opener folder"). The window SHALL close when the email's CURRENT `folder` (`MMail/Models/Models.swift:62`) differs from the opener folder, OR when the email is no longer present in the shared model at all (hard expunge). Local triage (`moveTo`/`archive`/`delete`/`bulkDelete`, `MMail/State/AppModel.swift:645-684`) mutates `emails[i].folder` IN PLACE and KEEPS the row and its id, so a predicate keyed on "id absent" would fire ONLY on expunge and silently fail the three local-triage cases; the opener-folder comparison is what catches archive/delete/move, and the id-absence check catches expunge. Capturing the opener folder at first-appear (NOT from a persisted open-time event) keeps the windowing value a bare id string (INV-1) and makes the close predicate well-defined for restored windows; a consequence is that a folder change that happened while the app was CLOSED does not retroactively close a restored window — it renders the email in its current folder and closes only on a subsequent in-session move/expunge.
- **INV-10 (detached actions target the window's own id):** Every action invoked from a detached window SHALL operate on THAT window's fixed email id, NEVER on `model.selectedId`/`model.selectedEmail`. Actions currently keyed on the live selection — notably `reply()`/`replyAll()`/`forward()`, which `guard let e = selectedEmail` (`MMail/State/AppModel.swift:1401-1420`) — REQUIRE id-targeted variants before they may be invoked from a detached window. Triage actions already take an id parameter (e.g. the row calls `archive(email.id)`, `MMail/Views/EmailListView.swift:429`), and the detached toolbar SHALL use those id forms.

## Requirements

### Requirement: Open a detached reader window via three entry points

The system SHALL open a detached, standalone macOS window that renders the targeted email as a full reader, reachable from all three of: (1) double-clicking a message-list row, (2) `⌘O` on the current selection, and (3) an "Open in New Window" item in the Message menu.

#### Scenario: Double-click a message-list row opens it in a window

- **GIVEN** the message list is showing rows (`MMail/Views/EmailListView.swift:421`) and no multi-select is active
- **WHEN** the user double-clicks a row
- **THEN** a detached window opens rendering that row's email as a full reader
- **AND** the existing single-click behavior (`model.activate(email.id)`) is preserved on the first click of the double-click — selection and the read-mark timer still start

#### Scenario: ⌘O on the current selection opens it in a window

- **GIVEN** a message is selected in the main window (`model.selectedId` is non-nil and resolves to an email)
- **WHEN** the user presses `⌘O`
- **THEN** a detached window opens rendering the currently selected email
- **AND** `⌘O` fires the open action exactly once (INV-5)

#### Scenario: Message menu "Open in New Window" item opens the selection in a window

- **GIVEN** the Message menu is built from `model.buildCommands()` projected by `MenuModel.build(from:)` (`MMail/MMailApp.swift:28-30`, `MMail/State/MenuModel.swift:41`) and a message is selected
- **WHEN** the user invokes the "Open in New Window" item
- **THEN** a detached window opens rendering the selected email
- **AND** the item displays `⌘O` as its shortcut hint (shown as TEXT, consistent with the existing menu convention where menu items show shortcuts as text)

#### Scenario: Each trigger targets a specific email id, not the live selection

- **WHEN** any of the three triggers fires
- **THEN** the window is requested for the concrete email id chosen at trigger time
- **AND** the detached window thereafter shows that fixed id and does not change as `selectedId` changes (INV-3)

#### Scenario: Edge case: ⌘O with no selection is a no-op

- **GIVEN** no message is selected (`model.selectedId` resolves to nil and there is no email to open)
- **WHEN** the user presses `⌘O`
- **THEN** nothing opens — no detached window, not even an empty one
- **AND** the app remains in its current state with no error

### Requirement: Detached window is a full-parity reader bound to one email

A detached window SHALL render the same reader content as the inline reader for its fixed email id — body, headers, "Show original" toggle, load-images toggle, and the toolbar triage actions (reply, archive, delete, mark, move, etc.) — all acting on the shared model. Every action invoked from the detached window SHALL target that window's own fixed email id, never the live main-window selection (INV-10).

**Reader-content reuse obligation:** the inline reader content is `private struct ReaderContent` (file-scoped, `MMail/Views/ReaderView.swift:36`), so a detached window declared in another file CANNOT reference it as-is. Reusing it (the basis of INV-7 and SC-003's "same reader content" parity) REQUIRES making that reader-content view accessible beyond its current file — un-private it or extract it — as an explicit plan/build step.

#### Scenario: Detached reader shows the same body and headers as inline

- **GIVEN** an email with its body loaded in the shared model's cache
- **WHEN** it is opened in a detached window
- **THEN** the window renders the same body, headers, and thread stack the inline reader would render for that email, by reusing the (made-accessible) inline reader content (`ReaderContent`, `MMail/Views/ReaderView.swift:36`)

#### Scenario: Show original and load images work in the detached window

- **GIVEN** a detached window showing an HTML email with remote images blocked by default (INV-7)
- **WHEN** the user toggles "Show original" or "Load images" in that window
- **THEN** the window re-renders accordingly, using `model.inlineParts(for: email.id)`, `model.imageProxyConfig`, and the dark/showOriginal decision — identically to the inline reader (`MMail/Views/ReaderView.swift` WebView path, ~lines 320-344)
- **AND** these per-window reader toggles are session-scoped state on that window's own reader content (matching the inline `@State loadImages`/`showOriginal`, `MMail/Views/ReaderView.swift:48,52`)

#### Scenario: Toolbar actions in the detached window act on the shared model, targeting the window's own id

- **GIVEN** a detached window showing email A
- **WHEN** the user invokes a triage/compose toolbar action (e.g. reply, mark read/unread, label) that does NOT remove the message
- **THEN** the action runs against the shared `AppModel` (single shared state, INV-2), and its effect is reflected in both the main window and the detached window
- **AND** the action targets A's own fixed id, NEVER `model.selectedId`/`selectedEmail` (INV-10), so it acts on A regardless of what is selected in the main window

#### Scenario: Reply from a detached window drafts against that window's email, not the live selection

- **GIVEN** email A is open in a detached window AND email B is currently selected in the main window (`model.selectedId` resolves to B)
- **WHEN** the user invokes Reply (or Reply All / Forward) in A's detached window
- **THEN** the reply drafts against A, NOT B
- **AND** this requires an id-targeted reply path because `reply()`/`replyAll()`/`forward()` currently `guard let e = selectedEmail` and would draft against B (`MMail/State/AppModel.swift:1401-1420`); adding those id-targeted variants is the plan's responsibility (INV-10)

#### Scenario: Edge case: opening an email whose body is not yet loaded

- **GIVEN** an email that has not had its body loaded (`bodyLoaded` false / body not in cache)
- **WHEN** it is opened in a detached window
- **THEN** the detached window triggers body loading through the shared model (the same load-body path the inline reader relies on) and renders the body once it arrives
- **AND** because the model is shared, the loaded body is also available to the main window without a second fetch (no cache-schema change, INV-8)

### Requirement: Opening the same email focuses the existing window

The system SHALL maintain at most one detached window per email id; requesting a window for an id that already has one open SHALL bring that existing window forward rather than create a duplicate.

#### Scenario: Re-opening an already-detached email focuses it

- **GIVEN** email A already has a detached window open
- **WHEN** the user triggers "open in window" for email A again (via any of the three entry points)
- **THEN** the existing window for A is focused/brought to front
- **AND** no second window for A is created (INV-6) — EXPECTED via native same-value dedup when presenting the same value to the windowing scene, which the plan MUST spike/verify; otherwise enforced by the explicit open-window-id registry fallback (INV-6)

#### Scenario: Two different emails can be open simultaneously

- **GIVEN** email A has a detached window open
- **WHEN** the user opens email B in a detached window
- **THEN** both windows exist at once, each bound to its own fixed id, so the user can compare them side by side

### Requirement: Auto-close when the shown message leaves its opener folder or is expunged

When the email a detached window is showing is archived, deleted, moved, or expunged by external IMAP sync, that detached window SHALL dismiss itself, regardless of whether the change originated from the detached window's own toolbar, the main window, or an external sync. The close condition is: the shown email's CURRENT `folder` differs from the window's opener folder (the folder the email was in at open time, INV-9), OR the email is no longer present in the shared model at all (hard expunge). Either condition closes the window. There SHALL be no stale "message no longer available" placeholder — the window simply closes.

Note: local triage does NOT remove the email row — `moveTo`/`archive`/`delete`/`bulkDelete` mutate `emails[i].folder` IN PLACE and keep the row and its id (`MMail/State/AppModel.swift:645-684`). Only an external IMAP expunge physically removes the row (`emails.removeAll{…}`, `MMail/State/AppModel.swift:2552-2555`). This is why the close predicate compares folders rather than testing id presence.

#### Scenario: Triage from the detached window's own toolbar closes it

- **GIVEN** a detached window showing email A, opened while A was in folder F (its opener folder)
- **WHEN** the user archives, deletes, or moves A from that window's toolbar (`model.archive`/`model.delete`/`model.moveTo`, `MMail/State/AppModel.swift:663,677,645`)
- **THEN** A's row stays in the model but its `folder` is mutated in place to a different folder (`MMail/State/AppModel.swift:645-684`), so A's current folder ≠ opener folder F and the detached window dismisses itself (INV-9)
- **AND** no placeholder is shown

#### Scenario: Triage from the main window closes a detached window

- **GIVEN** email A has a detached window open, opened while A was in folder F
- **WHEN** the user archives/deletes/moves A from the MAIN window (list selection or main toolbar)
- **THEN** A's `folder` is mutated in place (`MMail/State/AppModel.swift:645-684`), so A's current folder ≠ opener folder F, and the windowing layer observes the mismatch and dismisses A's detached window (INV-9)

#### Scenario: Edge case: external IMAP expunge closes a detached window

- **GIVEN** email A has a detached window open
- **WHEN** an external IMAP sync reconciles A as expunged server-side and physically removes its row from the shared model (`emails.removeAll{…}`, `MMail/State/AppModel.swift:2552-2555`; see also `AppModel.expungedWindowUIDs`, `MMail/State/AppModel.swift:416`)
- **THEN** A is no longer present in the model, so the id-absence arm of the close predicate fires and A's detached window dismisses itself (INV-9), folded into the same auto-close behavior as local triage

#### Scenario: Removing one email does not close another email's window

- **GIVEN** detached windows are open for emails A and B
- **WHEN** A leaves its opener folder or is expunged (any source)
- **THEN** only A's window closes; B's window stays open and continues to show B (B's current folder still equals B's opener folder and B is still present)

### Requirement: Windowing actions are driven by observable model state

The open/close window requests SHALL flow through observable model state that the view layer acts on, keeping `AppModel` free of SwiftUI window APIs (INV-4).

#### Scenario: A view layer performs the actual window open/close

- **WHEN** a trigger requests opening a window, or a removal requires closing one
- **THEN** the request is expressed as observable model state, and a SwiftUI view layer (which holds the `openWindow`/`dismissWindow` environment actions) performs the actual window operation
- **AND** `AppModel` itself does not reference SwiftUI window APIs

### Requirement: App-relaunch window restoration tolerates stale ids

When macOS restores detached windows on app relaunch by their stored email ids, a restored window whose email is no longer available in the cache SHALL handle the nil lookup gracefully by self-dismissing (or rendering empty and immediately closing), consistent with the auto-close rule — never showing a stale placeholder. A restored window whose email IS present SHALL capture that email's current folder at restore time as its opener folder (INV-9), so the close predicate is well-defined for restored windows.

#### Scenario: Edge case: relaunch restores a window for an id still in cache

- **GIVEN** a detached window for email A was open when the app quit, and A is still present after relaunch
- **WHEN** the app relaunches and restores the window for A's id
- **THEN** the window renders A as a full reader, looked up by id from the shared model

#### Scenario: Edge case: relaunch restores a window for an id no longer in cache

- **GIVEN** a detached window for email A was open when the app quit, and A is no longer in the cache after relaunch (e.g. expunged while the app was closed)
- **WHEN** the app relaunches and attempts to restore the window for A's id
- **THEN** the lookup-by-id returns nil and the window self-dismisses (or renders empty and closes) — no crash, no stale "no longer available" placeholder

#### Scenario: Edge case: relaunch restores a window for an email moved while the app was closed

- **GIVEN** a detached window for email A was open when the app quit, and while the app was closed A was moved to a different folder (but is still present in the cache)
- **WHEN** the app relaunches and restores the window for A's id
- **THEN** the window renders A and captures A's CURRENT folder at restore as its opener folder (INV-9), so the move-while-closed does NOT auto-close it
- **AND** the window will close on a subsequent in-session move or expunge of A

### Requirement: Read-marking is unchanged and the detached window adds none

The detached window SHALL introduce NO read-marking of its own and SHALL NOT mutate `model.selectedId`. At all three triggers the targeted email IS the current selection at trigger time, so it is already marked read by the EXISTING inline selection path — the detached window relies entirely on that.

Rationale: `markSelectedReadSoon()` guards on `selectedEmail` (`MMail/State/AppModel.swift:623-629`), so it cannot serve as the detached window's own read-marker without either mutating `selectedId` (which would violate the selection-decoupling of INV-3) or marking the wrong email. It is not needed: double-click's first click selects the row (`model.activate(email.id)`); `⌘O` and the Message-menu item both act on the current selection. In every case the email is already the selection and already read-marked by the normal inline mechanism.

#### Scenario: Opening relies on the existing inline read-mark, adds none

- **GIVEN** an unread message that is the current selection at trigger time
- **WHEN** it is opened in a detached window (via any of the three triggers)
- **THEN** it is marked read by the EXISTING inline selection mechanism (`markSelectedReadSoon`, called from `select(_:)`, `MMail/State/AppModel.swift:561-563`) — the detached window introduces no additional or duplicate read-marking and does NOT call `markSelectedReadSoon` for its own id
- **AND** the detached window does NOT mutate `model.selectedId` (INV-3)

#### Scenario: Double-click read-marking is unsurprising

- **GIVEN** a message-list row
- **WHEN** the user double-clicks it to open a window
- **THEN** the first click has already selected the row and started the existing ~0.4s read-mark timer, so opening the window adds no new read-marking surprise

## Success Criteria

- **SC-001:** All three entry points (double-click row, `⌘O` on selection, Message-menu "Open in New Window") each open a detached window rendering the targeted email — verified by live use of each trigger.
- **SC-002:** A detached window shows the email it was opened for and does NOT change when the user clicks other rows in the main window (selection-decoupled) — verified live by opening email A, then clicking around the list and confirming A's window still shows A.
- **SC-003:** A detached window renders full reader parity: body, headers, "Show original", load-images, and triage toolbar actions all function against the shared model — verified live, with WebView render invariants (computed styles, image-blocking/proxy behavior) also verifiable headlessly via an offscreen WKWebView.
- **SC-004:** Triggering open for an email that already has a detached window focuses the existing window and creates no duplicate; two different emails can be open in two windows at once — verified live. The single-window-per-id behavior is EXPECTED via SwiftUI native same-value dedup, but the plan MUST spike/verify it on the target macOS version (the codebase has no prior `openWindow`/`WindowGroup(id:for:)` usage); if native dedup does not hold, the explicit open-window-id registry fallback enforces it (INV-6).
- **SC-005:** A detached window auto-closes when its email (a) is triaged from its own toolbar, (b) is triaged from the main window, and (c) is expunged by external IMAP sync — each path verified live; cases (a) and (b) close because the email's current `folder` leaves the opener folder (the row and id persist, `MMail/State/AppModel.swift:645-684`) and case (c) closes because the row is physically removed (`MMail/State/AppModel.swift:2552-2555`); no "no longer available" placeholder ever appears.
- **SC-006:** `⌘O` fires the open action exactly once with no double-fire, and `⌘O` with no selection opens nothing — verified live.
- **SC-007a:** Opening an email with no body loaded loads its body in the detached window via the shared model and renders it — verified live.
- **SC-007b:** The relaunch-with-cached-data path renders correctly in the detached window — verified live by relaunching with the email's body already cached.
- **SC-008:** On app relaunch, a restored detached window whose email is still cached renders it (capturing the email's current folder at restore as its opener folder, INV-9); a restored window whose email is gone self-dismisses without crash or placeholder — verified live.
- **SC-009 (unit seams):** The email-lookup-by-id (given an id, return the matching `Email` or nil from the shared model) and the close-decision predicate are pure, deterministic seams covered by unit tests. The close-decision predicate takes `(email id, opener folder)` plus the current model and returns true when the email's CURRENT folder ≠ the opener folder OR the email is absent from the model. Unit coverage MUST exercise BOTH arms: the folder-change case (row present, folder mutated away from opener → true) and the absence case (row expunged → true), plus the negative (present and same folder → false).
- **SC-010 (no schema change):** The `MailCache` on-disk schema and `Email` `Codable` shape are byte-for-byte unchanged by this feature — verified by diff/inspection.

## Non-Goals

- **Detached compose/reply windows.** Compose/reply remains a single floating overlay INSIDE the main window (`@Published var compose`, `MMail/State/AppModel.swift:135`; rendered in `RootView`). Popping compose or reply into its own detached window is explicitly deferred to a separate backlog feature.
- **No stale placeholder.** When a shown message is removed, the window closes; it deliberately does NOT show a "message no longer available" placeholder. (User explicitly chose auto-close over a placeholder.)
- **No per-window settings or preferences.** Detached windows have no independent settings/preferences surface; reader toggles (`loadImages`, `showOriginal`) remain session-scoped per reader content, as inline today.
- **No window-frame size/position persistence in v1.** Detached windows rely on SwiftUI's default window sizing/placement; remembering each window's exact frame across sessions is out of scope for the first version.
- **No new cache or `Email` model changes.** This feature is window/render-time only (INV-8); any persistence-schema work is out of scope.
