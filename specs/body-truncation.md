# body-truncation Specification

## Purpose

Opening a message SHALL display its **complete** body. The reader currently shows
whatever the preview prefetch warmed, and the prefetch deliberately fetches only the
first 64 KB of a message's raw bytes (`fetchMessageDatas(byteLimit: 65_536)`,
`AppModel.swift:2458`) to keep the warm-cache batch cheap. Because the prefetch then
sets `bodyLoaded = true` (`AppModel.swift:2472`), the full-body fetch on open
(`loadBodyIfNeeded`, gated `!e.bodyLoaded` at `AppModel.swift:2520`) is skipped, so any
message whose raw MIME exceeds 64 KB is rendered permanently truncated — its tail
silently missing and unreachable in the reader's scroll view. This feature makes a
message's completeness explicit and guarantees that opening a message loads the whole
body, while preserving the prefetch's value (instant open, list previews, attachment
indicators) for messages that already fit.

## Invariants

- The reader MUST NEVER display a body that was cut off by the preview prefetch's byte cap.
- The **uncapped open fetch is the source of truth for completeness**: a body fetched with no byte cap SHALL be marked complete unconditionally on success. The capped prefetch SHALL mark a body complete ONLY when the server returned strictly fewer bytes than the cap (proving the whole message fit). The heuristic therefore errs SAFE — it can at worst mark an already-complete body as not-complete (causing one harmless extra fetch on open), and can NEVER mark a truncated body as complete.
- Wherever a loaded body is preserved or copied (folder-refresh merge, server-search-results), its completeness flag MUST travel with it. A complete body MUST NEVER silently become incomplete (which would trigger a needless refetch).
- A message whose raw size fits within the prefetch cap MUST NOT trigger a second fetch on open (the warm-cache fast path is preserved).
- The prefetch MUST keep using `BODY.PEEK` so warming NEVER marks a message as seen.
- The fix MUST NOT alter MIME parsing or the WebView height measurement — the truncation is in the fetch layer, not the renderer.

## Requirements

### Requirement: Body completeness is explicit

The `Email` model SHALL carry an explicit completeness flag distinct from `bodyLoaded`.
Completeness SHALL be determined as follows:

- An **uncapped** fetch (`byteLimit == nil`) that completes successfully yields a complete
  body — set complete = true unconditionally (the whole message was requested).
- A **capped** fetch (`byteLimit == N`) yields a complete body ONLY when the returned byte
  count is strictly less than `N` (the server returned fewer octets than the cap, proving
  end-of-message was reached). A returned count equal to `N` SHALL be treated as
  possibly-truncated (not complete). The exact-boundary case (raw size == N) is a benign
  false-incomplete: it costs at most one extra uncapped fetch on open.

The completeness flag SHALL be **additively decodable**: a cache written before this
feature (where the flag is absent) MUST decode successfully with the body treated as
not-complete — it MUST NOT cause a decode failure that discards the whole cached folder.

#### Scenario: Prefetch of an oversized message marks it incomplete

- **GIVEN** a message whose raw MIME exceeds the prefetch cap (64 KB)
- **WHEN** `prefetchBodies` warms it with `byteLimit: 65_536`
- **THEN** the returned byte count equals the cap
- **AND** its body is marked loaded but NOT complete

#### Scenario: Prefetch of a small message marks it complete

- **GIVEN** a message whose raw MIME is smaller than the prefetch cap
- **WHEN** `prefetchBodies` warms it
- **THEN** the returned byte count is less than the cap
- **AND** its body is marked loaded AND complete

#### Scenario: Edge case: legacy cached body with the flag absent

- **GIVEN** a folder cache written before this feature (no completeness field)
- **WHEN** the cache is decoded
- **THEN** decoding succeeds (the folder is NOT discarded)
- **AND** every message in it is treated as not-complete, so opening any of them fetches the full body

### Requirement: Open loads the complete body

Opening a message SHALL fetch the complete body whenever the cached body is absent OR not
complete. The open fetch SHALL retrieve the entire message **uncapped** (`byteLimit: nil`)
and, on success, SHALL mark the body complete and persist it to the cache. The decision
"should this open trigger a full fetch?" SHALL be a pure function of the cached body's
loaded + complete state, so it is unit-testable without a live server.

Rationale for uncapped (threat model): MMail is a single-user client fetching the user's
own mailbox over TLS, and the fetch is triggered by a deliberate open. The existing 30s
timeout bounds fetch time. Unbounded memory for a pathological multi-MB message is an
accepted trade-off — a "complete body" contract that silently truncated large messages
would reintroduce this very bug.

