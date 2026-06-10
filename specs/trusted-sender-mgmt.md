# Trusted-Sender Management Specification

## Purpose

The app SHALL let the user VIEW and REMOVE the senders whose remote images load automatically (the "trusted-image" set), under a SINGLE shared address-normalization rule used identically by ADD (the reader's "Always" button), CONTAINS (`isImageTrusted`, the reader's auto-load gate), REMOVE (Settings "Stop"), and LISTING (the Settings list) — so that an entry the user sees and removes corresponds EXACTLY to the entry `isImageTrusted` consults, and revoking trust in Settings genuinely stops the reader from auto-loading that sender's images. A Settings "Remote images" list with a per-entry "Stop" control already exists (`SettingsView.swift:233-249`), backed by `AppModel.untrustImages` (`AppModel.swift:880-883`); the MVP's substantive change is to make trust membership *consistent* by routing add/contains/remove/list through one canonical normalization (today they use divergent rules — see Invariants), and to give the list a non-conditional presence with an empty-state so the user can always reach it to audit/revoke.

The remove path is NOT broken today. `untrustImages` (`AppModel.swift:880-883`) has exactly one call site — `SettingsView.swift:241` — and the `addr` it receives is always already a canonical member of `model.trustedImageSenders.sorted()` (`SettingsView.swift:235`), so its `lowercased()` is a no-op on input that is already canonical and the remove ALWAYS succeeds. The actual defect is the **add→contains divergence**: `trustImages` (add, `AppModel.swift:873-878`) normalizes with `lowercased()` + `.whitespaces` trim, while `isImageTrusted` (contains, `AppModel.swift:868-871`) does `lowercased()` ONLY; and after a relaunch, persisted entries are reloaded through `normalizeAddress` (`AppModel.swift:267-268`), which strips `<>`, while `isImageTrusted` does not — so a whitespace-padded or angle-bracketed address can be trusted-but-not-honored (or honored in-session but not after relaunch). The severity here is **defensive normalization cleanup / future-proofing**, not "trust can't be reliably revoked today": `IMAPService.swift:608` builds `fromEmail` as a clean `mailbox@host` (no angle brackets, no surrounding whitespace) straight from the parsed IMAP envelope, so the divergence is currently mostly unreachable edge-case input. The unification is correct and cheap defense-in-depth; the more user-visible improvement is the always-visible audit section that lets the user reach the revoke surface even before any sender is trusted.

## Invariants

- **One normalization, four operations.** ADD, CONTAINS, REMOVE, and the canonical form stored in the set MUST all apply the SAME pure normalization to an address before comparing or storing it. The set membership that `isImageTrusted` consults MUST be exactly the set the Settings list renders and "Stop" removes from, under that one rule. This is the central consistency invariant: removing a listed entry MUST revoke precisely what the reader's auto-load gate checks, with no case/whitespace/angle-bracket variant left un-removable or un-checkable. (Note on today's state: REMOVE is not actually broken — its sole call site, `SettingsView.swift:241`, always passes an already-canonical Set member — but routing it through the one rule keeps the four operations correct by construction regardless of future call sites.)
- **Canonical store form = `AppModel.normalizeAddress`.** The chosen rule MUST be the existing `AppModel.normalizeAddress` (`AppModel.swift:801-807`): lowercase → trim `.whitespacesAndNewlines` → strip leading/trailing `<>` → re-trim → nil if empty. This is ALREADY the form persisted entries are loaded back as (`AppModel.swift:267-268` maps stored strings through `normalizeAddress`), so it is the form actually living in `trustedImageSenders` after a relaunch. Picking it as the canonical rule makes the in-memory set and the on-disk-reloaded set identical, and avoids inventing a fourth normalization.
- **Fix the existing divergence.** Today the operations use different rules and MUST be reconciled to the canonical rule as part of this feature: ADD `trustImages` uses `lowercased() + trimmingCharacters(in: .whitespaces)` (plain whitespace only, NOT newlines; no `<>` strip) and requires `@` (`AppModel.swift:873-878`); CONTAINS `isImageTrusted` uses `lowercased()` ONLY — no trim, no `<>` strip (`AppModel.swift:868-871`); REMOVE `untrustImages` also uses `lowercased()` ONLY (`AppModel.swift:880-883`), but harmlessly so today since its only caller hands it a canonical Set member. The reachable defect is the **add→contains divergence**. Because `isImageTrusted(email.fromEmail)` (`ReaderView.swift:290`) and `trustImages(sender?.email)` (`ReaderView.swift:305`) both start from the SAME raw `fromEmail` string (`sender.email == fromEmail ?? ""`, `Models.swift:101`), an address carrying surrounding whitespace is STORED trimmed by add but CHECKED untrimmed by contains → the trust silently never applies; an angle-bracket form (`<a@b.com>`) is stored verbatim by add but, after relaunch, matched against a `<>`-stripped reload form (`AppModel.swift:267-268`) → mismatch. In practice this is edge-case input: `fromEmail` is built clean as `mailbox@host` (`IMAPService.swift:608`), so the divergence is mostly unreachable and the fix is defense-in-depth, not an active-bug rescue. Reconciling all four operations to `normalizeAddress` closes both holes by construction.
- **Pure core, no I/O.** The list/add/remove/contains/normalize OPERATIONS MUST be expressed as a PURE, injectable core over plain values (a `Set<String>` / `[String]` and `String` addresses) with NO `UserDefaults`, Keychain, AppModel, or WebKit access inside it — mirroring the `ReaderImageLoadState` / `ProxyConfigState` house pattern (`ReaderImageLoadState.swift:108-117`). The impure `AppModel` methods become thin wrappers: normalize via the core, mutate `trustedImageSenders`, persist to `UserDefaults`. All purity-proving unit tests target the core.
- **Listing is deterministic.** The listed view MUST be sorted lexicographic ascending on the canonical string (Swift `Array.sorted()` default `<` on the normalized `String` — NOT domain-then-local-part or any other key) and de-duplicated — a function of the set's canonical members only, stable across calls. (The set is already de-duplicated by construction; canonical normalization guarantees no two members differ only by case/whitespace.)
- **Remove is idempotent and total.** Removing an address NOT in the set MUST be a no-op (no crash, no spurious persist-need beyond the unchanged set). Removing the last entry MUST leave an empty set, not an error.
- **Display-only reads.** Viewing the list MUST NEVER trigger a remote fetch, mint a proxy URL, read/write the signing secret, or alter any image-load path. Removing an entry mutates ONLY `trustedImageSenders` (+ its `UserDefaults` persistence); it changes no proxy/secret state.
- **No secret/credential exposure.** This feature touches only sender email addresses (already user-visible in the reader). It MUST NEVER render or log the proxy signing secret, Keychain material, or account passwords.

