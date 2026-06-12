# Weather City Lookup Specification

## Purpose

The Home view's weather widget lets the user type a city to override IP geolocation, but free-text like `"kingsville md"` does not resolve. `WeatherService.fetch(city:)` passes the ENTIRE typed string as the Open-Meteo geocoder's `name` parameter (`MMail/Mail/WeatherService.swift:44`) with `count=1`, and the geocoder matches a place NAME only — not "city state" — so a `"City ST"` string returns no results and `geocode` returns nil (`MMail/Mail/WeatherService.swift:52`). When `geocode` returns nil for a typed city, `located` is nil and `fetch` returns nil at `MMail/Mail/WeatherService.swift:13` — note this path does NOT reach `geolocate()`, so there is no present-day IP fallback for a typed city (see INV-3). When `fetch` returns nil, the model's `refreshWeather()` does `if let w { self.weather = w }` (`MMail/State/AppModel.swift:1185`), so the previous (wrong/stale) weather is SILENTLY kept with no feedback to the user.

This feature SHALL (1) parse a typed `"City, ST"` / `"City State"` / `"City, Country"` string into a place token plus an optional region qualifier and disambiguate the geocoder's candidate list by region (including US state abbreviations); (2) surface an ALERT when a typed city does not resolve to a confident match, so the user can re-type; and (3) preserve, as a permanent structural guarantee, that a typed city NEVER falls back to IP geolocation — today's typed-city path already does not reach `geolocate()` (a not-found typed city returns nil at `MMail/Mail/WeatherService.swift:13`), and the redesign's NEW not-found/error paths SHALL keep it that way by design so no future change introduces an IP fallback. IP geolocation stays ONLY for the explicit "Use my location" (empty-city) path. The parsing and candidate-matching SHALL be a pure, deterministic, network-free seam covered by XCTest; the network call stays in `WeatherService` and is not unit-tested.

## Invariants

