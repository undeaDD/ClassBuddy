import Foundation
import Testing
import WeatherKit
@testable import ClassBuddy

@Suite("Wetter")
struct WeatherTests {
    /// Erwartete Texte sind deutsch – unabhängig von der Sprache des Simulators.
    init() {
        AppLanguage.current = .german
    }

    @Test("WMO-Codes → Beschreibung", arguments: [
        (0, "Klar"), (2, "Teilweise bewölkt"), (3, "Bedeckt"), (48, "Nebel"),
        (61, "Regen"), (80, "Regenschauer"), (95, "Gewitter"), (99, "Gewitter mit Hagel"), (12_345, "Unbekannt"),
    ])
    func condition(code: Int, title: String) {
        #expect(WeatherCondition(code: code).title == title)
    }

    @Test("Ort aus den Schuleinstellungen (ohne Ort kein Abruf)")
    func placeQuery() {
        var school = SchoolInfo()
        #expect(WeatherService.placeQuery(for: school) == nil)

        school.postalCode = "50667"
        #expect(WeatherService.placeQuery(for: school) == nil)

        school.city = "  Köln "
        #expect(WeatherService.placeQuery(for: school) == "Köln")
    }

    @Test("WeatherKit-Wetterlagen → Beschreibung in der App-Sprache")
    func appleCondition() {
        #expect(WeatherCondition(apple: .clear).title == "Klar")
        #expect(WeatherCondition(apple: .mostlyCloudy).title == "Überwiegend bewölkt")
        #expect(WeatherCondition(apple: .wintryMix).title == "Schneeregen")
        #expect(WeatherCondition(apple: .scatteredThunderstorms).title == "Gewitter")
        #expect(WeatherCondition(apple: .windy).title == "Windig")
    }

    @Test("Tendenz: Vorhersage in etwa zwei Stunden, ab 1° Unterschied")
    func trend() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func hours(_ temperatures: [Double]) -> [(date: Date, temperature: Double)] {
            temperatures.enumerated().map { (now.addingTimeInterval(Double($0.offset + 1) * 3600), $0.element) }
        }
        #expect(WeatherService.trend(current: 15, hourly: hours([15.5, 16.4, 20]), now: now) == .rising)
        #expect(WeatherService.trend(current: 15, hourly: hours([14, 13.9, 10]), now: now) == .falling)
        #expect(WeatherService.trend(current: 15, hourly: hours([20, 15.4]), now: now) == .steady)
        // Nur eine Stunde voraus: der letzte Wert zählt.
        #expect(WeatherService.trend(current: 15, hourly: hours([17]), now: now) == .rising)
        // Vergangene Stunden zählen nicht; ohne Vorhersage keine Tendenz.
        #expect(WeatherService.trend(current: 15, hourly: [(now.addingTimeInterval(-3600), 30)], now: now) == nil)
        #expect(WeatherService.trend(current: 15, hourly: [], now: now) == nil)
    }
}
