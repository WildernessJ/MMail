# reader-render-fidelity Specification

## Purpose

The reader SHALL render an email body the way its sender composed it: on a stable
light surface regardless of the app theme, and with embedded inline images shown
inline rather than as broken boxes plus stray attachments. This fixes two related
rendering defects in the WKWebView reader.

**Bug A — dark mode mangles HTML bodies.** `HTMLMessageView` makes the webview
transparent (`web.setValue(false, forKey: "drawsBackground")` in `makeNSView`) and
injects `:root { color-scheme: light dark; }` into the wrapped head (`wrapped(_:)`). In
the dark app theme WebKit auto-darkens body content that uses *system* colors, but any
element carrying an EXPLICIT background or color keeps it. The result is incoherent: a
signature with a white-background `<table>` becomes a white island floating on a darkened
body, and a message that assumes a white page (explicit black text, no background)
renders black text on a dark surface and is unreadable. The two halves of one message
disagree about their background.

Separately, a PLAIN-TEXT-only message does NOT flow through `HTMLMessageView` at all: the
reader's body branch (`ReaderView.swift`, the `if let html = email.bodyHTML` block) only
routes an HTML body to `HTMLMessageView`; its `else` branch renders `Text(email.body)`
styled with the themed foreground `p.fg1` on the themed reader background `p.bg1`. So the
white-surface fix is NOT automatic for plain-text-only mail — see the dedicated
requirement below.

**Bug B — inline CID images render as attachments.** `MIME.swift` has NO Content-ID
handling. A message with a logo or signature image uses `multipart/related` with
`<img src="cid:image001.png@...">` referencing an embedded image part. The attachment
gate inside `walk` sees the part has a filename and classifies it as an attachment (it
appends a `MIME.Attachment`); the `cid:` reference is never resolved. So the image renders
as a blank/broken box in the body AND appears as a downloadable attachment — the same
image shown twice, neither correctly.

**Two attachment types — do not conflate them.** `MIME.Attachment` (defined in `MIME.swift`
as `struct Attachment { filename; mimeType; data }`) is the parse-time, in-memory part —
it carries the decoded `Data`. `AttachmentMeta` (in `Models.swift`, `Codable, Hashable`,
fields `filename`/`mimeType`/`size`) is the cache-serialized type stored on
`Email.attachments`; it drops the bytes and keeps only metadata. The promotion
`MIME.Attachment → AttachmentMeta` happens in `AppModel` (the prefetch and open paths each
`.map { AttachmentMeta(filename: $0.filename, mimeType: $0.mimeType, size: $0.data.count) }`).
The reader's attachment chips iterate the `[AttachmentMeta]` on `Email`. Throughout this
spec, "attachment list" means `Email.attachments: [AttachmentMeta]`.

Both fixes are render-/parse-layer changes. The chosen approach mirrors MailMate / Apple
Mail: render the message on a pure-white surface always (one code path, not theme-gated),
and resolve `cid:` references to inline `data:` URIs so embedded images show inline with
no network fetch.

## Invariants

- The email body surface MUST be a stable, opaque PURE WHITE, decoupled from the app
  theme, on EVERY render — light app mode and dark app mode use the identical render path.
  This applies to BOTH the HTML body (rendered in `HTMLMessageView`) AND the plain-text-only
  body (rendered as SwiftUI `Text` in the reader's `else` branch). App chrome (sidebar,
  list, reader pane border) stays themed; only the message content surface is forced light.
- The reader MUST NOT apply WebKit's dark auto-transform to body content. The wrapped head
  MUST force `color-scheme: only light` (not `light dark`) so WebKit never darkens the
  content, and MUST paint an opaque white background behind the body so transparent /
  unstyled regions read as white rather than the dark window showing through.
- A message that declares its own dark styling MUST be rendered on the white surface
  anyway (we do not honor sender dark modes); the message is shown exactly as it would
  appear on a white page. No per-message heuristic decides light-vs-dark.
- Inline images referenced by `cid:` MUST render inline. Because their bytes are EMBEDDED
  in the message (no network request), they MUST render even when remote-image blocking is
  ON ("load images" off) — they carry no tracking/privacy cost.