## Requirements

### Requirement: One canonical normalization shared by add, contains, remove, and storage

The trusted-set core SHALL expose a single pure normalization that lowercases, trims `.whitespacesAndNewlines`, strips leading/trailing `<>`, re-trims, and yields nil for an empty result — identical to `AppModel.normalizeAddress` (`AppModel.swift:801-807`). `AppModel.trustImages`, `AppModel.isImageTrusted`, and `AppModel.untrustImages` SHALL each normalize their input through this one rule before insert / contains / remove, so the three operations agree by construction.

#### Scenario: Add and contains agree on a whitespace-bearing address

- **GIVEN** the raw `fromEmail` is `"  Sender@Example.COM  "` (surrounding whitespace, mixed case)
- **WHEN** the user taps "Always" (add) and the reader later checks `isImageTrusted("  Sender@Example.COM  ")`
- **THEN** the address is stored as the canonical `"sender@example.com"`
- **AND** `isImageTrusted` returns true for the same raw input (today it returns FALSE — contains does not trim, so the stored trimmed form misses)

#### Scenario: Add and contains agree on an angle-bracket address

- **GIVEN** the raw `fromEmail` is `"<a@b.com>"`
- **WHEN** the sender is trusted and then re-checked via `isImageTrusted("<a@b.com>")`
- **THEN** the stored member is canonical `"a@b.com"`
- **AND** `isImageTrusted` returns true (matching the form the set holds after a relaunch reload, which strips `<>`)

#### Scenario: Remove matches the canonical stored form

- **GIVEN** the set contains the canonical member `"a@b.com"` (however it was originally typed/added)
- **WHEN** the core removes `"a@b.com"` (or any case/whitespace/angle-bracket variant that normalizes to it)
- **THEN** the member is gone from the set
- **AND** a subsequent `isImageTrusted` for that sender returns false

#### Scenario: Edge case: a variant that only differs by case/whitespace is the SAME entry

- **GIVEN** the set contains `"a@b.com"`
- **WHEN** the core is asked to add `"A@B.COM"` or `" a@b.com "`
- **THEN** the set still has exactly one member `"a@b.com"` (no duplicate)
- **AND** removing `"A@B.COM"` removes that single member

#### Scenario: Edge case: a non-address input is rejected on add

- **GIVEN** an input with no `@` (e.g. `"not-an-email"`) or one that normalizes to empty (e.g. `"   "` or `"<>"`)
- **WHEN** the core add runs
- **THEN** the set is unchanged (nothing inserted) — preserving today's `guard e.contains("@")` behavior (`AppModel.swift:875`)

### Requirement: Deterministic listing for the Settings view

