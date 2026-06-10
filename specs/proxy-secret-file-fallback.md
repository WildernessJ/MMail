# Proxy Secret File Fallback Specification

## Purpose

The app SHALL persist the image-proxy HMAC signing secret in **both** the macOS Keychain (primary) and a private on-disk fallback file, so the secret survives an unsigned `CODE_SIGNING_ALLOWED=NO` rebuild and the proxy re-activates on next launch without the user re-entering it. Today the secret lives in the Keychain only; an unsigned rebuild changes the binary's code-signing identity, so `Keychain.readProxySecret()` returns nil, `AppModel.imageProxyConfig` silently goes nil, and images load **direct** from the origin (leaking the user's IP) until the user re-pastes the secret in Settings. Existing Keychain-only secrets SHALL be migrated to the file automatically (backfill) so the protection is not lost on the first rebuild after this feature ships.

## Invariants

- **Two layers.** Secret sourcing splits into (1) a **pure** resolver `resolve(keychain:file:)` over injected source values — NO Keychain or filesystem access inside it — and (2) an **impure** wrapper `loadProxySecret()` that performs the actual reads, calls the pure resolver, and performs the file sync (below). All I/O lives in the wrapper; the resolver MUST be unit-testable with injected strings and no real I/O.
- The Keychain MUST remain the primary store: whenever a secret is present (non-blank) in the Keychain it MUST be the effective value, and the fallback file MUST NOT override it.
- The Keychain write and the file write MUST be **independent**: one failing MUST NOT prevent attempting the other, and each write's success/failure MUST be reported to the caller — never silently swallowed.
- The fallback file MUST be created or replaced **atomically** at mode `0600` — written to a `0600` temp file in the same directory and `rename(2)`'d into place — so there is no instant at which a partially-written or world-readable file is visible (this covers both first-create and overwrite). It MUST live OUTSIDE the git working tree.
- Secrets MUST be stored **trimmed** (leading/trailing whitespace and newlines removed) in both stores; the file holds exactly the trimmed secret with no trailing newline, and the resolver trims file contents before its blank check. A round-tripped secret therefore never reads as blank and never carries stray whitespace.
- The file sync MUST be **idempotent**: it MUST NOT write when the file already equals the resolved secret, so steady-state reads perform no disk writes.
- A secret value MUST NEVER be written to `UserDefaults`, logs, or any git-tracked file.
- This change MUST NOT alter the proxy URL-signing contract or the `ImageProxyConfig` shape — only how the secret is *sourced*.

## Requirements

### Requirement: Pure secret resolution prefers Keychain, falls back to file

A pure resolver `resolve(keychain:file:)` SHALL return the Keychain value when present and non-blank (after trimming), otherwise the file value when present and non-blank (after trimming), otherwise nil. The resolver SHALL perform no Keychain or filesystem access. Both `AppModel.imageProxyConfig` and `AppModel.hasProxySecret` SHALL obtain the secret through the impure `loadProxySecret()` wrapper (which reads both sources, calls `resolve`, and runs the sync below) — NOT by calling `Keychain.readProxySecret()` directly (today both call sites bypass any fallback).

#### Scenario: Keychain present takes precedence

- **GIVEN** the Keychain holds secret `K` and the fallback file holds a different secret `F`
- **WHEN** the resolver runs
- **THEN** it returns `K`

#### Scenario: Keychain blank falls back to file

- **GIVEN** the Keychain holds no proxy secret (e.g. after an unsigned rebuild)
- **AND** the fallback file holds secret `F`
- **WHEN** the resolver runs
- **THEN** it returns `F`
- **AND** `imageProxyConfig` is non-nil when proxying is enabled and a base URL is set

#### Scenario: Both sources blank