- A MIME part that IS referenced by a `cid:` in the HTML body MUST be DROPPED from the
  attachment list (`Email.attachments`) so the same image is not displayed twice. A part
  that has a Content-ID but is NOT referenced anywhere MUST remain a normal attachment. A
  part with no Content-ID is unaffected.
- The referenced/unreferenced filtering MUST be decided AFTER the full parse completes, NOT
  inside `walk`. `walk` recurses per-part and sees the current part BEFORE its siblings; in
  a `multipart/related` message the image part can appear BEFORE the HTML part, so "is this
  CID referenced by the HTML?" cannot be answered during the walk. The Content-ID MUST be
  captured on the parse-time `MIME.Attachment` (a new optional `contentID: String?` field on
  that in-memory struct — it carries `Data` already and is never serialized). `walk` MUST
  collect every candidate `MIME.Attachment` (including CID-bearing parts) and the assembled
  HTML; then a second pass over the fully-assembled `Parsed` MUST drop the `MIME.Attachment`s
  whose Content-ID is referenced by a `cid:` in the final HTML, BEFORE the surviving parts
  are promoted to `[AttachmentMeta]`.
- The CID filtering MUST happen at the `MIME.Attachment → AttachmentMeta` promotion boundary
  (or immediately before it, on the `Parsed.attachments`), so a referenced part never becomes
  an `AttachmentMeta` and never reaches the cache. Consequently `AttachmentMeta` does NOT
  need to carry the Content-ID: the cache-serialized type stays as-is (filename/mimeType/size).
  This avoids any cache-schema change.
- IF the implementation nonetheless adds a stored property to a cache-serialized type
  (`AttachmentMeta` or `Email`), that property MUST be optional with a nil/empty default, so
  a cache written before this feature decodes cleanly. `MailCache` uses a bare `JSONDecoder`
  over the whole `[Email]` array, and `AttachmentMeta` declares no `CodingKeys`, so a
  non-optional new key would fail decode and discard the entire cached folder — the same
  additive-decode hazard the existing `Email.bodyComplete: Bool?` and `Email.sortDate: Date?`
  fields were made optional to avoid.
- The CID→`data:`-URI rewrite MUST happen at RENDER time. `MailCache` MUST continue to
  store the raw `cid:` HTML — it MUST NOT be bloated with base64-inlined image bytes.
- The MIME parser MUST keep capturing each part's Content-ID additively: the existing
  text/html/attachment/calendar classification and the `Parsed`/cache behavior for
  messages WITHOUT any CID part MUST be unchanged.
- This feature MUST NOT alter which messages are fetched, the body-completeness contract,
  the image-proxy signing path, or the WebView height measurement.

## Requirements

### Requirement: Email body renders on a stable white surface

The reader SHALL render the HTML email body on an opaque pure-white surface on every
render, independent of the app's light/dark theme, so the message appears as the sender
composed it for a white page. The wrapped-HTML head SHALL force `color-scheme: only light`
(replacing the current `light dark` in `wrapped(_:)`) and SHALL paint an opaque white
background behind the body, so WebKit applies no dark auto-transform and transparent
regions read as white rather than letting the dark window show through. In the light app
theme the result is identical to today. The content fills the reader pane width,
consistent with the existing full-width reader. App chrome remains themed. (The plain-text-
only body is covered by the separate requirement below; it does not pass through
`HTMLMessageView`.)

The construction of the wrapped-HTML `<head>` (the `color-scheme` + white-background style
block) SHALL be a pure function of the inner HTML string, so the wrapper can be
unit-tested without a WebView host.

#### Scenario: Dark app, white-background signature no longer floats

- **GIVEN** the app is in the dark theme
- **AND** a message whose signature is a `<table>` with an explicit white background
- **WHEN** the message is opened in the reader
- **THEN** the entire message body renders on one continuous white surface
- **AND** the signature table is NOT a white island on a darkened body

#### Scenario: Dark app, black-on-assumed-white body is readable

- **GIVEN** the app is in the dark theme
- **AND** a message with explicit black text and no background (it assumes a white page)
- **WHEN** the message is opened in the reader
- **THEN** the body renders as black text on white and is fully readable
- **AND** WebKit applies no dark auto-darkening to the content

#### Scenario: Light app behavior is unchanged

