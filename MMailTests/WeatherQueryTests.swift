import Foundation
import Testing
@testable import MMail

/// Unit tests for the pure `WeatherQuery` seam: the network-free parser,
/// US-state-abbreviation table + region matcher, and best-candidate selector
/// that disambiguate a typed `"City, ST"` / `"City State"` / `"City, Country"`
/// string against the geocoder's candidate list. No I/O whatsoever (INV-1).
/// Covers SC-1 (parse), SC-2 (state table + matcher), SC-3/SC-4 (bestMatch
/// four arms + the success-vs-not-found split). Authored RED before the
/// implementation in `MMail/Mail/WeatherQuery.swift` exists.

// Small builder so candidate construction stays terse and the region matters.
private func cand(_ name: String,
                  admin1: String? = nil,
                  country: String? = nil,
                  countryCode: String? = nil,
                  lat: Double = 0,
                  lon: Double = 0) -> WeatherQuery.Candidate {
    WeatherQuery.Candidate(name: name, admin1: admin1, country: country,
                           countryCode: countryCode, latitude: lat, longitude: lon)
}

/// SC-1 — `parse` splits typed input into city + optional region and normalizes
/// whitespace, with the falsifiable multi-word trailing-token rule.
@Suite struct WeatherQueryParse {
    @Test func commaFormCityST() {
        let p = WeatherQuery.parse("Kingsville, MD")
        #expect(p.city == "Kingsville")
        #expect(p.region == "MD")
    }

    @Test func commaFormCollapsesWhitespace() {
        let p = WeatherQuery.parse("  Kingsville ,   MD  ")
        #expect(p.city == "Kingsville")
        #expect(p.region == "MD")
    }

    @Test func spaceFormTrailingStateAbbrev() {
        let p = WeatherQuery.parse("kingsville md")
        #expect(p.city == "kingsville")
        #expect(p.region == "md")
    }

    @Test func bareCityNoRegion() {
        let p = WeatherQuery.parse("Paris")
        #expect(p.city == "Paris")
        #expect(p.region == nil)
    }

    @Test func commaFormCountry() {
        let p = WeatherQuery.parse("Paris, France")
        #expect(p.city == "Paris")
        #expect(p.region == "France")
    }

    /// The falsifiable multi-word rule: a trailing token that is NOT a
    /// recognized region token stays part of the city — `"San Francisco"` must
    /// NOT mis-parse to city `"San"`, region `"Francisco"`.
    @Test func multiWordCityNoRegion() {
        let p = WeatherQuery.parse("San Francisco")
        #expect(p.region == nil)
        #expect(p.city == "San Francisco")
        #expect(p.city != "San")
    }

    /// The comma form is always safe for a multi-word city + region.
    @Test func multiWordCityCommaRegion() {
        let p = WeatherQuery.parse("San Francisco, CA")
        #expect(p.city == "San Francisco")
        #expect(p.region == "CA")
    }

    /// A trailing word that IS a recognized full state name is a region; the
    /// rest stays the city (`"Paris Texas"` → city `"Paris"`, region `"Texas"`).
    @Test func spaceFormTrailingFullStateName() {
        let p = WeatherQuery.parse("Paris Texas")
        #expect(p.city == "Paris")
        #expect(p.region == "Texas")
    }

    /// A non-region trailing word stays in the city even in the space form.
    @Test func spaceFormNonRegionTrailingStaysInCity() {
        let p = WeatherQuery.parse("New Orleans")
        #expect(p.region == nil)
        #expect(p.city == "New Orleans")
    }

    @Test func emptyInput() {
        let p = WeatherQuery.parse("   ")
        #expect(p.city == "")
        #expect(p.region == nil)
    }
}

/// SC-2 — the US-state-abbreviation table and the case-insensitive region
/// matcher (`admin1` full name, `country`, `country_code`).
@Suite struct WeatherQueryStateTableAndMatch {
    @Test func expandsKnownAbbreviations() {
        #expect(WeatherQuery.expandRegion("md").caseInsensitiveCompare("Maryland") == .orderedSame)
        #expect(WeatherQuery.expandRegion("tx").caseInsensitiveCompare("Texas") == .orderedSame)
        #expect(WeatherQuery.expandRegion("ny").caseInsensitiveCompare("New York") == .orderedSame)
    }

