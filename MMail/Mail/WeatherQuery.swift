import Foundation

/// Pure, deterministic, network-free seam (INV-1) for the weather city lookup:
/// parses a typed `"City, ST"` / `"City State"` / `"City, Country"` string,
/// holds the US-state-abbreviation→full-name table, matches a parsed region
/// against an already-decoded geocoder candidate, and selects the best
/// candidate. Performs NO I/O — the geocode JSON → `Candidate` mapping and the
/// network calls live in `WeatherService`.
enum WeatherQuery {
    /// One decoded geocoder result. `WeatherService` maps the Open-Meteo
    /// geocoding JSON into these; the seam consumes them.
    struct Candidate {
        let name: String
        let admin1: String?
        let country: String?
        let countryCode: String?
        let latitude: Double
        let longitude: Double
    }

    /// A parsed typed query: the city token the geocoder is searched by, plus an
    /// optional region qualifier used ONLY for disambiguation.
    struct Parsed {
        let city: String
        let region: String?
    }

    /// US-state abbreviation (lowercased key) → full name (50 states + DC).
    static let stateAbbreviations: [String: String] = [
        "al": "Alabama", "ak": "Alaska", "az": "Arizona", "ar": "Arkansas",
        "ca": "California", "co": "Colorado", "ct": "Connecticut", "de": "Delaware",
        "fl": "Florida", "ga": "Georgia", "hi": "Hawaii", "id": "Idaho",
        "il": "Illinois", "in": "Indiana", "ia": "Iowa", "ks": "Kansas",
        "ky": "Kentucky", "la": "Louisiana", "me": "Maine", "md": "Maryland",
        "ma": "Massachusetts", "mi": "Michigan", "mn": "Minnesota", "ms": "Mississippi",
        "mo": "Missouri", "mt": "Montana", "ne": "Nebraska", "nv": "Nevada",
        "nh": "New Hampshire", "nj": "New Jersey", "nm": "New Mexico", "ny": "New York",
        "nc": "North Carolina", "nd": "North Dakota", "oh": "Ohio", "ok": "Oklahoma",
        "or": "Oregon", "pa": "Pennsylvania", "ri": "Rhode Island", "sc": "South Carolina",
        "sd": "South Dakota", "tn": "Tennessee", "tx": "Texas", "ut": "Utah",
        "vt": "Vermont", "va": "Virginia", "wa": "Washington", "wv": "West Virginia",
        "wi": "Wisconsin", "wy": "Wyoming", "dc": "District of Columbia"
    ]

    /// A small set of recognized non-US region tokens (country names + ISO-2
    /// country codes) so the no-comma trailing-token rule can recognize
    /// `"Paris France"` / `"Paris FR"` while leaving `"San Francisco"` alone.
    private static let countryTokens: Set<String> = [
        "us", "usa", "united states", "ca", "canada", "uk", "gb",
        "united kingdom", "england", "fr", "france", "de", "germany",
        "es", "spain", "it", "italy", "mx", "mexico", "au", "australia",
        "jp", "japan", "cn", "china", "in", "india", "br", "brazil"
    ]

    /// True when `token` is a recognized region qualifier — a US-state
    /// abbreviation (table KEY), a full US-state name (table VALUE), or a known
    /// country code / country name. Checks BOTH sides of the state table so
    /// `"Paris Texas"` parses region `"Texas"` while a place word like
    /// `"Francisco"` (in neither side, nor a country token) does NOT.
    static func isRegionToken(_ token: String) -> Bool {
        let t = token.lowercased()
        if stateAbbreviations[t] != nil { return true }
        if stateAbbreviations.values.contains(where: { $0.lowercased() == t }) { return true }
        if countryTokens.contains(t) { return true }
        return false
    }

    /// Trim + collapse internal whitespace. COMMA form: everything before the
    /// LAST comma is the city, the segment after is the region. NO-COMMA form:
    /// the trailing whitespace-delimited token is the region ONLY when
    /// `isRegionToken` is true — otherwise the WHOLE string is the city (so
    /// `"San Francisco"` → city `"San Francisco"`, region nil).
    static func parse(_ raw: String) -> Parsed {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return Parsed(city: "", region: nil) }

        if let lastComma = collapsed.lastIndex(of: ",") {
            let city = String(collapsed[collapsed.startIndex..<lastComma])
                .trimmingCharacters(in: .whitespaces)
            let region = String(collapsed[collapsed.index(after: lastComma)...])
                .trimmingCharacters(in: .whitespaces)
            return Parsed(city: city, region: region.isEmpty ? nil : region)
        }

        let tokens = collapsed.split(separator: " ").map(String.init)
        if tokens.count >= 2, let last = tokens.last, isRegionToken(last) {
            let city = tokens.dropLast().joined(separator: " ")
            return Parsed(city: city, region: last)
        }
        return Parsed(city: collapsed, region: nil)
    }

    /// Full state name for a known abbrev (case-insensitive), else the input
    /// unchanged.
    static func expandRegion(_ region: String) -> String {
        stateAbbreviations[region.lowercased()] ?? region
    }

    /// Case-insensitive: true when `region` (expanded if a state abbrev) equals
    /// the candidate's `admin1` full name, its `country`, OR its `countryCode`.
    static func regionMatches(_ region: String, candidate: Candidate) -> Bool {
        let expanded = expandRegion(region).lowercased()
        let raw = region.lowercased()
        if let a = candidate.admin1?.lowercased(), a == expanded || a == raw { return true }
        if let c = candidate.country?.lowercased(), c == expanded || c == raw { return true }
        if let cc = candidate.countryCode?.lowercased(), cc == raw { return true }
        return false
    }

    /// Empty list → nil. No region → the top candidate (the geocoder's own
    /// ranking). Region given → the first candidate matching it, or nil if none
    /// (INV-2: NEVER fall through to the top when a region was specified).
    static func bestMatch(candidates: [Candidate], region: String?) -> Candidate? {
        guard !candidates.isEmpty else { return nil }
        guard let region, !region.isEmpty else { return candidates.first }
        return candidates.first { regionMatches(region, candidate: $0) }
    }
}