- **GIVEN** the app is in the light theme
- **WHEN** any HTML message is opened
- **THEN** it renders exactly as it does today (white surface, sender's colors intact)

#### Scenario: Edge case: message declares its own dark styles

- **GIVEN** a message whose own CSS sets a dark background / light text
- **WHEN** it is opened in either app theme
- **THEN** it is rendered on the forced white surface using its declared styles as-on-white
- **AND** no per-message logic switches the surface to dark

### Requirement: Plain-text-only body renders on the white surface

A message with no HTML part renders through the reader's plain-text fallback branch
(`Text(email.body)` in `ReaderView`), which today styles the text with the themed
foreground `p.fg1` over the themed reader background `p.bg1` — so in the dark app theme it
is light-on-dark, NOT on a white surface. Because this branch does NOT pass through
`HTMLMessageView`, the white-surface fix above does NOT reach it automatically. The reader
SHALL therefore render the plain-text-only body on the same opaque pure-white surface, with
a fixed dark text color (so it reads dark-on-white in either app theme), decoupled from the
app theme. App chrome around the message stays themed. This change is confined to the
plain-text fallback branch and MUST NOT alter the HTML path or app chrome.

#### Scenario: Dark app, plain-text body is dark-on-white

- **GIVEN** the app is in the dark theme
- **AND** a message with NO HTML part (plain text only)
- **WHEN** it is opened in the reader
- **THEN** the body text renders dark on a white surface (not light text on the dark reader)
- **AND** the surrounding reader chrome remains themed

#### Scenario: Light app, plain-text body is unchanged in appearance

- **GIVEN** the app is in the light theme
- **WHEN** a plain-text-only message is opened
- **THEN** it renders as dark text on white, matching today's light-mode appearance

### Requirement: MIME parser captures each part's Content-ID

The MIME parser SHALL capture the `Content-ID` header of each leaf part during `walk`,
normalizing it by stripping the surrounding angle brackets (a `Content-ID: <image001@host>`
header SHALL be keyed as `image001@host`, matching the token used in `cid:image001@host`).
The captured CID SHALL be stored on the part's parse-time `MIME.Attachment` (a new optional
`contentID: String?` field on that in-memory struct), so it travels with the part's decoded
bytes and MIME type and is available for the post-parse referenced/unreferenced filtering.
This SHALL be additive: the existing text / HTML / calendar / attachment classification SHALL
be unchanged for parts without a Content-ID, and a message with no CID part SHALL produce the
same `Parsed` result as today. `MIME.Attachment` is in-memory only (never serialized), so
adding `contentID` carries no cache-schema risk.

#### Scenario: A related image part's Content-ID is captured

- **GIVEN** a `multipart/related` message with an image part `Content-ID: <logo@acme>`
- **WHEN** the message is parsed
- **THEN** that part's bytes are indexed under the CID token `logo@acme`
- **AND** its MIME type (e.g. `image/png`) is recorded with it

#### Scenario: A part with no Content-ID is unaffected

- **GIVEN** a normal attachment part with a filename and NO Content-ID header
- **WHEN** the message is parsed
- **THEN** it is classified exactly as today (appended to the attachment list)

#### Scenario: Edge case: message with no CID part parses identically

- **GIVEN** a plain `multipart/alternative` message (text + HTML, no related images)
- **WHEN** the message is parsed
- **THEN** the resulting text, HTML, attachments, calendar, and unsubscribe values are
  identical to the pre-feature parse

### Requirement: CID references resolve to inline images at render time

The reader SHALL resolve `<img src="cid:TOKEN">` references in the HTML body to the
matching embedded part, rewriting each to a `data:<mime>;base64,<...>` URI so the image
renders INLINE. This rewrite SHALL happen at RENDER time only; `MailCache` SHALL keep
storing the raw `cid:` HTML (never the base64-inlined form), so the on-disk cache is not
bloated. The rewrite SHALL be a pure function over (HTML string, CID→part map) returning
the rewritten HTML, unit-testable without a WebView. A `cid:` reference with no matching
part SHALL be left untouched (it renders as a broken image, exactly as an absent remote
image would — no crash, no fabrication).

#### Scenario: Inline logo renders in the body