    @Test func expandIsCaseInsensitive() {
        #expect(WeatherQuery.expandRegion("MD").caseInsensitiveCompare("Maryland") == .orderedSame)
    }

    @Test func expandPassesThroughUnknown() {
        #expect(WeatherQuery.expandRegion("France") == "France")
    }

    @Test func tableHasAll51Entries() {
        // 50 states + DC.
        #expect(WeatherQuery.stateAbbreviations.count == 51)
    }

    @Test func matchesAdmin1ViaAbbrev() {
        let c = cand("Kingsville", admin1: "Maryland", country: "United States", countryCode: "US")
        #expect(WeatherQuery.regionMatches("md", candidate: c) == true)
    }

    @Test func matchesAdmin1FullName() {
        let c = cand("Kingsville", admin1: "Maryland", country: "United States", countryCode: "US")
        #expect(WeatherQuery.regionMatches("maryland", candidate: c) == true)
    }

    @Test func matchesCountryFullName() {
        let c = cand("Paris", admin1: "Île-de-France", country: "France", countryCode: "FR")
        #expect(WeatherQuery.regionMatches("France", candidate: c) == true)
    }

    @Test func matchesCountryCode() {
        let c = cand("Paris", admin1: "Île-de-France", country: "France", countryCode: "FR")
        #expect(WeatherQuery.regionMatches("fr", candidate: c) == true)
    }

    @Test func matchesUnitedStatesCountry() {
        let c = cand("Kingsville", admin1: "Texas", country: "United States", countryCode: "US")
        #expect(WeatherQuery.regionMatches("United States", candidate: c) == true)
        #expect(WeatherQuery.regionMatches("US", candidate: c) == true)
    }

    @Test func nonMatchingRegionIsFalse() {
        let c = cand("Kingsville", admin1: "Texas", country: "United States", countryCode: "US")
        #expect(WeatherQuery.regionMatches("Maryland", candidate: c) == false)
        #expect(WeatherQuery.regionMatches("zz", candidate: c) == false)
    }
}

/// SC-3 / SC-4 — `bestMatch` four arms and the pure success-vs-not-found split.
@Suite struct WeatherQueryBestMatch {
    static let kingsvilleMD = cand("Kingsville", admin1: "Maryland", country: "United States", countryCode: "US", lat: 39.4, lon: -76.4)
    static let kingsvilleTX = cand("Kingsville", admin1: "Texas", country: "United States", countryCode: "US", lat: 27.5, lon: -97.8)

    /// Arm 1: region matches a candidate's admin1 via abbrev → that one chosen,
    /// even though Texas is first in the list.
    @Test func regionMatchPicksCorrectAdmin1() {
        let chosen = WeatherQuery.bestMatch(candidates: [Self.kingsvilleTX, Self.kingsvilleMD], region: "md")
        #expect(chosen?.admin1 == "Maryland")
        #expect(chosen?.latitude == 39.4)
    }

    /// Arm 2: region given but NO candidate matches → nil (INV-2), never the top.
    @Test func regionGivenNoMatchReturnsNil() {
        let chosen = WeatherQuery.bestMatch(candidates: [Self.kingsvilleTX, Self.kingsvilleMD], region: "zz")
        #expect(chosen == nil)
    }

    /// Arm 3: no region + non-empty list → the first/top candidate.
    @Test func noRegionTakesTopCandidate() {
        let chosen = WeatherQuery.bestMatch(candidates: [Self.kingsvilleTX, Self.kingsvilleMD], region: nil)
        #expect(chosen?.admin1 == "Texas")
    }

    /// Arm 4a: empty list with a region → nil.
    @Test func emptyListWithRegionReturnsNil() {
        #expect(WeatherQuery.bestMatch(candidates: [], region: "md") == nil)
    }

    /// Arm 4b: empty list without a region → nil.
    @Test func emptyListNoRegionReturnsNil() {
        #expect(WeatherQuery.bestMatch(candidates: [], region: nil) == nil)
    }

    /// SC-4: the pure decision yields exactly one of {matched-candidate, nil};
    /// a matched region is a success, an unmatched region is not-found.
    @Test func successVsNotFoundSplit() {
        #expect(WeatherQuery.bestMatch(candidates: [Self.kingsvilleMD], region: "md") != nil)
        #expect(WeatherQuery.bestMatch(candidates: [Self.kingsvilleMD], region: "zz") == nil)
    }
}
