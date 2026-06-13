import Foundation

// Live weather via IP geolocation (no permission prompt) + Open-Meteo (no key).
enum WeatherService {
    /// The three distinguishable outcomes of a lookup (INV-4): a resolved
    /// forecast, a typed city that parsed but matched no confident candidate,
    /// or a transient network/decode error. `AppModel` treats `.error` and
    /// `.notFound` differently — `.notFound` raises the alert, `.error` does not.
    enum WeatherResult {
        case success(WeatherInfo)
        case notFound
        case error
    }

    /// `city` non-nil/non-empty resolves that typed place (NEVER IP-falls-back,
    /// INV-3); empty/nil uses IP geolocation (the "Use my location" path).
    static func fetch(city: String? = nil) async -> WeatherResult {
        // Typed-city path: parse, geocode by city alone, disambiguate by region.
        // Provably never reaches geolocate() (INV-3).
        if let city, !city.trimmingCharacters(in: .whitespaces).isEmpty {
            let parsed = WeatherQuery.parse(city)
            let cityToken = parsed.city.isEmpty ? city : parsed.city
            guard let candidates = await geocodeCandidates(cityToken) else { return .error }
            guard let chosen = WeatherQuery.bestMatch(candidates: candidates, region: parsed.region) else {
                return .notFound
            }
            var label = chosen.name
            if let admin = chosen.admin1, !admin.isEmpty { label = "\(label), \(admin)" }
            else if let cc = chosen.countryCode, !cc.isEmpty { label = "\(label), \(cc)" }
            guard let info = await forecast(lat: chosen.latitude, lon: chosen.longitude, label: label) else {
                return .error
            }
            return .success(info)
        }

        // IP path (unchanged behavior): geolocate() reachable ONLY here.
        guard let (lat, lon, label) = await geolocate() else { return .error }
        guard let info = await forecast(lat: lat, lon: lon, label: label) else { return .error }
        return .success(info)
    }

    /// Open-Meteo forecast request for a coordinate; nil on network/decode
    /// failure. Forecast math is byte-identical to the prior inline block.
    private static func forecast(lat: Double, lon: Double, label: String) async -> WeatherInfo? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "temperature_unit", value: "celsius"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1")
        ]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any] else { return nil }

        let temp = (current["temperature_2m"] as? Double).map { Int($0.rounded()) } ?? 0
        let feels = (current["apparent_temperature"] as? Double).map { Int($0.rounded()) } ?? temp
        let code = (current["weather_code"] as? Int) ?? 0
        var hi = temp, lo = temp
        if let daily = json["daily"] as? [String: Any] {
            if let maxArr = daily["temperature_2m_max"] as? [Double], let v = maxArr.first { hi = Int(v.rounded()) }
            if let minArr = daily["temperature_2m_min"] as? [Double], let v = minArr.first { lo = Int(v.rounded()) }
        }
        return WeatherInfo(temp: temp, feels: feels, hi: hi, lo: lo,
                           condition: condition(for: code), location: label)
    }

    /// Geocode a city name via Open-Meteo (no key), returning up to 10 decoded
    /// candidates for the seam to disambiguate. nil ONLY on request/decode
    /// failure (an empty results list maps to `[]`, which `bestMatch` treats as
    /// not-found — distinct from this nil = error). NEVER calls geolocate().
    private static func geocodeCandidates(_ name: String) async -> [WeatherQuery.Candidate]? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            .init(name: "name", value: name),
            .init(name: "count", value: "10"),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json")
        ]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let results = json["results"] as? [[String: Any]] ?? []
        return results.compactMap { r -> WeatherQuery.Candidate? in
            guard let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else { return nil }
            return WeatherQuery.Candidate(
                name: (r["name"] as? String) ?? name,
                admin1: r["admin1"] as? String,
                country: r["country"] as? String,
                countryCode: r["country_code"] as? String,
                latitude: lat, longitude: lon)
        }
    }

    private static func geolocate() async -> (Double, Double, String)? {
        // Primary: ipwho.is (HTTPS, no key).
        if let url = URL(string: "https://ipwho.is/"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (json["success"] as? Bool) == true,
           let lat = json["latitude"] as? Double, let lon = json["longitude"] as? Double {
            return (lat, lon, (json["city"] as? String) ?? "Your area")
        }
        // Fallback: ipapi.co.
        if let url = URL(string: "https://ipapi.co/json/"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let lat = json["latitude"] as? Double, let lon = json["longitude"] as? Double {
            return (lat, lon, (json["city"] as? String) ?? "Your area")
        }
        return nil
    }

    // WMO weather interpretation codes -> short description.
    private static func condition(for code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1, 2: return "Partly sunny"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "—"
        }
    }
}