- **GIVEN** a message whose HTML contains `<img src="cid:logo@acme">`
- **AND** the parser captured a part under `logo@acme` of type `image/png`
- **WHEN** the message is rendered
- **THEN** that `<img>`'s `src` is rewritten to `data:image/png;base64,...`
- **AND** the logo displays inline in the body

#### Scenario: Cache stores raw cid HTML, not base64

- **GIVEN** a message with an inline CID image has been loaded and cached
- **WHEN** the cached body is inspected
- **THEN** it still contains the literal `cid:` reference
- **AND** it does NOT contain the inlined `data:` base64 blob

#### Scenario: Multiple inline images in one message

- **GIVEN** a message whose HTML references three distinct `cid:` tokens, each with a
  matching embedded part
- **WHEN** the message is rendered
- **THEN** all three `<img>` references are rewritten to their respective `data:` URIs
- **AND** all three render inline

#### Scenario: Edge case: dangling cid reference

- **GIVEN** an `<img src="cid:missing@host">` whose token matches no embedded part
- **WHEN** the message is rendered
- **THEN** the reference is left unchanged
- **AND** rendering does not crash (the image shows as a broken box, as today)

### Requirement: Referenced inline parts are removed from the attachment list

A MIME part that is referenced by a `cid:` token in the HTML body SHALL be removed from
the attachment list (`Email.attachments`) shown to the user, so the same image is not
displayed twice (inline + as a downloadable attachment). A part that carries a Content-ID
but is NOT referenced by any `cid:` in the HTML SHALL remain a normal attachment.

This filtering SHALL be a SECOND pass over the fully-assembled parse result, NOT a decision
made inside `walk` (which cannot see sibling parts; in `multipart/related` the image part may
precede the HTML part). After `walk` collects every `MIME.Attachment` (each now carrying its
optional `contentID`) and the final HTML, the implementation SHALL drop the `MIME.Attachment`s
whose `contentID` is referenced by a `cid:` in that HTML, at or immediately before the
`MIME.Attachment → AttachmentMeta` promotion in `AppModel`. A referenced part therefore never
becomes an `AttachmentMeta` and never reaches the cache. The "is this part referenced by a
`cid:` in the HTML?" decision SHALL be a pure predicate over (HTML string, CID token),
unit-testable without a view.

#### Scenario: Inline-referenced image is not also an attachment

- **GIVEN** a message whose HTML references `cid:sig@acme` and whose embedded part has
  `Content-ID: <sig@acme>`
- **WHEN** the message is opened
- **THEN** the image renders inline
- **AND** it does NOT appear in the attachment list

#### Scenario: Content-ID present but unreferenced stays an attachment

- **GIVEN** an embedded part with `Content-ID: <orphan@acme>` that NO `cid:` in the HTML
  references
- **WHEN** the message is opened
- **THEN** that part appears in the attachment list as a normal attachment

#### Scenario: Edge case: very large inline image

- **GIVEN** a message with a multi-megabyte embedded image referenced inline by `cid:`
- **WHEN** the message is rendered
- **THEN** the image is rewritten to a `data:` URI and renders inline
- **AND** the size cost is borne at render time only (the cache still holds the raw
  `cid:` HTML, so on-disk size is unaffected)

### Requirement: Inline CID images render with remote images blocked

Because CID image bytes are embedded in the message and require no network request, inline
CID images SHALL render even when remote-image blocking is ON ("load images" off). The
reader's remote-block content rule (`blockRules`) uses `url-filter: ".*"` over image and
other resource types. The implementation SHALL ensure that rule does NOT suppress
`data:`-URI images. Either outcome is acceptable: (a) the `.*` filter is found NOT to match
`data:` URIs (so inline CID images render natively with no carve-out — confirmed by live
test); OR (b) the `.*` filter is found to match `data:` URIs, in which case a `data:`-allow
carve-out (an `ignore-previous-rules` allow for the `data:` scheme, analogous to the
existing proxy-origin allow rule built by `proxyAllowRules(for:)`) SHALL be added so they
render. The carve-out is mandatory ONLY if the build-time test shows the `.*` rule blocks
`data:`. This MUST be verified against WKWebView behavior at build time; neither outcome is
asserted as settled in advance.

#### Scenario: CID image shows with load-images off