The trusted-set core SHALL produce a sorted, de-duplicated `[String]` of the canonical members for display, a pure function of the set's contents. The Settings "Remote images" list SHALL render this list (it already sorts via `model.trustedImageSenders.sorted()`, `SettingsView.swift:235`, and keys `ForEach` by `\.element`).

#### Scenario: Listing is sorted and deduplicated

- **GIVEN** the set `{"c@x.com", "a@x.com", "b@x.com"}`
- **WHEN** the core lists it
- **THEN** the result is `["a@x.com", "b@x.com", "c@x.com"]` (ascending)

#### Scenario: Edge case: empty set lists as empty

- **GIVEN** the set is empty
- **WHEN** the core lists it
- **THEN** the result is `[]` (no crash, no placeholder member)

### Requirement: Remove one trusted sender (revoke trust)

`AppModel.untrustImages(addr)` SHALL remove the address (after canonical normalization) from `trustedImageSenders`, persist the updated set to `UserDefaults` under `kTrustedImages`, and take effect on the reader's NEXT render of any message from that sender (which re-evaluates `isImageTrusted`). Removal SHALL require no confirmation modal (MVP: immediate). Removing an address not present SHALL be a no-op.

#### Scenario: Removing a trusted sender stops auto-loading its images

- **GIVEN** `"news@shop.com"` is in `trustedImageSenders` (so the reader auto-shows its images)
- **WHEN** the user taps "Stop" next to that entry in Settings
- **THEN** `"news@shop.com"` is removed from the set and the change is persisted
- **AND** the next time a message from `"news@shop.com"` is displayed, `isImageTrusted` returns false and its remote images are blocked again (the user must re-tap "Load images"/"Always" to re-trust)

#### Scenario: Remove is immediate with no confirm step

- **WHEN** the user taps "Stop"
- **THEN** the entry is removed without a confirmation dialog
- **AND** the list re-renders without that entry in the same Settings view

#### Scenario: Edge case: removing an address not in the set is a no-op

- **GIVEN** `"x@y.com"` is NOT trusted
- **WHEN** the core removes `"x@y.com"`
- **THEN** the set is unchanged and no error is raised

#### Scenario: Edge case: removing the last entry empties the set

- **GIVEN** the set has exactly one member
- **WHEN** that member is removed
- **THEN** the set is empty
- **AND** the Settings list shows its empty-state copy (see next requirement), not a stale row

### Requirement: The Settings list is always reachable with an empty-state

The Settings "Remote images" section SHALL render UNCONDITIONALLY (not gated on `!model.trustedImageSenders.isEmpty`, as today at `SettingsView.swift:233`), showing the sorted entries when present and an explanatory empty-state line when the set is empty — consistent with the sibling "Blocked contacts" section, which always renders and shows guidance copy when empty (`SettingsView.swift:250-254`). This guarantees the user can always reach the audit/revoke surface and understands it exists even before any sender is trusted.

#### Scenario: List shows entries when senders are trusted

- **GIVEN** one or more trusted senders
- **WHEN** the Settings "Remote images" section renders
- **THEN** each canonical address is shown as a row with a "Stop" control, sorted ascending

#### Scenario: Empty-state when no senders are trusted

