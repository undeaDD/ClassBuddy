import Foundation
import Testing
@testable import ClassBuddy

@Suite("Einstellungen, Navigation & Katalog")
struct ConfigurationTests {
    /// Erwartete Texte sind deutsch – unabhängig von der Sprache des Simulators.
    init() {
        AppLanguage.current = .german
    }

    // MARK: Einstellungen

    @Test("Gespeicherte Einstellungen älterer Versionen: fehlende Felder bekommen Standardwerte")
    func decodesPartialSettings() throws {
        let json = Data(#"{"dayStart": 500, "showWeekends": true}"#.utf8)
        let values = try JSONDecoder().decode(SchoolSettings.Values.self, from: json)
        let defaults = SchoolSettings.Values()

        #expect(values.dayStart == 500)
        #expect(values.showWeekends)
        #expect(values.dayEnd == defaults.dayEnd)
        // Pausen haben zufällige IDs – verglichen werden Beginn und Dauer.
        #expect(values.breaks.map(\.start) == defaults.breaks.map(\.start))
        #expect(values.breaks.map(\.duration) == defaults.breaks.map(\.duration))
        #expect(values.school == SchoolInfo())
        #expect(values.teacher == TeacherProfile())
    }

    @Test("Einstellungen überstehen Speichern und Laden")
    func settingsRoundTrip() throws {
        var values = SchoolSettings.Values()
        values.school.name = "Testschule"
        values.teacher.gender = .diverse
        values.federalState = "DE-NW"

        let decoded = try JSONDecoder().decode(SchoolSettings.Values.self, from: JSONEncoder().encode(values))
        #expect(decoded == values)
    }

    @Test("Schul-Website: https wird ergänzt, http abgelehnt", arguments: [
        ("schule.de", "https://schule.de"), ("http://schule.de", nil), ("", nil),
    ])
    func schoolWebsite(input: String, expected: String?) {
        var school = SchoolInfo()
        school.website = input
        #expect(school.websiteURL?.absoluteString == expected)
    }

    @Test("Name der Lehrkraft")
    func teacherName() {
        #expect(TeacherProfile(firstName: "Dominic", lastName: "Drees").fullName == "Dominic Drees")
        #expect(TeacherProfile().fullName.isEmpty)
    }

    // MARK: Navigation

    @Test("Tab-Leiste zeigt Übersicht, Kalender und Schüler")
    func tabBar() {
        #expect(AppTab.allCases.filter(\.isInTabBar) == [.dashboard, .calendar, .students])
    }

    @Test("iPad: oben fest nur Übersicht und Kalender")
    func padTabBar() {
        #expect(AppTab.allCases.filter(\.isInPadTabBar) == [.dashboard, .calendar])
    }

    @Test("Tab- und Gruppen-IDs sind eindeutig und stabil")
    func customizationIDs() {
        let ids = AppTab.allCases.map(\.customizationID) + AppTabSection.allCases.map(\.customizationID)
        #expect(Set(ids).count == ids.count)
        #expect(AppTab.dashboard.customizationID == "tab.dashboard")
    }

    @Test("Jeder Tab gehört zu genau einer Gruppe")
    func sections() {
        let grouped = AppTabSection.allCases.flatMap(\.tabs)
        #expect(Set(grouped) == Set(AppTab.allCases))
        #expect(grouped.count == AppTab.allCases.count)
        #expect(AppTabSection.schoolClass.tabs == [.rooms, .board, .checklists, .notes])
        #expect(AppTabSection.other.tabs == [.feedback, .settings])
        #expect(AppTabSection.titled == [.schoolClass, .other])
    }

    @Test("Klassen-Button nur auf Seiten mit Klassenbezug")
    func classSelection() {
        #expect(AppTab.allCases.filter { !$0.usesClassSelection } == [.feedback, .settings])
    }

    @Test("Nur Feedback ist ein Aktions-Tab")
    func actionTabs() {
        #expect(AppTab.allCases.filter(\.isAction) == [.feedback])
    }

    // MARK: Kachel-Katalog

    @Test("Neue eingebaute Kacheln starten ausgeblendet, Schüler + Nächste Stunde sichtbar")
    func builtInDefaults() {
        let visible = DashboardBuiltInCard.allCases.filter { !$0.isHiddenByDefault }
        #expect(visible == [.students, .nextLesson])
    }

    @Test("Kachel-IDs sind eindeutig")
    func builtInIDs() {
        let ids = DashboardBuiltInCard.allCases.map(\.rawValue)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Eigene Kacheln sind mehrfach hinzufügbar, eingebaute nicht")
    func reusableTemplates() {
        #expect(CardTemplate.reusable.allSatisfy { $0.isReusable })
        #expect(CardTemplate.reusable.contains(.shortcut))
        #expect(!CardTemplate.builtIn(.weather).isReusable)
    }

    // MARK: Rechtliches

    @Test("Impressum, Datenschutz und Lizenzen liegen in der App", arguments: LegalDocument.allCases)
    func legalDocumentsExist(document: LegalDocument) throws {
        let url = try #require(document.url)
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(html.contains("<html"))
    }
}