- **GIVEN** neither source holds a non-blank secret
- **WHEN** the resolver runs
- **THEN** it returns nil
- **AND** `imageProxyConfig` is nil (today's behavior — proxy bypassed)

#### Scenario: Edge case: fallback file present but blank

- **GIVEN** the Keychain is blank
- **AND** the fallback file exists but contains only whitespace/newlines
- **WHEN** the resolver runs
- **THEN** it returns nil (a blank file is treated as absent)

### Requirement: Saving persists to both stores and reports per-store outcome

`AppModel.setProxySecret` SHALL trim the supplied secret and write it to BOTH the Keychain and the fallback file, returning a result that reports the success/failure of EACH write independently. A failure in one store MUST NOT prevent the write to the other. Any failure MUST be surfaced to the user in the Settings UI and logged (`os_log`); it MUST NOT be silently swallowed. (This requires `Keychain.storeProxySecret` to report its outcome rather than discard it.)

#### Scenario: Both writes succeed

- **GIVEN** the user pastes a non-empty secret and taps Save
- **WHEN** `setProxySecret` runs and both stores are writable
- **THEN** the result reports Keychain-success and file-success
- **AND** both stores hold the identical trimmed secret, the file at mode `0600`

#### Scenario: Edge case: file write fails, Keychain succeeds

- **GIVEN** the fallback file (or its directory) cannot be written
- **WHEN** `setProxySecret` runs
- **THEN** the Keychain write still succeeds
- **AND** the result reports the file failure
- **AND** the failure is shown in Settings and logged, not swallowed

#### Scenario: Edge case: Keychain write fails, file succeeds

- **GIVEN** the Keychain write fails (e.g. an item locked to a prior signing identity)
- **WHEN** `setProxySecret` runs
- **THEN** the file write still succeeds
- **AND** the result reports the Keychain failure
- **AND** the failure is shown in Settings and logged (so the user is not misled into thinking both stores are set)

#### Scenario: Edge case: empty secret is not savable

- **GIVEN** the secret draft is empty or whitespace-only
- **WHEN** the Settings secret field is shown
- **THEN** the Save control is disabled (unchanged from today)
- **AND** neither store is modified

### Requirement: Loading syncs the authoritative Keychain secret to the fallback file

Within `loadProxySecret()`, whenever the effective secret comes from the Keychain and the fallback file does NOT already equal that secret (file absent, blank, or holding a different value), the app SHALL write the resolved secret to the file (atomic `0600`). This both **migrates** an existing Keychain-only secret (file absent — closing the gap for users who had a secret before this feature shipped) and **corrects divergence** (file holds a stale value — so a stale file can never win on a later unsigned build). The sync is idempotent (no write when the file already equals the secret), fires from whichever call site triggers `loadProxySecret()` first (`imageProxyConfig` or `hasProxySecret`), and a sync-write failure MUST be logged but MUST NOT break the read.

#### Scenario: Existing Keychain-only secret is migrated

- **GIVEN** the Keychain holds secret `K` and the fallback file is absent
- **WHEN** `loadProxySecret()` runs
- **THEN** the file is created with `K` (trimmed) at mode `0600`
- **AND** a subsequent load performs no further write (idempotent)

#### Scenario: Stale file is corrected to the Keychain value

- **GIVEN** the Keychain holds secret `K` and the fallback file holds a different secret `F`
- **WHEN** `loadProxySecret()` runs
- **THEN** `resolve` returns `K` (Keychain wins)
- **AND** the file is overwritten with `K` (atomic `0600`), so the stale `F` cannot win on a later unsigned build

#### Scenario: Sync fires regardless of which call site loads first

- **GIVEN** the Keychain holds `K` and the file is absent
- **AND** Settings renders (calling `hasProxySecret`) before any mail view loads `imageProxyConfig`
- **WHEN** `hasProxySecret` triggers `loadProxySecret()`
- **THEN** the file is migrated to `K` in that same session

#### Scenario: Edge case: sync write fails

- **GIVEN** the Keychain holds `K` but the fallback file cannot be written
- **WHEN** `loadProxySecret()` runs
- **THEN** the failure is logged
- **AND** the effective secret is still `K` (the read is not broken)

### Requirement: Secret-present status reflects either source

`AppModel.hasProxySecret` SHALL be true exactly when the resolver returns a non-nil secret (present in either store), so Settings shows the "(set)" state after an unsigned rebuild.

#### Scenario: File-only secret still shows as set

- **GIVEN** the Keychain is blank but the fallback file holds a secret
- **WHEN** the Settings "Image privacy proxy" section renders
- **THEN** `hasProxySecret` is true
- **AND** the secret field shows the "•••••••• (set)" placeholder

#### Scenario: No secret anywhere

- **GIVEN** neither source holds a non-blank secret
- **WHEN** the Settings section renders
- **THEN** `hasProxySecret` is false
- **AND** the field shows the "Paste the signing secret" placeholder

### Requirement: The fallback file is private, locked-down, and outside the repo

The fallback file SHALL be located at `~/Library/Application Support/MMail/proxy-secret`, its parent directory created with intermediate directories as needed, the file created-or-replaced atomically at mode `0600` (write a `0600` temp file in the same directory, then `rename(2)` into place — so neither first-create nor overwrite exposes a partial or world-readable file), holding exactly the trimmed secret with no trailing newline, and SHALL NOT reside within the git working tree.

#### Scenario: Write creates the directory and file with correct mode and contents

- **GIVEN** `~/Library/Application Support/MMail/` does not yet exist
- **WHEN** a secret is saved
- **THEN** the directory is created (with intermediates)
- **AND** `proxy-secret` is written there at mode `0600`
- **AND** its contents equal the trimmed secret with no trailing newline

#### Scenario: Edge case: directory already exists, file overwritten atomically

- **GIVEN** `~/Library/Application Support/MMail/` already exists with an older `proxy-secret`
- **WHEN** a secret is saved
- **THEN** the existing directory is reused (no failure)
- **AND** the file is replaced atomically (temp + `rename`) at mode `0600`
- **AND** at no instant is a partial or non-`0600` file visible

## Success Criteria

- **SC-001** *(manual)*: After saving a secret once and performing an unsigned `CODE_SIGNING_ALLOWED=NO` rebuild + relaunch, remote images for a trusted sender load **through the proxy** with no re-entry (confirmed by a proxy hit in `wrangler tail`, not a direct origin load). This is a manual-exploration check, explicitly NOT part of the automated suite (SC-007).
- **SC-002**: The pure `resolve(keychain:file:)` returns the Keychain value when both are present (Keychain wins), and is exercised with injected strings only — the resolver test performs NO Keychain or filesystem access (proving purity; a resolver that touched the FS would fail this test).
- **SC-003**: The fallback file exists at mode `0600` under `~/Library/Application Support/MMail/`, is not under the repository path, and its contents equal the trimmed secret with no trailing newline.
- **SC-004**: `loadProxySecret()` syncs the file to the authoritative Keychain value in all three cases — file absent (migrated), file holding a different value `F` (overwritten with `K`), and file already equal (no write, idempotent).
- **SC-005**: `hasProxySecret` is true (Settings shows "(set)") after a rebuild that left the Keychain item unreadable, given the fallback file is present.
- **SC-006**: `setProxySecret` reports each store's outcome; a simulated file-write failure yields a result flagging the file failure with the Keychain still written, and the symmetric Keychain-failure case flags the Keychain with the file still written.
- **SC-007**: All automated scenarios above pass under the MMail XCTest target (SC-001 excluded — manual).

## Non-Goals

- **No clear/forget-secret flow.** Disclosure (user-accepted): the fallback file is NOT deleted when the app is removed, IS included in Time Machine backups of `~/Library/Application Support/`, and to revoke the secret the user must delete `~/Library/Application Support/MMail/proxy-secret` manually. Accepted because this is a low-sensitivity HMAC key (worst-case leak = Worker quota abuse; zero mail/account access).
- No encryption of the fallback file — plaintext at `0600` is the accepted tradeoff.
- No environment-variable source — Keychain + file only.
- No change to the proxy URL-signing contract, the `ImageProxyConfig` shape, or the Cloudflare Worker.
- The fallback file is NOT synced or shared across machines.
- Not the reader proxy-vs-direct indicator (B), the Settings misconfiguration warning (C), or trusted-sender management (D) — those are separate queued features.
