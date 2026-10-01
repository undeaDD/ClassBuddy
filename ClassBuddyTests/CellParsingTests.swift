import Foundation
import Testing
@testable import ClassBuddy

/// Tolerantes Lesen von Zellwerten – auch nach dem Bearbeiten in Excel/Numbers.
@Suite("Excel-Zellwerte")
struct CellParsingTests {
    /// Erwartete Texte sind deutsch – unabhängig von der Sprache des Simulators.
    init() {
        AppLanguage.current = .german
    }

    private typealias Cell = Backup.Cell

    private nonisolated static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        Calendar.school.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("Datum: ISO, deutsch, zweistelliges Jahr, Excel-Seriennummer", arguments: [
        ("2026-09-29", day(2026, 9, 29)),
        ("29.09.2026", day(2026, 9, 29)),
        ("1.3.14", day(2014, 3, 1)),
        ("46294", day(2026, 9, 29)),
        ("2026-09-29 08:30", day(2026, 9, 29)),
    ])
    func parseDate(text: String, expected: Date) {
        #expect(Cell.parseDate(text) == expected)
    }

    @Test("Datum: ungültige Werte", arguments: ["", "  ", "morgen", "2026/09/29"])
    func parseDateInvalid(text: String) {
        #expect(Cell.parseDate(text) == nil)
    }

    @Test("Datum mit Uhrzeit, auch als Excel-Seriennummer mit Tagesbruchteil")
    func parseDateTime() {
        #expect(Cell.parseDateTime("2026-09-29 08:30") == Self.day(2026, 9, 29, hour: 8, minute: 30))
        #expect(Cell.parseDateTime("46294.354166666664") == Self.day(2026, 9, 29, hour: 8, minute: 30))
        #expect(Cell.parseDateTime("2026-09-29") == Self.day(2026, 9, 29))
    }

    @Test("Uhrzeit", arguments: [("08:05", 485), ("0:00", 0), ("23:59", 1439), ("0.5", 720), ("25:00", nil), ("abc", nil)])
    func parseTime(text: String, expected: Int?) {
        #expect(Cell.parseTime(text) == expected)
    }

    @Test("Wochentag: Name, Kürzel oder Zahl", arguments: [
        ("Montag", 0), ("mittwoch", 2), ("Mi", 2), ("Do", 3), ("So", 6), ("1", 0), ("7", 6), ("8", nil), ("x", nil),
    ])
    func parseWeekday(text: String, expected: Int?) {
        #expect(Cell.parseWeekday(text) == expected)
    }

    @Test("Ja/Nein", arguments: [
        ("ja", true), ("JA", true), ("x", true), ("true", true), ("nein", false), ("0", false), ("vielleicht", nil),
    ])
    func parseBool(text: String, expected: Bool?) {
        #expect(Cell.parseBool(text) == expected)
    }

    @Test("Geschlecht", arguments: [
        ("weiblich", Gender.female), ("w", .female), ("female", .female),
        ("männlich", .male), ("m", .male), ("divers", .diverse), ("d", .diverse),
    ])
    func parseGender(text: String, expected: Gender) {
        #expect(Cell.parseGender(text) == expected)
    }

    @Test("Listen mit Semikolon, Leerzeichen und leeren Einträgen")
    func parseList() {
        #expect(Cell.parseList("Mathe; Physik;;  Chemie ") == ["Mathe", "Physik", "Chemie"])
        #expect(Cell.parseList("").isEmpty)
    }

    @Test("Kachel-Typ übersteht Schreiben und Lesen", arguments: [
        DashboardLink.Kind.file, .image, .website, .shortcut, .script,
    ])
    func linkKindRoundTrip(kind: DashboardLink.Kind) {
        #expect(Cell.parseLinkKind(Cell.linkKind(kind)) == kind)
    }

    @Test("Formatierung für den Export")
    func formatting() {
        #expect(Cell.date(Self.day(2026, 3, 1)) == "2026-03-01")
        #expect(Cell.date(nil).isEmpty)
        #expect(Cell.dateTime(Self.day(2026, 3, 1, hour: 7, minute: 5)) == "2026-03-01 07:05")
        #expect(Cell.weekday(4) == "Freitag")
        #expect(Cell.weekday(9).isEmpty)
        #expect(Cell.list(["A", "B"]) == "A; B")
    }

    @Test("Tabelle: Zugriff per Spaltenname, leere Zeilen werden übersprungen")
    func table() {
        let table = Backup.Table([["Name", " Alter "], ["Emma", "12"], ["", ""], ["Leon"]])

        #expect(table.rows.count == 2)
        #expect(table.rows[0]["Name"] == "Emma")
        #expect(table.rows[0]["Alter"] == "12")
        #expect(table.rows[1]["Alter"].isEmpty)
    }

    @Test("Schlüssel/Wert-Tabelle")
    func keyValues() {
        let values = Backup.KeyValues([["Schlüssel", "Wert"], ["Name", " Testschule "], ["Ort"]])

        #expect(values["Name"] == "Testschule")
        #expect(values["Ort"].isEmpty)
        #expect(values["Fehlt"].isEmpty)
    }
}