- **GIVEN** `trustedImageSenders` is empty
- **WHEN** the Settings "Remote images" section renders
- **THEN** the section is still present
- **AND** it shows a short explanatory line (e.g. that senders are trusted via a message's "Always" button) instead of an empty list

## Success Criteria

- **SC-001** *(manual)*: On screen, after trusting a sender via the reader's "Always" button, the Settings "Remote images" section lists that sender; tapping "Stop" removes the row immediately (no confirm dialog); reopening a message from that sender shows its remote images blocked again (the "Load images"/"Always" row reappears). This on-screen SwiftUI list + remove + reader-re-block flow is a manual-exploration check, explicitly NOT part of the automated suite (SC-006) — a rendered SwiftUI list, a live `UserDefaults`-backed `AppModel`, and a WebKit reader render cannot be asserted by the test target.
- **SC-002**: A pure trusted-set core exposes `normalize`, `add`, `remove`, `contains`, and `list` over injected `Set<String>` / `String` values, exercised with NO `UserDefaults` / Keychain / AppModel / WebKit access (proving purity — a core that touched any of those would fail this test). `normalize` returns the canonical lowercased, whitespace/newline-trimmed, `<>`-stripped form (nil for empty), matching `AppModel.normalizeAddress` (`AppModel.swift:801-807`).
- **SC-003**: The consistency invariant is asserted directly: for each of a representative set of raw inputs — `"a@b.com"`, `"A@B.COM"`, `"  a@b.com  "`, `"<a@b.com>"`, `"<A@B.com >"` — `contains(add(empty, raw), raw)` is true (an added address is findable by the same raw input under one normalization), AND `contains(remove(add(empty, raw), raw), raw)` is false (removing the same raw input revokes it). This proves add/contains/remove agree by construction — the central edge case the current divergent rules fail. Regression assertion closing the old in-session-vs-relaunch divergence: simulate the persisted-reload canonicalization by applying `normalize` (the `normalizeAddress` rule) to a stored raw entry to produce the post-relaunch canonical member, then assert `contains` of a set holding ONLY that reloaded canonical form still returns true for the ORIGINAL raw input — e.g. `contains([normalize("<A@B.com >")!], "<A@B.com >")` is true. Under the OLD `lowercased()`-only contains this failed (the stored form was `<>`-stripped but the check was not), so the in-session and post-relaunch behaviors no longer diverge. Pure test over the injected core — no real `UserDefaults`.
- **SC-004**: `add` is idempotent and de-duplicating: adding two case/whitespace/angle-bracket variants of one address yields a one-member set; `add` of a no-`@` or empty-normalizing input leaves the set unchanged. `remove` is total: removing an absent address is a no-op returning the unchanged set, and removing the sole member yields the empty set.
- **SC-005**: `list` returns the canonical members sorted lexicographic ascending on the canonical string (Swift `Array.sorted()` default `<` on the normalized `String`, NOT domain-then-local-part or any other key) and de-duplicated for a populated set, and `[]` for the empty set — a pure function of the input set, asserted with injected values.
- **SC-006**: All automated scenarios above pass under the `MMailTests` target using **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — NOT XCTest. SC-001 is excluded (manual on-screen verification).

## Non-Goals

- **No manual add-by-typing in Settings.** Decision/assumption: senders are added to trust ONLY via the reader's existing per-message "Always" button (`ReaderView.swift:305`), which carries the real `fromEmail` of a message the user is actually reading. A free-text "add a trusted address" field in Settings is out of scope — it invites typos that would silently fail the `@` guard, and there is no need to pre-trust a sender before seeing their mail. Settings is VIEW + REVOKE only. (A reviewer may argue for a manual-add field; the assumption is that the reader add path is the only sound entry point.)
- **No bulk "remove all / clear list" control.** Decision/assumption: MVP is per-entry "Stop" only. A "clear all trusted senders" button is deferred; with the list always visible and per-row removal, clearing N senders is N taps, acceptable for the expected small list size. (Reviewer may request a clear-all for large lists.)
- **No confirmation modal on remove.** Decision/assumption: removal is immediate and reversible (re-tap "Always" on the next message), and the consequence (images blocked again) is conservative/privacy-safe, so a confirm dialog is friction without benefit.
- **No undo / toast.** Removal gives no undo affordance beyond re-trusting via the reader. Out of MVP scope.
- **No change to the trust SEMANTICS or the reader gate.** `showImages = loadImages || isImageTrusted(fromEmail)` (`ReaderView.swift:290-291`) is unchanged; trusted senders still bypass the block. This feature only makes membership *consistent* and *revocable*, it does not alter what trust DOES. The one permitted change to existing behavior is reconciling the three divergent normalizations to the canonical `normalizeAddress` rule (Invariants) — which can change outcomes ONLY for non-canonical addresses (whitespace/angle-bracket/newline variants), always toward the canonical form the persisted set already uses; canonical `mailbox@host` addresses (the practical norm produced by `IMAPService.swift:608`) are unaffected.
- **No migration pass over existing stored entries.** Decision/assumption: entries already persisted are reloaded through `normalizeAddress` on launch (`AppModel.swift:267-268`), so they are ALREADY in canonical form in memory; no separate rewrite of `UserDefaults` is required. (If a future audit finds a non-canonical entry was persisted by the old `trustImages`, it is canonicalized on the next reload anyway.)
- **Not the proxy secret fallback (A), reader proxy indicator (B), or proxy misconfiguration warning (C)** — those are separate, completed image-privacy features. This spec adds nothing to `ProxySecretStore`, `ReaderImageLoadState`, `ProxyConfigState`, `ImageProxy`, the URL-signing contract, or the Cloudflare Worker.
- **No change to blocked-sender normalization.** The sibling `unblockSender` (`AppModel.swift:843`) uses the same `lowercased()`-only pattern for blocked-sender operations; this spec intentionally does NOT touch blocked-sender normalization — scope is limited strictly to the trusted-image-sender operations (add/contains/remove/list). A reader expecting blanket "normalization consistency" across all sender lists should note that boundary.
- **No telemetry.** The trusted set is never logged or transmitted; it lives only in `UserDefaults` under `kTrustedImages` as today.
