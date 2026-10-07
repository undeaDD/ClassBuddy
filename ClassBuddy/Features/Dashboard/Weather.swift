import CoreLocation
import Foundation
import MapKit
import OSLog
import SwiftUI
import WeatherKit

/// Wetter am Schulort. Bevorzugt Apple (Ortssuche über MapKit, Wetter über WeatherKit); fällt jeweils auf
/// Open-Meteo zurück (open-meteo.com, frei, ohne Schlüssel, CC BY 4.0) – z. B. ohne WeatherKit-Berechtigung
/// (selbst signierte Builds) oder wenn Apple nicht antwortet.
/// Der Ort kommt aus der Schuladresse (Ort, PLZ zur Unterscheidung gleichnamiger Orte) –
/// es wird kein Standort des Geräts verwendet und keine personenbezogenen Daten gesendet.
nonisolated enum WeatherService {
    struct Snapshot: Equatable, Sendable {
        let place: String
        let temperature: Double
        let high: Double
        let low: Double
        let condition: WeatherCondition
        let fetchedAt: Date
        /// Herkunft der Wetterdaten (Apple verlangt dann die Attribution auf der Kachel).
        let source: Source
        /// Nur bei Apple: offizielles Logo (hell/dunkel) und Link zu den Datenquellen.
        var attribution: Attribution?
        /// Tendenz der nächsten Stunden (`nil` ohne Stundenvorhersage).
        var trend: Trend?
    }

    enum Trend: Equatable, Sendable {
        case rising, falling, steady
    }

    /// Vergleicht die aktuelle Temperatur mit der Vorhersage in etwa zwei Stunden (bzw. dem letzten Wert davor):
    /// ab 1° Unterschied steigend bzw. fallend, sonst gleichbleibend.
    static func trend(current: Double, hourly: [(date: Date, temperature: Double)], now: Date) -> Trend? {
        let upcoming = hourly.filter { $0.date > now }.sorted { $0.date < $1.date }
        guard let target = upcoming.first(where: { $0.date >= now.addingTimeInterval(2 * 3600) }) ?? upcoming.last else { return nil }
        let delta = target.temperature - current
        if delta >= 1 { return .rising }
        if delta <= -1 { return .falling }
        return .steady
    }

    struct Attribution: Equatable, Sendable {
        let lightMarkURL: URL
        let darkMarkURL: URL
        let legalPageURL: URL
    }

    enum Source: Sendable {
        case apple, openMeteo
    }

    /// Ort mit Koordinaten (aus MapKit oder der Open-Meteo-Ortssuche).
    struct Place: Sendable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    /// Ersatz, solange das Apple-Logo lädt (oder nicht geladen werden konnte).
    static let appleMarkText = "\u{F8FF} Weather"
    static let appleLegalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    /// Letzter WeatherKit-Fehler (Debug-Menü): warum die Kachel Open-Meteo statt Apple zeigt.
    static let diagnostics = Diagnostics()

    actor Diagnostics {
        private(set) var lastAppleError: String?
        private(set) var lastSource: Source?

        func record(source: Source, appleError: String?) {
            lastSource = source
            lastAppleError = appleError
        }
    }

    private static let log = Logger(subsystem: "de.devsforge.ClassBuddy", category: "weather")

    enum WeatherError: LocalizedError {
        case noLocation
        case placeNotFound
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noLocation: loc("Ort der Schule in den Schuleinstellungen eintragen")
            case .placeNotFound: loc("Schulort nicht gefunden")
            case .badResponse: loc("Wetter nicht verfügbar")
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
        let postalCode = school.postalCode.trimmingCharacters(in: .whitespaces)
        let street = school.street.trimmingCharacters(in: .whitespaces)
        // Ganze Schuladresse als Schlüssel: andere Straße oder PLZ → neu laden.
        let cacheKey = [street, postalCode, query].joined(separator: "|")
        if let cached = await cache.snapshot(for: cacheKey), Date.now.timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached
        }
        let place: Place
        // Apple: die Schuladresse samt Straße; Open-Meteo kennt nur Orte (PLZ/Bundesland unterscheiden gleichnamige).
        if let applePlace = await appleGeocode(query, postalCode: postalCode, street: street) {
            place = applePlace
        } else {
            place = try await geocode(query, postalCode: postalCode, federalStateName: federalStateName)
        }
        let snapshot: Snapshot
        do {
            snapshot = try await appleForecast(for: place)
            await diagnostics.record(source: .apple, appleError: nil)
        } catch {
            log.info("WeatherKit nicht verfügbar, Open-Meteo: \(String(describing: error), privacy: .public)")
            await diagnostics.record(source: .openMeteo, appleError: String(describing: error))
            snapshot = try await forecast(for: place)
        }
        await cache.store(snapshot, for: cacheKey)
        return snapshot
    }

    // MARK: Apple (MapKit + WeatherKit)

    /// Ortssuche über Apple; `nil` bei Fehler oder ohne Treffer (dann Open-Meteo).
    private static func appleGeocode(_ city: String, postalCode: String, street: String) async -> Place? {
        await appleLookup(city, postalCode: postalCode, street: street)?.place
    }

    /// „Köln, Nordrhein-Westfalen, Deutschland“ → DE-NW.
    private static func appleFederalStateCode(_ city: String, postalCode: String) async -> String? {
        guard let context = await appleLookup(city, postalCode: postalCode)?.cityWithContext else { return nil }
        let parts = context.components(separatedBy: ", ")
        return HolidayImporter.federalStates.first { parts.contains($0.name) }?.code
    }

    /// Treffer der Apple-Ortssuche (Koordinaten + „Ort, Bundesland, Land“), als Sendable-Wert statt `MKMapItem`.
    private struct AppleLookup: Sendable {
        let place: Place
        let cityWithContext: String?
    }

    @MainActor
    private static func appleLookup(_ city: String, postalCode: String, street: String = "") async -> AppleLookup? {
        let place = [postalCode, city].filter { !$0.isEmpty }.joined(separator: " ")
        let address = [street, place, "Deutschland"].filter { !$0.isEmpty }.joined(separator: ", ")
        guard let request = MKGeocodingRequest(addressString: address) else { return nil }
        request.preferredLocale = Locale(identifier: "de_DE")
        do {
            guard let item = try await request.mapItems.first else { return nil }
            let coordinate = item.location.coordinate
            return AppleLookup(
                place: Place(name: city, latitude: coordinate.latitude, longitude: coordinate.longitude),
                cityWithContext: item.addressRepresentations?.cityWithContext(.full)
            )
        } catch {
            log.info("MapKit-Ortssuche fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Wirft ohne WeatherKit-Berechtigung (Entitlement fehlt, z. B. selbst signiert) oder bei Netzfehlern.
    private static func appleForecast(for place: Place) async throws -> Snapshot {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let (current, daily, hourly) = try await WeatherKit.WeatherService.shared.weather(
            for: location, including: .current, .daily, .hourly
        )
        let today = daily.first
        let temperature = current.temperature.converted(to: .celsius).value
        let attribution = try? await WeatherKit.WeatherService.shared.attribution
        return Snapshot(
            place: place.name,
            temperature: temperature,
            high: today?.highTemperature.converted(to: .celsius).value ?? temperature,
            low: today?.lowTemperature.converted(to: .celsius).value ?? temperature,
            condition: WeatherCondition(apple: current.condition),
            fetchedAt: .now,
            source: .apple,
            attribution: attribution.map {
                Attribution(lightMarkURL: $0.combinedMarkLightURL, darkMarkURL: $0.combinedMarkDarkURL, legalPageURL: $0.legalPageURL)
            },
            trend: trend(
                current: temperature,
                hourly: hourly.prefix(6).map { ($0.date, $0.temperature.converted(to: .celsius).value) },
                now: .now
            )
        )
    }

    /// Bundesland der Schule aus PLZ und Ort: über Apple (MapKit), sonst die Open-Meteo-Ortssuche.
    /// Bei Open-Meteo nur bei eindeutigem Treffer: passende PLZ oder ein einziger Ort dieses Namens.
    static func federalStateCode(for school: SchoolInfo) async -> String? {
        let postalCode = school.postalCode.trimmingCharacters(in: .whitespaces)
        guard let query = placeQuery(for: school), postalCode.count == 5, postalCode.allSatisfy(\.isNumber) else { return nil }
        if let code = await appleFederalStateCode(query, postalCode: postalCode) { return code }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "de"),
            URLQueryItem(name: "countryCode", value: "DE"),
        ]
        guard let response: GeocodingResponse = try? await fetch(components.url!) else { return nil }
        let places = response.results ?? []
        let place = places.first { $0.postcodes?.contains(postalCode) == true } ?? (places.count == 1 ? places.first : nil)
        return place?.admin1.flatMap { name in HolidayImporter.federalStates.first { $0.name == name }?.code }
    }

    // MARK: Open-Meteo (Rückfall)

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
        let hourly: ForecastHourly?
    }

    private struct ForecastHourly: Decodable {
        /// Unix-Zeit (`timeformat=unixtime`).
        let time: [Double]
        let temperature2m: [Double]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
        }
    }

    private struct ForecastCurrent: Decodable {
        let temperature2m: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
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
    private static func geocode(_ query: String, postalCode: String, federalStateName: String?) async throws -> Place {
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
        return Place(name: place.name, latitude: place.latitude, longitude: place.longitude)
    }

    private static func forecast(for place: Place) async throws -> Snapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "hourly", value: "temperature_2m"),
            URLQueryItem(name: "forecast_hours", value: "4"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        let response: ForecastResponse = try await fetch(components.url!)
        let hourly = response.hourly.map { hourly in
            zip(hourly.time, hourly.temperature2m).map { (Date(timeIntervalSince1970: $0), $1) }
        } ?? []
        return Snapshot(
            place: place.name,
            temperature: response.current.temperature2m,
            high: response.daily.maximum.first ?? response.current.temperature2m,
            low: response.daily.minimum.first ?? response.current.temperature2m,
            condition: WeatherCondition(code: response.current.weatherCode),
            fetchedAt: .now,
            source: .openMeteo,
            trend: trend(current: response.current.temperature2m, hourly: hourly, now: .now)
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

/// Wetterlage als Beschreibung in der App-Sprache – aus dem WMO-Code (Open-Meteo) bzw. von WeatherKit
/// (dessen eigene Beschreibung folgt der Systemsprache, nicht der App-Sprache).
nonisolated struct WeatherCondition: Equatable, Sendable {
    let title: String

    init(code: Int) {
        title = Self.titles.first { $0.codes.contains(code) }?.title ?? loc("Unbekannt")
    }

    init(apple condition: WeatherKit.WeatherCondition) {
        title = Self.appleTitles.first { $0.conditions.contains(condition) }?.title ?? condition.description
    }

    private static let appleTitles: [(conditions: Set<WeatherKit.WeatherCondition>, title: String)] = [
        ([.clear, .hot, .frigid], loc("Klar")),
        ([.mostlyClear], loc("Überwiegend klar")),
        ([.partlyCloudy], loc("Teilweise bewölkt")),
        ([.mostlyCloudy], loc("Überwiegend bewölkt")),
        ([.cloudy], loc("Bedeckt")),
        ([.foggy], loc("Nebel")),
        ([.haze, .smoky, .blowingDust], loc("Dunst")),
        ([.drizzle], loc("Nieselregen")),
        ([.freezingDrizzle, .freezingRain], loc("Gefrierender Regen")),
        ([.sleet, .wintryMix], loc("Schneeregen")),
        ([.rain], loc("Regen")),
        ([.heavyRain], loc("Starker Regen")),
        ([.sunShowers], loc("Regenschauer")),
        ([.snow, .heavySnow, .blizzard, .blowingSnow], loc("Schnee")),
        ([.flurries, .sunFlurries], loc("Schneeschauer")),
        ([.hail], loc("Hagel")),
        ([.thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms], loc("Gewitter")),
        ([.breezy, .windy], loc("Windig")),
        ([.hurricane, .tropicalStorm], loc("Sturm")),
    ]

    private static let titles: [(codes: Set<Int>, title: String)] = [
        ([0], loc("Klar")),
        ([1], loc("Überwiegend klar")),
        ([2], loc("Teilweise bewölkt")),
        ([3], loc("Bedeckt")),
        ([45, 48], loc("Nebel")),
        ([51, 53, 55], loc("Nieselregen")),
        ([56, 57, 66, 67], loc("Gefrierender Regen")),
        ([61, 63], loc("Regen")),
        ([65], loc("Starker Regen")),
        ([71, 73, 75, 77], loc("Schnee")),
        ([80, 81, 82], loc("Regenschauer")),
        ([85, 86], loc("Schneeschauer")),
        ([95], loc("Gewitter")),
        ([96, 99], loc("Gewitter mit Hagel")),
    ]
}

/// Kachel „Wetter“: Temperatur und Wetterlage am Schulort. Antippen lädt neu.
struct WeatherCard: View {
    let school: SchoolInfo
    /// Bundesland (z. B. „Nordrhein-Westfalen“) zur Unterscheidung gleichnamiger Orte.
    var federalStateName: String?

    @State private var snapshot: WeatherService.Snapshot?
    @State private var errorText: String?

    var body: some View {
        StatCard(
            title: DashboardBuiltInCard.weather.title,
            value: snapshot.map { "\(Int($0.temperature.rounded()))°" } ?? "–",
            detail: detail,
            symbol: DashboardBuiltInCard.weather.symbol,
            isSensitive: false,
            // Quelle am Kopf erkennbar: Apple-Logo als Link zu den Datenquellen (Pflicht bei WeatherKit),
            // sonst das eigene Symbol mit „Wetter“. Kein Antippen der Kachel (lädt beim Erscheinen, max. alle 30 min).
            brand: snapshot?.source == .apple ? brand : nil,
            valueSuffix: snapshot?.trend.map(Self.trendSuffix)
        )
        .task(id: "\(school.street)|\(school.postalCode)|\(WeatherService.placeQuery(for: school) ?? "")") {
            await load()
        }
    }

    /// Platzhalter-Pfeile, bis die Icons festgelegt sind.
    static func trendSuffix(_ trend: WeatherService.Trend) -> (text: String, accessibilityLabel: String) {
        switch trend {
        case .rising: ("↗", loc("steigend"))
        case .falling: ("↘", loc("fallend"))
        case .steady: ("→", loc("gleichbleibend"))
        }
    }

        private var brand: CardBrand {
        CardBrand(
            lightImageURL: snapshot?.attribution?.lightMarkURL,
            darkImageURL: snapshot?.attribution?.darkMarkURL,
            text: WeatherService.appleMarkText,
            link: snapshot?.attribution?.legalPageURL ?? WeatherService.appleLegalURL
        )
    }

    private var detail: String {
        if let snapshot {
            let range = "↑ \(Int(snapshot.high.rounded()))° ↓ \(Int(snapshot.low.rounded()))°"
            return "\(snapshot.condition.title) · \(range)"
        }
        return errorText ?? loc("Wird geladen …")
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
                value: date.appTime,
                detail: loc("\(date.appFormatted(.dateTime.weekday(.wide))), \(date.appDate) · KW \(week)"),
                symbol: DashboardBuiltInCard.dateTime.symbol,
                isSensitive: false
            )
        }
    }
}
