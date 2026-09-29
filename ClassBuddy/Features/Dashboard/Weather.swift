import Foundation
import SwiftUI

/// Wetter am Schulort über Open-Meteo (open-meteo.com, frei, ohne Schlüssel, CC BY 4.0).
/// Der Ort kommt aus der Schuladresse (Ort, PLZ zur Unterscheidung gleichnamiger Orte) –
/// es wird kein Standort des Geräts
/// verwendet und keine personenbezogenen Daten gesendet.
nonisolated enum WeatherService {
    struct Snapshot: Equatable, Sendable {
        let place: String
        let temperature: Double
        let high: Double
        let low: Double
        let condition: WeatherCondition
        let fetchedAt: Date
    }

    enum WeatherError: LocalizedError {
        case noLocation
        case placeNotFound
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noLocation: "Ort der Schule in den Schuleinstellungen eintragen"
            case .placeNotFound: "Schulort nicht gefunden"
            case .badResponse: "Wetter nicht verfügbar"
            }
        }
    }

    /// Suchbegriff für den Ort (die Ortssuche von Open-Meteo findet deutsche PLZ nicht zuverlässig).
    static func placeQuery(for school: SchoolInfo) -> String? {
        let city = school.city.trimmingCharacters(in: .whitespaces)
        return city.isEmpty ? nil : city
    }

    private static let cache = Cache()
    private static let maxAge: TimeInterval = 30 * 60

    /// Wetter laden (höchstens alle 30 Minuten neu, sonst aus dem Speicher).
    static func load(for school: SchoolInfo, federalStateName: String? = nil) async throws -> Snapshot {
        guard let query = placeQuery(for: school) else { throw WeatherError.noLocation }
        if let cached = await cache.snapshot(for: query), Date.now.timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached
        }
        let place = try await geocode(
            query,
            postalCode: school.postalCode.trimmingCharacters(in: .whitespaces),
            federalStateName: federalStateName
        )
        let snapshot = try await forecast(for: place)
        await cache.store(snapshot, for: query)
        return snapshot
    }

    // MARK: Open-Meteo

    private struct GeocodingResponse: Decodable {
        struct Place: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let postcodes: [String]?
            /// Bundesland
            let admin1: String?
        }

        let results: [Place]?
    }

    private struct ForecastResponse: Decodable {
        let current: ForecastCurrent
        let daily: ForecastDaily
    }

    private struct ForecastCurrent: Decodable {
        let temperature2m: Double
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    private struct ForecastDaily: Decodable {
        let maximum: [Double]
        let minimum: [Double]

        enum CodingKeys: String, CodingKey {
            case maximum = "temperature_2m_max"
            case minimum = "temperature_2m_min"
        }
    }

    /// Bei gleichnamigen Orten gewinnt: passende PLZ, dann passendes Bundesland, sonst der erste (größte) Treffer.
    private static func geocode(_ query: String, postalCode: String, federalStateName: String?) async throws -> GeocodingResponse.Place {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "de"),
            URLQueryItem(name: "countryCode", value: "DE"),
        ]
        let response: GeocodingResponse = try await fetch(components.url!)
        let places = response.results ?? []
        let byPostalCode = places.first { !postalCode.isEmpty && $0.postcodes?.contains(postalCode) == true }
        let byState = places.first { federalStateName != nil && $0.admin1 == federalStateName }
        guard let place = byPostalCode ?? byState ?? places.first else {
            throw WeatherError.placeNotFound
        }
        return place
    }

    private static func forecast(for place: GeocodingResponse.Place) async throws -> Snapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        let response: ForecastResponse = try await fetch(components.url!)
        return Snapshot(
            place: place.name,
            temperature: response.current.temperature2m,
            high: response.daily.maximum.first ?? response.current.temperature2m,
            low: response.daily.minimum.first ?? response.current.temperature2m,
            condition: WeatherCondition(code: response.current.weatherCode, isDay: response.current.isDay == 1),
            fetchedAt: .now
        )
    }

    private static func fetch<Response: Decodable>(_ url: URL) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherError.badResponse }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private actor Cache {
        private var snapshots: [String: Snapshot] = [:]

        func snapshot(for key: String) -> Snapshot? { snapshots[key] }
        func store(_ snapshot: Snapshot, for key: String) { snapshots[key] = snapshot }
    }
}

