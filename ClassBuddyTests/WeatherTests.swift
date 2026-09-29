import Foundation
import Testing
import UIKit
@testable import ClassBuddy

@Suite("Wetter")
struct WeatherTests {
    @Test("WMO-Codes: Beschreibung und Symbol, tagsüber/nachts", arguments: [
        (0, true, "Klar", "sun.max.fill"),
        (0, false, "Klar", "moon.stars.fill"),
        (2, true, "Teilweise bewölkt", "cloud.sun.fill"),
        (3, false, "Bedeckt", "cloud.fill"),
        (61, true, "Regen", "cloud.rain.fill"),
        (80, false, "Regenschauer", "cloud.moon.rain.fill"),
        (95, true, "Gewitter", "cloud.bolt.rain.fill"),
        (12_345, true, "Unbekannt", "cloud.fill"),
    ])
    func condition(code: Int, isDay: Bool, title: String, symbol: String) {
        let condition = WeatherCondition(code: code, isDay: isDay)
        #expect(condition.title == title)
        #expect(condition.symbol == symbol)
    }

    @Test("Alle WMO-Codes haben ein gültiges SF Symbol")
    func symbolsExist() {
        let codes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99]
        for code in codes {
            for isDay in [true, false] {
                let symbol = WeatherCondition(code: code, isDay: isDay).symbol
                #expect(UIImage(systemName: symbol) != nil, "\(symbol) fehlt")
            }
        }
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
}
