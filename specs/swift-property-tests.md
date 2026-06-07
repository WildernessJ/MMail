# Swift Property-Test Baseline Specification

## Purpose

MMail SHALL have a dependency-free property-based-testing (PBT) foundation — a small `forAll`
harness built only on Apple's `swift-testing` — plus a first suite of property tests over its
highest-value pure functions, so regressions in pure logic are caught automatically before
further feature work proceeds. This is the Swift analog of the project owner's Python/hypothesis
workflow; it is authored by hand (NOT via the harness's Python `property-tests` skill).

## Invariants

- The PBT harness MUST NOT add any third-party dependency — it is built only on `swift-testing`.
- Every property failure MUST be reproducible: the run MUST print the failing input and the RNG
  seed required to replay it.
- Property tests MUST exercise only pure, deterministic functions — no network, filesystem, or UI.
- Tests MUST reach production code via `@testable import MMail`; production source MUST NOT be
  changed solely to enable testing beyond the visibility already present (all current targets are
  `internal`, so no change is expected).
- When a property surfaces a GENUINE production defect (e.g. a crash), this feature SHALL include
  the minimal fix so the property holds — never weaken the generator to hide the defect. The
  `parseRecipients` backwards-range crash (see its requirement) is the one such fix currently in
  scope; any others discovered during build are surfaced to the user before being folded in.

## Requirements

### Requirement: forAll PBT harness

The harness SHALL provide a `forAll` runner that draws N inputs (default 200) from a caller-supplied
generator seeded by a deterministic RNG, evaluates a property on each input, and on the first
failure shrinks the input toward a minimal failing case and reports it together with the seed.

#### Scenario: All inputs satisfy the property

- **GIVEN** a generator and a property that holds for every value it can produce
- **WHEN** `forAll` runs the default number of iterations
- **THEN** every iteration passes
- **AND** no failure is reported

#### Scenario: A violated property is reported with a replay seed

- **GIVEN** a property that is false for some generated inputs
- **WHEN** `forAll` runs
- **THEN** the run fails
- **AND** the output contains a concrete counterexample value
- **AND** the output contains the RNG seed used

#### Scenario: Replay by seed reproduces the counterexample

- **GIVEN** a previously failing run reported seed `S`
- **WHEN** `forAll` is re-run pinned to seed `S`
- **THEN** it reproduces the same failing input

#### Scenario: Edge case: shrinking reduces a failing input

- **GIVEN** a property that fails on a large generated collection or integer
- **WHEN** `forAll` finds a failure
- **THEN** the reported counterexample is a reduced (smaller) input that still fails

### Requirement: Privacy.cleanLink property tests

`Privacy.cleanLink(_:)` (defined in `enum Privacy`, `MMail/Views/HTMLMessageView.swift:34`) SHALL
preserve an `http(s)` URL's meaningful structure while removing only known tracking parameters.
Generators for this requirement produce `http`/`https` URLs only — `mailto:`, `file:`, and opaque
URLs are out of scope, since `cleanLink` is applied to links inside HTML email bodies.

Note on idempotence: a second application of `cleanLink` finds no tracking params and returns its
input unchanged via the short-circuit at `HTMLMessageView.swift:38` (it does NOT re-serialize), so
idempotence is not exposed to `URLComponents` percent-encoding round-trip drift.

#### Scenario: Idempotence

- **WHEN** `cleanLink` is applied twice to any generated URL
- **THEN** the result equals applying it once

#### Scenario: Tracking keys removed

- **GIVEN** a URL whose query contains tracking keys (e.g. `utm_source`, `fbclid`, `gclid`)
- **WHEN** `cleanLink` is applied
- **THEN** none of those tracking keys remain in the result

#### Scenario: Non-tracking params and structure preserved

- **GIVEN** a URL with non-tracking query items plus optional tracking keys
- **WHEN** `cleanLink` is applied
- **THEN** every non-tracking query item is retained
- **AND** the scheme, host, and path are unchanged

#### Scenario: Edge case: components cannot re-serialize

- **GIVEN** a generated URL for which stripping yields components whose `.url` is `nil`
- **WHEN** `cleanLink` is applied
- **THEN** the function returns without trapping
- **AND** if this path causes a tracking key to survive (the current fallback at
  `HTMLMessageView.swift:40` returns the original URL), the test surfaces it as a `cleanLink` bug
  to fix rather than weakening the property to hide it

### Requirement: dedupById property tests

`AppModel.dedupById(_:)` (`AppModel.swift:1740`) SHALL remove duplicate-id entries without trapping,
without disturbing first-occurrence order, and without dropping or inventing entries.

#### Scenario: Uniqueness, order, and exact cardinality

- **GIVEN** any generated list of emails (including repeated ids)
- **WHEN** `dedupById` is applied
- **THEN** the result contains no duplicate ids
- **AND** the surviving entries preserve their first-occurrence order
- **AND** the result is a subsequence of the input (no entry is invented or reordered)
- **AND** the result's count equals the number of distinct ids in the input

#### Scenario: Idempotence

- **WHEN** `dedupById` is applied twice
- **THEN** the result equals applying it once

#### Scenario: Edge case: many duplicate ids do not trap

- **GIVEN** a list where most or all entries share the same id
- **WHEN** `dedupById` is applied
- **THEN** it returns normally without a runtime trap
- **AND** the result has exactly one entry per distinct id

### Requirement: MIME decode robustness property tests

`MIME.decodeHeader(_:)` (`MIME.swift:9`) and `MIME.extractText`/`parse` (`MIME.swift:142`/`:144`)
SHALL never crash on arbitrary input.

#### Scenario: decodeHeader passes through input that has no encoded-word marker

- **GIVEN** a generated string containing no `=?` substring anywhere (the marker the fast path at
  `MIME.swift:10` keys on) — the generator MUST enforce "no `=?` anywhere in the full string" as an
  invariant, since a `=?` in mid-string garbage takes the slow path and trims the result
- **WHEN** `decodeHeader` is applied
- **THEN** the output equals the input exactly (the fast path returns it unmodified, including any
  surrounding whitespace)

#### Scenario: decodeHeader never crashes on arbitrary input

- **GIVEN** any generated string, including ones containing `=?` with malformed encoded-word
  structure and random bytes-as-text
- **WHEN** `decodeHeader` is applied
- **THEN** it returns a string without trapping

#### Scenario: parse/extractText never crashes on arbitrary bytes

- **GIVEN** arbitrary `Data` (random bytes, truncated MIME, empty)
- **WHEN** `parse`/`extractText` is applied
- **THEN** it returns without trapping

### Requirement: parseRecipients property tests

`AppModel.parseRecipients(_:)` (`AppModel.swift:2663`) SHALL never crash, SHALL extract the address
from `Name <addr>` forms, and SHALL NOT leak the display name into the result.

KNOWN BUG this requirement surfaces: the angle-bracket extraction at `AppModel.swift:2667-2668`
uses the FIRST `<` and the FIRST `>`. When a `>` occurs before the first `<` (e.g. a display name
like `3>2 Name <addr@x.com>`), `s[lt.upperBound..<gt.lowerBound]` forms a backwards `Range` and the
`String` subscript traps (hard crash). Per the same philosophy as the cleanLink edge case, the
crash-freedom scenario below MUST keep an UNCONSTRAINED display-name generator (including `<`/`>`
in any order), and this feature MUST include a minimal safety fix to `parseRecipients` — search for
the closing `>` only AFTER the opening `<` (`range(of: ">", range: lt.upperBound..<endIndex)`) so a
`>` preceding the first `<` cannot form a backwards range — so the property holds. Do NOT weaken the
generator to hide the crash. (This is strictly better than a bare `lt.upperBound <= gt.lowerBound`
guard, which stops the crash but returns the whole piece and leaks the display name.)

#### Scenario: Address extraction without display-name leakage

- **GIVEN** a field built from generated `Display Name <local@domain>` entries joined by `,` or `;`,
  where each generated address contains `@` and each display name contains neither `@` nor `<`/`>`
- **WHEN** `parseRecipients` is applied
- **THEN** each embedded address appears in the result
- **AND** every returned entry contains `@`
- **AND** no returned entry contains its source display-name text

#### Scenario: Edge case: never crashes on arbitrary fields

- **GIVEN** an arbitrary generated field — bare addresses, `Name <addr>` forms, mixed `,`/`;`
  separators, AND display names containing arbitrary `<` and `>` characters in any order
- **WHEN** `parseRecipients` is applied
- **THEN** it returns without trapping (this is a pure crash-freedom property; correctness of
  extraction is asserted only by the constrained scenario above)

### Requirement: Test target and one-command run

A test target SHALL exist in `project.yml`, and the property suite SHALL run via `xcodebuild test`.

Implementation note (risk to resolve in the plan): the app target is `SWIFT_VERSION: "5.0"`. The
test target may need `SWIFT_VERSION: "6.0"` for `swift-testing` macros, and because `AppModel` is an
`ObservableObject` that may be `@MainActor`-isolated, calls to its `static` functions from tests may
require the test suite/functions to be `@MainActor` to avoid strict-concurrency errors. The plan
MUST verify the chosen test-target settings actually build before relying on them.

#### Scenario: Suite runs from the command line

- **WHEN** `xcodebuild test` is run for the MMail scheme
- **THEN** the property-test target builds and executes
- **AND** all properties pass

## Success Criteria

- **SC-001**: `xcodebuild test` runs the property suite and all properties pass.
- **SC-002**: For each **value-comparison** property (cleanLink idempotence/removal/preservation,
  dedupById uniqueness/order/cardinality, decodeHeader ASCII passthrough, parseRecipients
  extraction), deliberately breaking the target function makes that property fail and report a
  concrete counterexample plus the replay seed.
- **SC-003**: No third-party dependency is added — `project.yml`'s `packages:` list is unchanged;
  the only addition is the test target itself.
- **SC-004**: A failing value-comparison property can be replayed deterministically from its printed
  seed.
- **SC-005**: For the **crash-freedom** properties (decodeHeader, extractText/parse, and
  parseRecipients never trap), verification is that the property runs the full iteration count
  without trapping; a regression manifests as a test crash/trap (not a shrunk counterexample), and
  that is the accepted signal. parseRecipients crash-freedom additionally depends on the safety fix
  noted in its requirement (without it, the property crashes on the documented backwards-range input).

## Non-Goals

- No IMAP/SMTP/network behavior testing — that is the separate e2e/manual track.
- No UI / SwiftUI view testing.
- No use of the harness Python `property-tests` skill (hypothesis/`pytest`) — this baseline is
  hand-authored Swift on `swift-testing`.
- The diagnosed IMAP `MOVE`-fallback bug is out of scope (parked as a separate feature).
- Not a full QuickCheck/hypothesis reimplementation — minimal shrinking sufficient for the target
  types (String, Data, URL, `[Email]`) is enough.