/// Wetterlage nach WMO-Code (wie von Open-Meteo geliefert), mit deutscher Beschreibung und SF Symbol.
nonisolated struct WeatherCondition: Equatable, Sendable {
    let title: String
    let symbol: String

    init(code: Int, isDay: Bool) {
        let entry = Self.table.first { $0.codes.contains(code) }
        title = entry?.title ?? "Unbekannt"
        symbol = (isDay ? entry?.day : entry?.night) ?? "cloud.fill"
    }

    private struct Entry {
        let codes: Set<Int>
        let title: String
        let day: String
        let night: String
    }

    /// WMO-Wettercodes → Beschreibung, Symbol tagsüber / nachts.
    private static let table: [Entry] = [
        Entry(codes: [0], title: "Klar", day: "sun.max.fill", night: "moon.stars.fill"),
        Entry(codes: [1], title: "Überwiegend klar", day: "sun.max.fill", night: "moon.fill"),
        Entry(codes: [2], title: "Teilweise bewölkt", day: "cloud.sun.fill", night: "cloud.moon.fill"),
        Entry(codes: [3], title: "Bedeckt", day: "cloud.fill", night: "cloud.fill"),
        Entry(codes: [45, 48], title: "Nebel", day: "cloud.fog.fill", night: "cloud.fog.fill"),
        Entry(codes: [51, 53, 55], title: "Nieselregen", day: "cloud.drizzle.fill", night: "cloud.drizzle.fill"),
        Entry(codes: [56, 57, 66, 67], title: "Gefrierender Regen", day: "cloud.sleet.fill", night: "cloud.sleet.fill"),
        Entry(codes: [61, 63], title: "Regen", day: "cloud.rain.fill", night: "cloud.rain.fill"),
        Entry(codes: [65], title: "Starker Regen", day: "cloud.heavyrain.fill", night: "cloud.heavyrain.fill"),
        Entry(codes: [71, 73, 75, 77], title: "Schnee", day: "cloud.snow.fill", night: "cloud.snow.fill"),
        Entry(codes: [80, 81, 82], title: "Regenschauer", day: "cloud.sun.rain.fill", night: "cloud.moon.rain.fill"),
        Entry(codes: [85, 86], title: "Schneeschauer", day: "cloud.snow.fill", night: "cloud.snow.fill"),
        Entry(codes: [95], title: "Gewitter", day: "cloud.bolt.rain.fill", night: "cloud.bolt.rain.fill"),
        Entry(codes: [96, 99], title: "Gewitter mit Hagel", day: "cloud.bolt.rain.fill", night: "cloud.bolt.rain.fill"),
    ]
}

/// Kachel „Wetter“: Temperatur und Wetterlage am Schulort. Antippen lädt neu.
struct WeatherCard: View {
    let school: SchoolInfo
    /// Bundesland (z. B. „Nordrhein-Westfalen“) zur Unterscheidung gleichnamiger Orte.
    var federalStateName: String?

    @State private var snapshot: WeatherService.Snapshot?
    @State private var errorText: String?
    @State private var reloadToken = 0

    var body: some View {
        StatCard(
            title: DashboardBuiltInCard.weather.title,
            value: snapshot.map { "\(Int($0.temperature.rounded()))°" } ?? "–",
            detail: detail,
            symbol: .system(snapshot?.condition.symbol ?? "cloud.sun"),
            isSensitive: false
        ) {
            reloadToken += 1
        }
        .task(id: "\(WeatherService.placeQuery(for: school) ?? "")-\(reloadToken)") {
            await load()
        }
    }

    private var detail: String {
        if let snapshot {
            let range = "↑ \(Int(snapshot.high.rounded()))° ↓ \(Int(snapshot.low.rounded()))°"
            return "\(snapshot.condition.title) · \(range) · \(snapshot.place)"
        }
        return errorText ?? "Wird geladen …"
    }

    private func load() async {
        do {
            snapshot = try await WeatherService.load(for: school, federalStateName: federalStateName)
            errorText = nil
        } catch {
            snapshot = nil
            errorText = error.localizedDescription
        }
    }
}

/// Kachel „Datum & Uhrzeit“ (minütlich aktualisiert).
struct DateTimeCard: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            let date = context.date
            let week = Calendar.school.component(.weekOfYear, from: date)
            StatCard(
                title: DashboardBuiltInCard.dateTime.title,
                value: date.formatted(date: .omitted, time: .shortened),
                detail: "\(date.formatted(.dateTime.weekday(.wide).day().month(.wide))) · KW \(week)",
                symbol: DashboardBuiltInCard.dateTime.symbol,
                isSensitive: false
            )
        }
    }
}
