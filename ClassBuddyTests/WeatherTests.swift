import Foundation
import Testing
@testable import ClassBuddy

@Suite("Wetter")
struct WeatherTests {
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
}
