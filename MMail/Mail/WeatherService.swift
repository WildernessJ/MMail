import Foundation

// Live weather via IP geolocation (no permission prompt) + Open-Meteo (no key).
enum WeatherService {
    /// `city` non-nil/non-empty geocodes that place; otherwise IP geolocation.
    static func fetch(city: String? = nil) async -> WeatherInfo? {
        let located: (Double, Double, String)?
        if let city, !city.trimmingCharacters(in: .whitespaces).isEmpty {
            located = await geocode(city)
        } else {
            located = await geolocate()
        }
        guard let (lat, lon, city) = located else { return nil }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "temperature_unit", value: "fahrenheit"),
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
                           condition: condition(for: code), location: city)
    }

    /// Resolve a city name to coordinates via Open-Meteo geocoding (no key).
    private static func geocode(_ name: String) async -> (Double, Double, String)? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            .init(name: "name", value: name),
            .init(name: "count", value: "1"),
            .init(name: "language", value: "en"),
            .init(name: "format", value: "json")
        ]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]], let first = results.first,
              let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else { return nil }
        var label = (first["name"] as? String) ?? name
        if let admin = first["admin1"] as? String, !admin.isEmpty { label = "\(label), \(admin)" }
        else if let country = first["country_code"] as? String, !country.isEmpty { label = "\(label), \(country)" }
        return (lat, lon, label)
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