- **GIVEN** remote-image blocking is ON ("load images" off)
- **AND** a message with an inline `cid:` image
- **WHEN** the message is opened
- **THEN** the inline image renders
- **AND** any genuinely remote `http(s)` images remain blocked

#### Scenario: Edge case: block rule must not catch data: URIs

- **GIVEN** the remote-block content rule (`url-filter: ".*"`) is installed
- **WHEN** a `data:image/...;base64,...` resource loads
- **THEN** it is NOT blocked (verified against WKWebView; a `data:`-scheme allow carve-out
  is added if the `.*` filter would otherwise catch it)

## Success Criteria

- **SC-001**: In the dark app theme, opening a real message with a white-background
  signature table renders the whole body on one continuous white surface with no white
  island and no unreadable dark-on-dark text — confirmed by live verification against the
  mailbox.org account (manual exploration).
- **SC-002**: In the light app theme, HTML messages render identically to before the change
  — confirmed by live visual comparison.
- **SC-003**: A real message with a `multipart/related` signature logo renders the logo
  inline AND does not show it as a downloadable attachment — confirmed by live
  verification, including with "load images" turned OFF (the embedded image still renders).
- **SC-004**: A message whose part has a Content-ID but is unreferenced by any `cid:` still
  appears as a normal attachment — confirmed by live verification or unit test.
- **SC-005**: The pure seams are covered by tests in `MMailTests` that pass under the
  project's Swift test runner: (a) the wrapped-`<head>` builder emits `color-scheme: only
  light` and an opaque white background; (b) the CID→`data:`-URI rewrite over an HTML
  string + CID map rewrites matching refs and leaves dangling refs untouched; (c) the
  "is part referenced by a `cid:` in the HTML" predicate returns true only for referenced
  tokens. type-driven structuring + opposite-model review are always-on per `.harness.yaml`.
- **SC-006**: Inspecting the cached body of a CID-image message shows it still contains the
  raw `cid:` reference and no inlined base64 — confirmed by unit test or manual inspection.
- **SC-007**: The `data:`-URI / content-rule interaction is resolved by build-time
  verification against WKWebView, and inline CID images render with remote blocking on while
  remote `http(s)` images stay blocked, via EITHER branch: (a) the `blockRules` `.*` filter
  does NOT match `data:` URIs and inline CID images render with no carve-out; OR (b) the
  `.*` filter DOES match `data:` and a `data:`-scheme `ignore-previous-rules` carve-out is
  added and they render. The branch is determined empirically at build time, not assumed.
- **SC-008**: A plain-text-only message opened in the dark app theme renders its body as
  dark text on a white surface (not light-on-dark) — confirmed by live verification; the
  HTML path and light-mode appearance are unchanged.
- **SC-009**: A cache written before this feature decodes without error after the change: no
  cache-serialized type (`Email`, `AttachmentMeta`) gains a non-optional stored property, so
  existing `MailCache` JSON still loads (the inline-image filtering is applied at promotion,
  leaving `AttachmentMeta` unchanged) — confirmed by a decode test over a pre-feature cache
  fixture or by inspection that no required key was added.

## Non-Goals

- **No dark-transform / theming engine for email bodies.** We do NOT build a CSS rewriter,
  a luminance-inverting transform, or a per-message light/dark heuristic to make bodies
  "match" the dark app theme. The locked decision is a single always-white surface; a smart
  dark-mode email transform is explicitly out of scope. (This exclusion does NOT touch the
  inline CID-image fix above, which is in scope.)
- No off-white / tinted reader surface and no inset "card" framing of the message
  (rejected alternatives): the surface is full-bleed pure white filling the pane.
- No keeping inline CID images in the attachment list "just in case" (rejected): a part
  referenced inline is dropped from attachments to avoid double display, matching MailMate.
- No persisting the rewritten `data:`-URI HTML to `MailCache` (rejected): the cache holds
  the raw `cid:` HTML; rewriting is render-time only.
- No handling of inline images referenced by means other than `cid:` (e.g. external
  `http(s)` images), and no change to the remote-image proxy/signing path — those are
  governed by the existing image-privacy features.
- No change to MIME parsing for messages without CID parts, to body-completeness, to the
  WebView height/scroll measurement, or to which messages are fetched.
- No new user setting to toggle the white surface or inline-image behavior — both are the
  fixed correct behavior.
