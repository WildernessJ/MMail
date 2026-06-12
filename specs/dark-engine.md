# dark-engine Specification

## Purpose

The reader SHALL render an email body in a native-dark theme — dark backgrounds,
light text, with images and brand colors preserved — when the app is in dark mode, so a
message is no longer a bright white rectangle in an otherwise-dark app. This is the
Gmail/Outlook "dark mode email" look. It builds directly on the shipped
`reader-render-fidelity` feature, which renders every body on a forced PURE-WHITE surface
(`ReaderHTML.wrappedDocument(_:)` at `MMail/Mail/CIDInlining.swift:32`) regardless of theme;
that white surface remains the substrate, and this feature transforms it in-page when
`model.dark == true`.

The chosen approach is to **vendor the DarkReader engine** (MIT,
https://github.com/darkreader/darkreader) as a bundled app resource and run it IN-PAGE inside
the existing `WKWebView` (`HTMLMessageView`, `MMail/Views/HTMLMessageView.swift:47`): after a
body loads, the app calls `DarkReader.enable(theme)` once, which reads each element's computed
style and intelligently darkens backgrounds / lightens text while leaving images intact. We do
NOT hand-roll a DOM-walker or a naive CSS `invert()+hue-rotate()` transform — that inferior
fallback is an escalation option only, never an automatic substitute. The transform is purely
visual, in-page, and local: it issues no network request and does not touch the
privacy/remote-block/proxy/CID paths. A per-message, session-scoped "Show original" escape
hatch reverts THIS message to the white surface, mirroring the existing `loadImages` `@State`
toggle. Because the plain-text-only body does NOT flow through the WebView, it gets its own
SwiftUI dark treatment so it does not stay a white rectangle in dark mode.

## Invariants

- The dark transform MUST apply to a message body ONLY when `model.dark == true`
  (`MMail/State/AppModel.swift:124`, applied via `.preferredColorScheme(model.dark ? .dark :
  .light)` at `MMail/MMailApp.swift:12`) AND that message is NOT in per-message "Show original"
  state. In LIGHT mode (`model.dark == false`) the render path MUST be byte-identical to today's
  shipped behavior (the forced white surface from `reader-render-fidelity`) — no engine, no
  injected script, no behavioral change. ("App is dark" == `model.dark == true`; no
  System/Light/Dark auto-follow exists — see Non-Goals.)
- The transform MUST be purely visual and in-page: a CSS restyle layered over the
  already-loaded DOM. It MUST NOT issue ANY network request. The existing remote-block /
  image-proxy / `^data:` carve-out content rules (`HTMLMessageView.blockRules` at
  `MMail/Views/HTMLMessageView.swift:105`, `proxyAllowRules(for:)` at `:134`) MUST be UNTOUCHED.
  The vendored `darkreader.js` MUST be loaded from `Bundle.main` (a local app resource), never
  fetched remotely, and DarkReader's dynamic theme MUST be local-only (no remote calls).
- The white-surface base document (`ReaderHTML.wrappedDocument`, `MMail/Mail/CIDInlining.swift:32`,
  consumed by `HTMLMessageView.wrapped` at `MMail/Views/HTMLMessageView.swift:80`) MUST remain
  the substrate. The engine transforms that document IN-PAGE after load. The dark theme MUST be
  a single fixed dark palette (background near the app's dark surface, approximately `#1A1A1A`;
  light text). NO user theme customization and NO multiple dark themes.
- Inline CID images (rewritten to self-contained `data:` URIs by
  `ReaderHTML.inlineCIDImages(inHTML:parts:)`, `MMail/Views/ReaderView.swift:330`) AND
  remote-proxied images MUST still render correctly under the transform. DarkReader's
  image-preservation behavior SHALL be confirmed live per SC-003/SC-004; if embedded logos /
  brand images are inverted or wrecked, the engine is treated as infeasible for our purpose and
  escalates per the feasibility requirement. Preserving images is the explicit point of
  `reader-render-fidelity`.
- "Show original" MUST be per-message and session-scoped. It MUST be a new
  `@State private var showOriginal = false` on `ReaderContent` (`MMail/Views/ReaderView.swift:36`),
  resetting to `false` whenever a different message is opened — this is automatic because
  `ReaderView` keys the content view with `.id(email.id)` (`MMail/Views/ReaderView.swift:12`),
  which forces a fresh `ReaderContent` per message (the same mechanism that resets `loadImages`
  at `:48`). Toggling it ON reverts THIS message to the white surface; toggling it OFF
  re-darkens. It MUST NOT persist across sessions or across messages.
- State changes MUST re-render correctly. Toggling app dark↔light, or toggling
  "Show original", MUST update the rendered body to the correct visual AND height result. The
  dark-apply decision MUST be threaded into `HTMLMessageView` as a NEW input the view observes;
  the plan picks the exact re-render mechanism, which MAY be EITHER: (a) an in-place JS toggle
  via `evaluateJavaScript` (`DarkReader.enable()` / `DarkReader.disable()`) on the
  already-loaded page — preferred, no reload flash, but height MUST then be re-measured after
  the toggle; OR (b) a full reload via the existing change-detection in `updateNSView`
  (`MMail/Views/HTMLMessageView.swift:68`), extending `lastHTML`/`lastBlock`/`lastProxyConfig`
  so a change in the dark-apply decision re-runs the load/transform exactly as an
  `html`/`blockRemote`/`proxyConfig` change does today (acceptable, but incurs a reload/flash
  on each toggle).
- The content-height measurement (`evaluateJavaScript("document.body.scrollHeight")` in
  `webView(_:didFinish:)` at `MMail/Views/HTMLMessageView.swift:197`) MUST reflect the
  TRANSFORMED DOM. Today `didFinish` measures height immediately on load completion; that
  direct measure runs BEFORE any DarkReader transform. When the dark engine applies, the
  load-completion path MUST be modified to sequence inject→`enable()`→measure: inject
  `darkreader.js` and call `DarkReader.enable(theme)` FIRST, and re-measure
  `document.body.scrollHeight` only inside that injection-completion path (superseding the
  unconditional immediate `didFinish` measure), so a layout shift from darkening does not leave
  a stale/wrong height. When the engine does NOT apply (light mode / "Show original"), the
  immediate `didFinish` measure stays today's path unchanged.
- NO cache-schema change. The transform is render-time only. NO new stored property may be
  added to any `Codable` cache-serialized type (`Email`, `AttachmentMeta`). A cache written
  before this feature MUST still decode (`MailCache` uses a bare `JSONDecoder` over the whole
  `[Email]` array — a non-optional new key would discard the entire cached folder).
- The plain-text-only body (`ReaderView.swift:335-349`, native SwiftUI `Text(email.body)`,
  NOT a WebView) MUST render dark (dark surface + light text) when `model.dark == true` AND
  "Show original" is off, consistent with the HTML dark look. In light mode (or under "Show
  original") it MUST be unchanged (dark-on-white, as `reader-render-fidelity` shipped).
- JavaScript execution risk is UNCHANGED. JS is already enabled in the WebView (the height
  measure depends on it; inline `<script>` in email HTML already runs — content rules block only
  REMOTE script *resources*). Injecting the engine introduces NO new JS-execution risk class,
  and this feature MUST NOT add the separate "disable the email's own inline JS" hardening.

## Requirements

### Requirement: Engine feasibility is proven before the UI is built

The build SHALL begin with a feasibility spike that empirically proves the vendored DarkReader
engine works inside this app's WebView BEFORE any user-facing UI (toggle, plain-text path,
reactivity wiring) is built on top of it. The spike SHALL vendor `darkreader.js` as a bundled
resource (under `MMail/Resources/`, auto-bundled by XcodeGen's recursive `sources: - path: MMail`;
adding the new file requires running `xcodegen generate` once and committing the regenerated
`MMail.xcodeproj/project.pbxproj`), load it from `Bundle.main`, inject it into a real
already-loaded email body, call `DarkReader.enable(theme)`, and CONFIRM a real email visibly
darkens (dark background, light text, images intact) in the live app. Two co-equal cruxes are
de-risked. FIRST: the HTML loads with `baseURL: nil` (an `about:blank` origin), so the engine +
its injection + the existing height measure MUST sequence correctly over that origin. SECOND:
the base document `ReaderHTML.wrappedDocument` emits `:root { color-scheme: only light; }` (a
load-bearing part of `reader-render-fidelity` that suppresses WebKit auto-darkening). DarkReader
reads/replaces computed styles, so `color-scheme: only light` may make it short-circuit (skip a
document it sees as light-only) OR override its injected dark styles. The spike MUST confirm the
engine darkens a real email WITH `color-scheme: only light` left intact. If the engine only works
by altering/removing `wrappedDocument`'s `color-scheme`, that is NOT a silent change: it MUST
preserve light-mode byte-identical behavior (re-verifying `reader-render-fidelity`) or escalate
per the feasibility outcome below.

The outcome SHALL be handled honestly: if the spike CONFIRMS feasibility, the build proceeds. If
the spike proves the engine INFEASIBLE in this WebView, the build SHALL HALT and ESCALATE to the
user for a decision. The known lower-quality fallback (a CSS `filter: invert(1) hue-rotate(180deg)`
with image re-inversion) does NOT meet the chosen native-dark bar, so it is NOT an automatic
fallback — it is one option presented at escalation, applied only with explicit user sign-off.

#### Scenario: Spike confirms the engine darkens a real email

- **GIVEN** `darkreader.js` is vendored as a bundled resource and loaded from `Bundle.main`
- **AND** a real HTML email body has loaded in the WebView (with `baseURL: nil`)
- **AND** the base document retains `color-scheme: only light`
- **WHEN** the engine is injected and `DarkReader.enable(theme)` is called
- **THEN** the email visibly renders dark (dark background, light text) in the live app
- **AND** embedded images are not color-inverted or wrecked
- **AND** the build proceeds to the UI work

#### Scenario: Edge case: spike proves the engine infeasible

- **GIVEN** the feasibility spike cannot make the engine darken a real email in this WebView
- **WHEN** the infeasibility is observed
- **THEN** the build HALTS and escalates to the user with the finding
- **AND** the inferior CSS-filter approach is NOT applied automatically as a fallback
- **AND** no UI is built on the unproven engine

### Requirement: HTML body renders native-dark in dark mode

The reader SHALL apply the DarkReader dark transform to the HTML email body IN-PAGE when
`model.dark == true` AND the message's "Show original" state is off. The transform SHALL run over
the existing white-surface substrate (`ReaderHTML.wrappedDocument`) after the body loads, producing
a dark background near `#1A1A1A` with light text while preserving images and brand colors. In light
mode, OR when "Show original" is on, the engine SHALL NOT run and the render SHALL be the shipped
white surface. The transform SHALL NOT issue any network request and SHALL NOT alter the
remote-block / proxy / `data:` content rules. The decision "should the dark engine apply to this
render?" (`model.dark && !showOriginal`) SHALL be a pure predicate, unit-testable without a WebView
host. If an injection-script / theme-config string is built, that builder SHALL also be a pure
function unit-testable without a WebView.

#### Scenario: Dark app, white-background newsletter goes dark

- **GIVEN** the app is in dark mode (`model.dark == true`) and "Show original" is off
- **AND** a newsletter whose body assumes a white page (light background, dark text)
- **WHEN** the message is opened in the reader
- **THEN** the body renders with a dark background and light, readable text
- **AND** no network request is issued by the transform

#### Scenario: Dark app, brand colors and images preserved

- **GIVEN** the app is in dark mode and "Show original" is off
- **AND** a brand-colored marketing email with logos and colored call-to-action buttons
- **WHEN** the message is opened
- **THEN** the background darkens and text lightens
- **AND** brand colors and images remain recognizable (not inverted or washed out)

#### Scenario: Light app behavior is unchanged

- **GIVEN** the app is in light mode (`model.dark == false`)
- **WHEN** any HTML message is opened
- **THEN** it renders exactly as it does today (the shipped white surface, sender's colors intact)
- **AND** the engine is not injected and no transform runs

#### Scenario: Edge case: embedded signature logo is not inverted

- **GIVEN** the app is in dark mode and "Show original" is off
- **AND** a message with an inline `cid:` signature logo (an ETHS-style signature image)
- **WHEN** the message is opened
- **THEN** the body darkens but the signature logo renders with correct colors (NOT inverted)
- **AND** the logo still renders even with remote-image blocking on (it is an embedded `data:` URI)

### Requirement: Per-message "Show original" reverts to the white surface

The reader SHALL provide a per-message, session-scoped "Show original" control that reverts THIS
message to the shipped white surface. It SHALL be a new `@State private var showOriginal = false` on
`ReaderContent` (`MMail/Views/ReaderView.swift:36`), inheriting the per-message reset already
provided by `.id(email.id)` (`MMail/Views/ReaderView.swift:12`) — exactly the session-scoped,
per-message semantics of the existing `loadImages` `@State` (`:48`). Toggling it ON SHALL revert the
body to the white surface (no dark transform); toggling it OFF SHALL re-darken (when `model.dark`).
It SHALL NOT persist across app sessions, and it SHALL reset when a different message is opened.

#### Scenario: Show original reverts a darkened message to white

- **GIVEN** the app is in dark mode and a message is rendering native-dark
- **WHEN** the user activates "Show original" for that message
- **THEN** the body reverts to the white surface (white background, dark text)
- **AND** toggling it back off re-darkens the same message

#### Scenario: Show original resets when a different message is opened

- **GIVEN** "Show original" is active on message A in dark mode
- **WHEN** the user opens a different message B
- **THEN** message B renders native-dark (Show original is reset to off for B)
- **AND** re-opening A also renders native-dark (the state did not persist for A)

#### Scenario: Edge case: Show original in light mode is a no-op visual change

- **GIVEN** the app is in light mode
- **WHEN** "Show original" is toggled
- **THEN** the body remains on the white surface either way (light mode never darkens)
- **AND** no engine is injected in either state

### Requirement: State changes re-render the body correctly

The reader SHALL re-render the body when the dark-apply decision changes. Toggling app
dark↔light, or toggling "Show original", SHALL update the rendered body to the correct visual
AND height result. The dark-apply decision SHALL be threaded into `HTMLMessageView` as a NEW
input the view observes; the plan picks the exact re-render mechanism, which MAY be EITHER (a)
an in-place JS toggle via `evaluateJavaScript` (`DarkReader.enable()` / `DarkReader.disable()`)
on the already-loaded page — preferred, no reload flash, but height MUST then be re-measured
after the toggle — OR (b) a full reload via the existing `lastHTML`/`lastBlock`/`lastProxyConfig`
change detection in `updateNSView` (`MMail/Views/HTMLMessageView.swift:68`), extended so a change
in that input re-runs the load/transform exactly as an `html`/`blockRemote`/`proxyConfig` change
does today (acceptable, but incurs a reload/flash per toggle).

The content-height measurement (`document.body.scrollHeight` at
`MMail/Views/HTMLMessageView.swift:197`) SHALL reflect the TRANSFORMED DOM. Today
`webView(_:didFinish:)` measures height immediately on load completion, BEFORE any transform;
when the dark engine applies, that load-completion path SHALL be modified to sequence
inject→`enable()`→measure (inject `darkreader.js` and call `DarkReader.enable(theme)` FIRST,
then re-measure `scrollHeight` inside the injection-completion path, superseding the immediate
`didFinish` measure). Whichever re-render mechanism the plan picks, height SHALL be re-measured
AFTER the transform settles, so a layout shift from darkening does not leave a stale height. In
light mode / "Show original", the immediate `didFinish` measure is today's path unchanged.

#### Scenario: Toggling app dark to light re-renders without darkening

- **GIVEN** a darkened HTML message is open in dark mode
- **WHEN** the user switches the app to light mode
- **THEN** the same message re-renders on the white surface (no transform)
- **AND** switching back to dark re-darkens it

#### Scenario: Height reflects the transformed DOM

- **GIVEN** a message whose darkened layout differs in height from its white-surface layout
- **WHEN** the message renders native-dark
- **AND** `DarkReader.enable(theme)` has been injected and run BEFORE the height is measured
  (the load-completion path measures `scrollHeight` only after the transform settles)
- **THEN** the measured `scrollHeight` reflects the transformed (darkened) DOM
- **AND** the body is not visually clipped or left with excess blank space

### Requirement: Plain-text-only body renders dark in dark mode

A message with no HTML part renders through the reader's plain-text branch
(`MMail/Views/ReaderView.swift:335-349`), native SwiftUI `Text(email.body)` styled with the fixed
dark text color `ReaderHTML.bodyTextColor` on `.background(.white)` — which does NOT pass through
`HTMLMessageView`, so DarkReader cannot reach it. The reader SHALL therefore give this branch its
OWN SwiftUI dark treatment: when `model.dark == true` AND "Show original" is off, it SHALL render
on a dark surface (approximately `#1A1A1A`) with light text, consistent with the HTML dark look. In
light mode, OR under "Show original", it SHALL remain dark-on-white (as `reader-render-fidelity`
shipped). This change is confined to the plain-text branch and MUST NOT alter the HTML path or the
surrounding themed reader chrome.

#### Scenario: Dark app, plain-text body is light-on-dark

- **GIVEN** the app is in dark mode and "Show original" is off
- **AND** a message with NO HTML part (plain text only)
- **WHEN** it is opened
- **THEN** the body renders as light text on a dark surface (consistent with the HTML dark look)
- **AND** the surrounding reader chrome remains themed

#### Scenario: Light app, plain-text body is unchanged

- **GIVEN** the app is in light mode
- **WHEN** a plain-text-only message is opened
- **THEN** it renders as dark text on white, matching today's shipped appearance

#### Scenario: Show original reverts plain-text to dark-on-white

- **GIVEN** the app is in dark mode and a plain-text body is rendering light-on-dark
- **WHEN** "Show original" is activated
- **THEN** the plain-text body reverts to dark-on-white

### Requirement: No cache-schema change and no privacy-path change

The dark transform SHALL be render-time only. NO stored property SHALL be added to any
cache-serialized type (`Email`, `AttachmentMeta`); a cache written before this feature SHALL still
decode. The feature SHALL NOT change which messages are fetched, the body-completeness contract, the
remote-block / image-proxy / `^data:` carve-out content rules, the CID-inlining path, or the WebView
height/scroll plumbing beyond reading the transformed DOM's height.

#### Scenario: Pre-feature cache still decodes

- **GIVEN** a `MailCache` JSON written before this feature
- **WHEN** the app loads it after the change
- **THEN** it decodes without error (no new required key was added)
- **AND** no cache-serialized type gained a non-optional stored property

#### Scenario: Privacy content rules are untouched

- **GIVEN** a dark-mode message with remote images blocked
- **WHEN** the body renders native-dark
- **THEN** genuinely remote `http(s)` resources remain blocked
- **AND** the transform issues no network request of its own

## Success Criteria

- **SC-001**: A feasibility spike vendors `darkreader.js`, injects it, calls `DarkReader.enable`,
  and confirms a real email darkens live in the app (dark background, light text, images intact)
  BEFORE any UI is built — confirmed by live verification. If the spike proves infeasible, the build
  halts and escalates to the user; the inferior CSS-filter approach is NOT applied automatically.
- **SC-002**: In dark mode, opening a real white-background newsletter renders the body dark
  (dark background, readable light text) — confirmed by live verification against the mailbox.org
  account (manual exploration).
- **SC-003**: In dark mode, a brand-colored marketing email and an image-heavy email both darken
  while keeping brand colors and images recognizable (not inverted/wrecked) — confirmed by live
  verification across both message types.
- **SC-004**: In dark mode, the real ETHS-style signature-logo email darkens but the inline `cid:`
  logo renders with correct (non-inverted) colors, including with "load images" OFF — confirmed by
  live verification.
- **SC-005**: In light mode, HTML messages render identically to before the change (the shipped
  white surface) — confirmed by live visual comparison (mirrors `reader-render-fidelity` SC-002).
- **SC-006**: "Show original" reverts the open message to the white surface and toggling it back
  re-darkens; the state resets when a different message is opened and does not persist across
  sessions — confirmed by live verification.
- **SC-007**: Toggling app dark↔light re-renders the open body correctly (dark→white→dark), and the
  measured `scrollHeight` reflects the transformed DOM with no clipping or excess blank space —
  confirmed by live verification.
- **SC-008**: A plain-text-only message opened in dark mode renders light text on a dark surface
  (consistent with the HTML dark look), and in light mode (or under "Show original") it stays
  dark-on-white — confirmed by live verification.
- **SC-009**: The transform issues no network request and leaves the remote-block / proxy / `data:`
  content rules unchanged — confirmed by live verification (remote images stay blocked when blocking
  is on) plus inspection that `HTMLMessageView.blockRules` / `proxyAllowRules` are untouched.
- **SC-010**: A cache written before this feature decodes without error after the change: no
  cache-serialized type (`Email`, `AttachmentMeta`) gains a non-optional stored property — confirmed
  by a decode test over a pre-feature cache fixture or by inspection that no required key was added.
- **SC-011**: The pure seams are covered by tests in `MMailTests` that pass under the project's
  Swift test runner: (a) the "should the dark engine apply?" predicate returns true only when
  `model.dark && !showOriginal`; (b) if an injection-script / theme-config string builder exists, it
  emits the expected fixed-dark-palette configuration over its inputs. type-driven structuring +
  manual exploration + opposite-model review are always-on per `.harness.yaml`.

## Non-Goals

- **No System/Light/Dark auto-follow.** This keys off the existing `model.dark` bool
  (`MMail/State/AppModel.swift:124`) only. A System/Light/Dark auto-follow control is a separate,
  deferred feature.
- **No auto-fallback to the inferior CSS-filter approach.** If the engine proves infeasible, the
  build escalates to the user; a `filter: invert(1) hue-rotate(180deg)` (+ image re-inversion)
  transform is NOT applied without explicit user sign-off.
- **No persistence of "Show original."** It is per-message and session-scoped only — no per-message
  or per-sender persistence across sessions, and no global setting to disable the engine (out of
  scope unless trivially free).
- **No theme customization and no multiple dark themes.** The dark palette is a single fixed theme
  (background approximately `#1A1A1A`, light text). No user color controls.
- **No change to privacy / remote-block / image-proxy / CID paths, to which messages are fetched,
  or to body-completeness.** The transform is local, in-page, and render-time only.
- **No hand-rolled DOM-walker or color-science reimplementation.** The vendored DarkReader engine
  is the chosen approach; we do not reinvent it.
- **No "disable the email's own inline JS" hardening.** Inline email JS already runs today; this
  feature introduces no new JS-execution risk class and explicitly does not add that separate
  hardening.