#### Scenario: Truncated preview is replaced with the full body on open

- **GIVEN** a prefetched-but-incomplete body (truncated at 64 KB)
- **WHEN** the user opens the message
- **THEN** the full message is fetched uncapped
- **AND** the reader renders the complete HTML, including content that was previously cut off
- **AND** the body is marked complete and re-cached

#### Scenario: Complete body opens without a refetch

- **GIVEN** a cached body already marked loaded AND complete
- **WHEN** the user opens the message
- **THEN** the pure refetch decision returns "no fetch"
- **AND** the body displays immediately

#### Scenario: Completeness is copied to the search-results mirror

- **GIVEN** the opened message also appears in `serverSearchResults`
- **WHEN** the full body load succeeds
- **THEN** the search-results copy is updated with both the body AND the complete flag (so reselecting it from search does not refetch)

#### Scenario: Edge case: open fetch fails

- **GIVEN** an incomplete cached body
- **WHEN** the user opens the message AND the full fetch fails or times out
- **THEN** the existing failure path applies (the reader shows the error + Retry affordance)
- **AND** no partial/truncated body is persisted as complete

### Requirement: Completeness survives a folder refresh

`mergeRealFolder` SHALL carry the completeness flag alongside the body when it preserves an
already-fetched body across a folder refresh. A complete body MUST NOT be downgraded to
not-complete by a refresh (which would cause an unnecessary full fetch on the next open).

#### Scenario: Refresh preserves a complete body

- **GIVEN** an open folder containing a message whose body is loaded AND complete
- **WHEN** a background refresh re-syncs the folder and `mergeRealFolder` runs
- **THEN** the message's body remains loaded AND complete
- **AND** opening it triggers no refetch

### Requirement: Prefetch keeps warming previews and never upgrades incomplete bodies

The preview prefetch SHALL continue warming the newest messages + starred with its byte
cap and `BODY.PEEK`, populating preview snippets, attachment, and unsubscribe indicators.
The prefetch pool filter SHALL continue to skip messages whose body is already loaded, so
the prefetch does NOT attempt to upgrade an incomplete warmed body — the uncapped open
fetch is the sole upgrade path. The prefetch SHALL NOT mark a truncated body as complete.

#### Scenario: Warming does not mark messages seen

- **GIVEN** unread messages in a folder
- **WHEN** `prefetchBodies` runs
- **THEN** none of the warmed messages is marked seen on the server
- **AND** list preview snippets and attachment indicators are populated as before

#### Scenario: Prefetch does not re-warm an incomplete body

- **GIVEN** a message already warmed with an incomplete (truncated) body
- **WHEN** `prefetchBodies` runs again for the folder
- **THEN** the message is skipped by the pool filter (it is already `bodyLoaded`)
- **AND** its body is upgraded to complete only when the user opens it

## Success Criteria

- **SC-001**: Opening the "Trade the SpaceX pre-IPO perp" email (raw > 64 KB) renders the "Web3 protocols are accessible…" disclaimer footer (present in MailMate, previously missing in MMail), and the reader scrolls to the true end of the message. (Manual exploration.)
- **SC-002**: The refetch-on-open decision is a pure function; unit tests assert it returns "fetch" for an absent-or-incomplete body and "no fetch" for a loaded+complete body.
- **SC-003**: Warming a folder marks no message as seen (`BODY.PEEK` preserved), and all existing XCTests remain green.
- **SC-004**: The completeness determination (uncapped ⇒ complete; capped ⇒ returned-bytes < cap) is a pure, unit-tested function covering the under-cap, at-cap, and uncapped cases.
- **SC-005**: A complete body survives a `mergeRealFolder` refresh without being downgraded (unit-tested or manually confirmed via no-refetch on open after a background sync).

## Non-Goals

- Not changing the prefetch's 64 KB cap or which messages it warms (newest 8 + starred).
- Not adding streaming or progressive rendering of partial bodies — open fetches the whole message, then renders.
- Not adding an IMAP octet-count cross-check against the requested range: the uncapped open fetch is the completeness source of truth, and the capped-prefetch heuristic only gates an optimization and errs safe, so the extra protocol parsing would be dead weight.
- Not touching MIME parsing, the WebView height/scroll logic (`HTMLMessageView.swift:186`), or the image-proxy render path.
- Not adding a global "download whole mailbox" or offline-full-sync mode — completeness is per-message, on open.