- **INV-1 (pure parse/match seam):** Input parsing, the US-state-abbreviation table, region matching, and best-candidate selection SHALL live in a pure, deterministic, network-free type (named `WeatherQuery` herein). It SHALL take already-decoded candidate values and a parsed query and return a chosen candidate or nil, performing NO I/O. This is the only part under XCTest; the network call stays in `WeatherService` (`MMail/Mail/WeatherService.swift:41-57`) and is NOT unit-tested.
- **INV-2 (never a wrong city when a region was given):** If the typed input parses to a non-nil region qualifier and NO geocoder candidate matches that region (by `admin1` full name, `country`, `country_code`, OR a US-state abbreviation expanded to its full name), `bestMatch` SHALL return nil — never a same-named candidate in the wrong region. This is the core correctness guarantee replacing the current `count=1`/whole-string behavior (`MMail/Mail/WeatherService.swift:45,52`).
- **INV-3 (typed city NEVER falls back to IP geolocation — structural, by design):** This is a STRUCTURAL invariant the redesign makes explicit and permanently guarantees, NOT a fix for an existing leak: today's typed-city path already never reaches `geolocate()` (a not-found typed city returns nil at `MMail/Mail/WeatherService.swift:13`; `geolocate()` is only reached on the empty-city branch at `MMail/Mail/WeatherService.swift:8-12`). When `fetch` is called with a non-empty city, it SHALL NOT call `geolocate()` (`MMail/Mail/WeatherService.swift:59-76`) under ANY outcome — match, not-found, or network/decode error — and the NEW not-found and error code paths SHALL preserve this so the redesign can never introduce an IP fallback. `geolocate()` SHALL remain reachable ONLY via the empty-city path (`MMail/Mail/WeatherService.swift:8-12`, today reached by `setWeatherCity("")` from the "Use my location" button, `MMail/Views/HomeView.swift:157`). This is a privacy invariant: IP-geolocation egress is opt-in.
- **INV-4 (three distinguishable outcomes, error is a single class):** `fetch(city:)` SHALL return a result that lets `AppModel` distinguish exactly three outcomes for a typed city — success (a `WeatherInfo`), not-found (typed city parsed but no confident candidate match), and transient network/decode error. The error outcome covers BOTH error sub-cases identically: (a) the geocode request itself failed or was undecodable (the `try?`/`guard` at `MMail/Mail/WeatherService.swift:49-52`), AND (b) `bestMatch` succeeded but the subsequent FORECAST request failed or was undecodable (the `try?`/`guard` at `MMail/Mail/WeatherService.swift:24-26`). Both map to the SAME error outcome; `AppModel` treats them identically — leave `self.weather` unchanged AND do NOT raise the not-found alert. The model SHALL raise the not-found alert ONLY on the not-found outcome, NOT on either error sub-case, so a network blip does not produce a misleading "couldn't find that city" message. This replaces the single-`WeatherInfo?`-nil return that conflates all three (`MMail/Mail/WeatherService.swift:6,13,52`).
- **INV-5 (not-found preserves prior weather and never re-alerts a stale city on relaunch):** On the not-found and error outcomes, `refreshWeather()` SHALL leave `self.weather` unchanged (preserving today's "keep previous" behavior at `MMail/State/AppModel.swift:1185`) and, for not-found, raise the alert. Furthermore, the not-found alert SHALL be raised ONLY in response to an explicit user submit (the "Set" button at `MMail/Views/HomeView.swift:158`), NEVER on the automatic launch/refresh of a persisted `weatherCity` (`MMail/State/AppModel.swift:228,1176-1177`) — so a stale bad string is never silently re-alerted on relaunch. The persisted `weatherCity` string is kept as-is (no revert); see the "raise the not-found alert only on the not-found outcome" requirement.

## Requirements

### Requirement: Parse typed input into a place token and optional region qualifier

The pure seam SHALL split a typed string into a city token plus an optional region qualifier and normalize whitespace and case, so the geocoder is queried by the CITY token alone and the region is used only for disambiguation. In the COMMA form, everything before the last comma is the city and the segment after it is the region. In the NO-COMMA form, a trailing whitespace-delimited token SHALL be treated as a region qualifier ONLY when it is a RECOGNIZED region token — a known US-state abbreviation, a country code, or a country/state full name; otherwise the WHOLE remaining string is the city (so a multi-word place name like `"San Francisco"` parses to city `"San Francisco"`, region nil, and is NEVER mis-parsed to city `"San"`).

#### Scenario: "City, ST" comma form

- **GIVEN** the user types `"Kingsville, MD"`
- **WHEN** `WeatherQuery.parse(_:)` runs
- **THEN** it returns `(city: "Kingsville", region: "MD")` with surrounding/duplicate whitespace collapsed
- **AND** the city token (not the whole string) is what the geocoder is queried with — fixing the whole-string `name` bug (`MMail/Mail/WeatherService.swift:44`)

#### Scenario: "City State" space form (trailing-token region)

- **GIVEN** the user types `"kingsville md"` (no comma)
- **WHEN** `parse` runs
- **THEN** it returns `(city: "kingsville", region: "md")` because the trailing token `"md"` IS a recognized region token (a known US-state abbreviation) per the multi-word rule below
- **AND** case is normalized for matching so `"md"` and `"MD"` are equivalent

#### Scenario: Bare city, no region

- **GIVEN** the user types `"Paris"`
- **WHEN** `parse` runs
- **THEN** it returns `(city: "Paris", region: nil)`

#### Scenario: Edge case — multi-word city with no region

- **GIVEN** the user types `"San Francisco"`
- **WHEN** `parse` runs (no comma)
- **THEN** in the no-comma form, a trailing whitespace-delimited token SHALL be treated as a REGION qualifier ONLY when it is a RECOGNIZED region token — a known US-state abbreviation, a country code, or a country/state full name; otherwise the WHOLE remaining string is part of the CITY name
- **AND** because `"Francisco"` is NOT a recognized region token, the result is `(city: "San Francisco", region: nil)` — the parser MUST NOT mis-parse it to city `"San"`
- **AND** by contrast `"kingsville md"` parses to `(city: "kingsville", region: "md")` because `"md"` IS a recognized US-state abbreviation
- **AND** the comma form (e.g. `"San Francisco, CA"`) is ALWAYS safe — everything before the last comma is the city, the segment after is the region

### Requirement: Disambiguate the geocoder candidate list by region, including US state abbreviations

The pure seam SHALL select the best candidate from the geocoder's list using the parsed region, expanding US state abbreviations to full names, and SHALL return nil when a region was specified but nothing matches it.

#### Scenario: Region matches a candidate's admin1 via US-state abbreviation

- **GIVEN** parsed `(city: "Kingsville", region: "md")` and a candidate list (queried with `count` ≥ 10, replacing `count=1` at `MMail/Mail/WeatherService.swift:45`) containing a Kingsville whose `admin1` is `"Maryland"` and a Kingsville whose `admin1` is `"Texas"`
- **WHEN** `WeatherQuery.bestMatch(candidates:region:)` runs
- **THEN** the abbreviation `"md"` expands to `"Maryland"` (via the in-scope US-state-abbreviation→full-name table) and the Maryland candidate is chosen — its lat/lon/label drive the forecast
- **AND** matching is case-insensitive

#### Scenario: Region matches full admin1 name, country, or country code

- **GIVEN** parsed regions `"Maryland"`, `"United States"`, `"US"`, or `"France"`
- **WHEN** `bestMatch` runs against candidates carrying `name/admin1/country/country_code/lat/lon`
- **THEN** a candidate is matched when the region (case-insensitively) equals its `admin1` full name, its `country`, OR its `country_code` — so `"Paris, France"` and `"Paris, FR"` both resolve to Paris, France rather than Paris, Texas

#### Scenario: Region specified but no candidate matches → not-found (never a wrong city)

- **GIVEN** parsed `(city: "Kingsville", region: "zz")` (or any region matching no candidate's admin1/country/country_code/state-abbrev)
- **WHEN** `bestMatch` runs
- **THEN** it returns nil (INV-2) — it MUST NOT fall through to the top candidate, because that would show a same-named city in the wrong region

#### Scenario: No region specified → take the top candidate

- **GIVEN** parsed `(city: "Paris", region: nil)` and a non-empty candidate list
- **WHEN** `bestMatch` runs
- **THEN** it returns the first/top candidate (the geocoder's own ranking), reproducing today's single-result behavior for unqualified queries but now over a `count` ≥ 10 list

#### Scenario: Edge case — empty candidate list

- **GIVEN** any parsed query and an EMPTY candidate list (geocoder returned no results)
- **WHEN** `bestMatch` runs
- **THEN** it returns nil regardless of whether a region was specified

### Requirement: fetch returns three distinguishable outcomes and never IP-falls-back a typed city

`WeatherService.fetch(city:)` SHALL classify a typed-city lookup into success / not-found / network-or-decode-error, and SHALL never invoke IP geolocation for a typed city.

#### Scenario: Successful typed-city lookup

- **GIVEN** a non-empty city that parses and whose geocoder candidates yield a confident `bestMatch`, and the forecast request succeeds
- **WHEN** `fetch(city:)` runs
- **THEN** it returns the success outcome carrying a `WeatherInfo` (`MMail/Models/Models.swift:219-226`) whose `location` reflects the matched candidate's name + admin1/country (as today, `MMail/Mail/WeatherService.swift:53-55`)

#### Scenario: Typed city does not resolve → not-found outcome

- **GIVEN** a non-empty city where `bestMatch` returns nil (region given but unmatched, or empty candidate list)
- **WHEN** `fetch(city:)` runs
- **THEN** it returns the NOT-FOUND outcome (distinct from error and from success)
- **AND** it does NOT call `geolocate()` (INV-3) and does NOT return a wrong-city `WeatherInfo`

#### Scenario: Geocode request fails → error outcome

- **GIVEN** a non-empty city, but the GEOCODING request fails/cannot be decoded (the `try?`/`guard` failures at `MMail/Mail/WeatherService.swift:49-52`)
- **WHEN** `fetch(city:)` runs
- **THEN** it returns the ERROR outcome (distinct from not-found)
- **AND** it does NOT call `geolocate()` (INV-3)

#### Scenario: bestMatch succeeds but forecast request fails → SAME error outcome

- **GIVEN** a non-empty city whose geocoder candidates yield a confident `bestMatch`, but the subsequent FORECAST request then fails/cannot be decoded (the `try?`/`guard` at `MMail/Mail/WeatherService.swift:24-26`)
- **WHEN** `fetch(city:)` runs
- **THEN** it returns the SAME ERROR outcome as a geocode-request failure (NOT not-found, NOT success), so `AppModel` leaves `self.weather` unchanged and does NOT raise the not-found alert (INV-4)
- **AND** it does NOT call `geolocate()` (INV-3) — a successful match followed by a forecast failure never IP-falls-back

#### Scenario: Empty city still uses IP geolocation

- **GIVEN** `fetch` is called with `nil` city (the "Use my location" path, `MMail/Views/HomeView.swift:157` → `setWeatherCity("")` sets `weatherCity` to `""`, so `refreshWeather` passes `nil` BECAUSE of the `city.isEmpty ? nil : city` ternary at `MMail/State/AppModel.swift:1184` — `setWeatherCity` itself does not pass `nil`). A TYPED city, by contrast, is a non-empty `weatherCity`, so the same ternary passes the non-empty string through to `fetch`; the plan's new `fetch` signature MUST therefore treat `nil`/empty as the IP path and a non-empty string as the typed-city path.
- **WHEN** `fetch` runs
- **THEN** it calls `geolocate()` (`MMail/Mail/WeatherService.swift:11,59-76`) exactly as today and returns success or, on failure, an outcome the model treats as "no change" (NOT the typed-city not-found alert)

### Requirement: Model raises the not-found alert only on the not-found outcome

`AppModel` SHALL drive a published flag that the Home view binds to an alert, set ONLY when a typed city yields the not-found outcome — never on success, error, or the empty-city path. Prior weather SHALL be preserved on not-found and error. The persisted `weatherCity` string SHALL be KEPT (not reverted) on a not-found typed city, and the not-found alert SHALL be raised ONLY in response to an explicit user submit ("Set" at `MMail/Views/HomeView.swift:158`) — NEVER on the automatic launch/refresh of that persisted string. This guarantees the user is never confused by a stale bad city silently re-presenting its not-found alert on relaunch, with no `UserDefaults` schema change.

#### Scenario: Not-found raises the alert and preserves prior weather

- **GIVEN** the user typed a city that resolves to not-found
- **WHEN** `refreshWeather()` (`MMail/State/AppModel.swift:1181-1187`) observes the not-found outcome
- **THEN** it sets a published not-found flag and leaves `self.weather` unchanged (INV-5)
- **AND** `HomeView`'s `weatherCard` (`MMail/Views/HomeView.swift:133-176`) presents an alert titled e.g. "Couldn't find that city" whose message suggests "Try City, ST" so the user can re-type (a NEW alert binding alongside the existing `cityPromptOpen` alert at `MMail/Views/HomeView.swift:154-161`, using a new `@State` flag like the existing `cityPromptOpen`/`cityDraft` at `MMail/Views/HomeView.swift:7-8`)

#### Scenario: Network/decode error does NOT raise the not-found alert

- **GIVEN** the user typed a city but the lookup hit the error outcome (network blip)
- **WHEN** `refreshWeather()` observes the error outcome
- **THEN** it does NOT set the not-found flag (INV-4) and leaves `self.weather` unchanged — no misleading "couldn't find that city" on a transient failure

#### Scenario: Stale not-found city is not re-alerted on relaunch/auto-refresh

- **GIVEN** a previously typed city that resolved to not-found is still the persisted `weatherCity` and the app relaunches (or an automatic, non-user-initiated `refreshWeather()` fires)
- **WHEN** `refreshWeather()` runs on that persisted string WITHOUT an explicit user submit
- **THEN** the not-found flag is NOT set and NO alert is presented — prior weather is shown unchanged; the alert is reserved for an explicit "Set" submit (INV-5)
- **AND** the persisted `weatherCity` string is kept as-is (NOT reverted), with no `UserDefaults` schema change

#### Scenario: Success clears any prior not-found state

- **GIVEN** a previous not-found left the flag set, and the user re-typed a city that now resolves
- **WHEN** `refreshWeather()` observes success
- **THEN** it updates `self.weather` and clears the not-found flag so the alert does not re-present

#### Scenario: Edge case — "Use my location" never triggers the not-found alert

- **GIVEN** the user picks "Use my location" (empty city)
- **WHEN** geolocation fails for any reason
- **THEN** the not-found flag is NOT set (the not-found alert is exclusively for typed cities), preserving prior weather

## Success Criteria

- **SC-1 (unit):** `WeatherQuery.parse` returns the documented `(city, region)` for `"Kingsville, MD"`→`("Kingsville","MD")`, `"kingsville md"`→`("kingsville","md")`, `"Paris"`→`("Paris", nil)`, `"Paris, France"`→`("Paris","France")`, and — asserting the multi-word rule — `"San Francisco"`→`("San Francisco", nil)` (NOT city `"San"`) and `"San Francisco, CA"`→`("San Francisco","CA")` — XCTest, network-free.
- **SC-2 (unit):** The US-state-abbreviation table + region matcher resolve `"md"`→Maryland, `"tx"`→Texas, `"ny"`→New York case-insensitively, and match full `admin1`, `country`, and `country_code` — XCTest.
- **SC-3 (unit):** `WeatherQuery.bestMatch` chooses the region-matching candidate when one exists, returns nil when a region was specified but none matches (INV-2), takes the top candidate when no region is specified, and returns nil for an empty candidate list — all four arms covered by XCTest.
- **SC-4 (unit):** The not-found classification is exercised as a pure decision: given a parsed query + candidate list, the seam yields exactly one of {matched-candidate, not-found} so `fetch`'s success-vs-not-found split is unit-testable without network — XCTest. The pure seam's coverage is success-vs-not-found ONLY; the error outcome (both the geocode-request-failure and the post-`bestMatch` forecast-failure sub-cases of INV-4) lives in `WeatherService`'s network code, not in the seam, so it is out of scope for this unit test and is exercised live (SC-6 covers not-found; error behavior is inspection-level).
- **SC-5 (live):** Typing `"kingsville md"` resolves to Kingsville, Maryland in the widget (not Texas, not stale) — live-verified by the user.
- **SC-6 (live):** Typing a bogus city (e.g. `"asdfqwer, zz"`) presents the "Couldn't find that city" alert and leaves the previously shown weather unchanged — live-verified by the user.
- **SC-7 (live):** "Use my location" still resolves via IP geolocation and shows weather, and never triggers the not-found alert — live-verified by the user.
- **SC-8 (live/inspection):** A typed-city lookup never invokes IP geolocation (INV-3, the privacy fix) — verified by inspection that the typed-city path has no reachable `geolocate()` call, plus live confirmation that a not-found typed city does not silently jump to the local IP-area weather.

## Non-Goals

- **No autocomplete / candidate picker UI.** The widget keeps a single text field + alert (`MMail/Views/HomeView.swift:154-161`); it does NOT present a list of matching cities for the user to pick from. Disambiguation is by the typed region qualifier only.
- **No reverse-geocoding or map/coordinate entry.** Lat/lon are obtained solely from the Open-Meteo geocoder candidates; the user cannot type coordinates.
- **No change to the forecast request or `WeatherInfo` shape.** The forecast call (`MMail/Mail/WeatherService.swift:14-37`) and the `WeatherInfo` model (`MMail/Models/Models.swift:219-226`) are unchanged; this feature only changes the geocode/disambiguate/outcome-signalling path.
- **No new IP-geolocation providers or fallbacks.** `geolocate()`'s ipwho.is→ipapi.co chain (`MMail/Mail/WeatherService.swift:59-76`) is untouched; it simply becomes unreachable from the typed-city path.
- **No persistence-format change for `weatherCity`.** The `UserDefaults` key/handling (`MMail/State/AppModel.swift:228,230,1176-1177`) is unchanged. A not-found typed city's stored string is KEPT (not reverted) per the "raise the not-found alert only on the not-found outcome" requirement; the not-found alert is gated to explicit user submit so the stale string never silently re-alerts on relaunch. The only thing left to the plan is the trivial mechanism for distinguishing a user submit from an automatic refresh — not a schema change.
