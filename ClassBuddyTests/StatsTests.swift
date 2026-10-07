import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Globale Statistiken: Berechnungen und Zähler")
struct StatsTests {
    init() {
        AppLanguage.current = .german
    }

    private static let calendar = Calendar.school

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    @Test("Schultage bis zu den Ferien: Wochenenden und Feiertage zählen nicht")
    func nextHoliday() throws {
        let holidays = [
            HolidayRange(name: "Herbstferien", start: Self.day(2026, 10, 19), end: Self.day(2026, 10, 30), isSchoolHoliday: true),
            HolidayRange(name: "Einheit", start: Self.day(2026, 10, 3), end: Self.day(2026, 10, 3), isSchoolHoliday: false),
            HolidayRange(name: "Feiertag", start: Self.day(2026, 10, 7), end: Self.day(2026, 10, 7), isSchoolHoliday: false),
        ]
        // Di 6.10. bis Fr 16.10.: 9 Wochentage, davon 7.10. frei → 8.
        let next = try #require(StatsLogic.nextHoliday(holidays, weekdays: Array(0..<5), today: Self.day(2026, 10, 6)))
        #expect(next.name == "Herbstferien")
        #expect(next.schoolDays == 8)
        #expect(StatsLogic.nextHoliday([], weekdays: Array(0..<5), today: .now) == nil)
    }

    @Test("Schuljahr zwischen den Sommerferien, sonst August bis Juli")
    func schoolYear() {
        let holidays = [
            HolidayRange(name: "Sommerferien", start: Self.day(2026, 7, 9), end: Self.day(2026, 8, 21), isSchoolHoliday: true),
            HolidayRange(name: "Sommerferien", start: Self.day(2027, 7, 15), end: Self.day(2027, 8, 27), isSchoolHoliday: true),
            HolidayRange(name: "Herbstferien", start: Self.day(2026, 10, 19), end: Self.day(2026, 10, 30), isSchoolHoliday: true),
        ]
        let year = StatsLogic.schoolYear(holidays, today: Self.day(2026, 10, 6))
        #expect(year.start == Self.day(2026, 8, 22))
        #expect(year.end == Self.day(2027, 7, 15))

        let fallback = StatsLogic.schoolYear([], today: Self.day(2027, 3, 1))
        #expect(fallback.start == Self.day(2026, 8, 1))
        #expect(fallback.end == Self.day(2027, 8, 1))
        #expect(StatsLogic.progress(of: fallback, at: Self.day(2020, 1, 1)) == 0)
    }

    @Test("Geburtstage je Monat und Altersverteilung")
    func birthdays() {
        let birthdays = [Self.day(2013, 1, 5), Self.day(2013, 1, 20), Self.day(2012, 12, 1)]
        let months = StatsLogic.birthdaysPerMonth(birthdays)
        #expect(months[0] == 2)
        #expect(months[11] == 1)
        let ages = StatsLogic.ageDistribution(birthdays, today: Self.day(2026, 10, 6))
        #expect(ages.map(\.age) == [13])
        #expect(ages.map(\.count) == [3])
    }

    @Test("Stundenplan-Belegung zählt gleichzeitige Stunden")
    func heatmap() {
        let cells = StatsLogic.heatmap([(0, 1), (0, 1), (2, 3)])
        #expect(cells[.init(weekday: 0, slot: 1)] == 2)
        #expect(cells[.init(weekday: 2, slot: 3)] == 1)
    }

    @Test("Zähler: erhöhen, nie negativ, Anzeige")
    func counters() throws {
        let defaults = try #require(UserDefaults(suiteName: "StatsTests-\(UUID().uuidString)"))
        FunStat.randomPicks.increment(in: defaults)
        FunStat.randomPicks.increment(by: 2, in: defaults)
        FunStat.randomPicks.increment(by: -5, in: defaults)
        #expect(FunStat.randomPicks.value(in: defaults) == 3)
        FunStat.loudSeconds.set(-1, in: defaults)
        #expect(FunStat.loudSeconds.value(in: defaults) == 0)
        #expect(FunStat.timerMinutes.formatted(135) == "2 h 15 min")
        #expect(FunStat.loudSeconds.formatted(200) == "3 min 20 s")
    }

    @Test("Zähler im Excel hin und zurück")
    func backupRoundTrip() throws {
        let container = try ModelContainer(for: SchoolClass.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let values: [FunStat: Int] = [.appLaunches: 42, .groupsDealt: 7, .timerMinutes: 90]
        let data = try Backup.export(
            context: ModelContext(container), settings: SchoolSettings.Values(), appearance: .system, funStats: values
        )
        let target = try ModelContainer(for: SchoolClass.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let result = try Backup.import(data, context: ModelContext(target), currentSettings: SchoolSettings.Values())
        let imported = try #require(result.settings.funStats)
        #expect(imported[.appLaunches] == 42)
        #expect(imported[.groupsDealt] == 7)
        #expect(imported[.randomPicks] == 0)
    }
}

@Suite("Kachel Sekretariat: Telefon- und Mail-Links")
struct SecretariatCardTests {
    @Test("Telefonnummer wird zu tel: mit Ziffern")
    func phone() {
        #expect(SecretariatCard.phoneURL("+49 (0) 30 / 123-45")?.absoluteString == "tel:+4903012345")
        #expect(SecretariatCard.phoneURL("030 12345")?.absoluteString == "tel:03012345")
        #expect(SecretariatCard.phoneURL("") == nil)
    }

    @Test("E-Mail nur mit @ und ohne Leerzeichen")
    func mail() {
        #expect(SecretariatCard.mailURL(" sekretariat@schule.de ")?.absoluteString == "mailto:sekretariat@schule.de")
        #expect(SecretariatCard.mailURL("keine adresse") == nil)
        #expect(SecretariatCard.mailURL("") == nil)
    }
}
