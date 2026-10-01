import Foundation
import Testing
@testable import ClassBuddy

@Suite("Stundenraster")
struct LessonGridTests {
    /// Erwartete Texte sind deutsch – unabhängig von der Sprache des Simulators.
    init() {
        AppLanguage.current = .german
    }

    @Test("Standard-Raster: 8 Stunden, Pausen werden übersprungen")
    func defaultGrid() {
        let slots = SchoolSettings.Values().slots

        #expect(slots.count == 8)
        #expect(slots.map(\.timeRange) == [
            "08:00–08:45", "08:45–09:30",
            "09:50–10:35", "10:35–11:20",
            "11:35–12:20", "12:20–13:05",
            "13:50–14:35", "14:35–15:20",
        ])
        #expect(slots.map(\.number) == Array(1...8))
    }

    @Test("Stunde, die nicht vor die Pause passt, beginnt nach der Pause")
    func lessonMovesBehindBreak() {
        var values = SchoolSettings.Values()
        values.dayStart = 8 * 60
        values.dayEnd = 10 * 60
        values.lessonDuration = 45
        values.breaks = [BreakTime(start: 8 * 60 + 30, duration: 10)]

        #expect(values.slots.map(\.timeRange) == ["08:40–09:25"])
    }

    @Test("Ende vor Beginn ergibt kein Raster")
    func emptyGrid() {
        var values = SchoolSettings.Values()
        values.dayStart = 12 * 60
        values.dayEnd = 8 * 60

        #expect(values.slots.isEmpty)
    }

    @Test("Pausen außerhalb des Schultags werden ignoriert")
    func breaksOutsideDayAreIgnored() {
        var values = SchoolSettings.Values()
        values.breaks = [BreakTime(start: 6 * 60, duration: 30), BreakTime(start: 18 * 60, duration: 30)]

        #expect(values.sortedBreaks.isEmpty)
    }

    @Test("Uhrzeit-Formatierung", arguments: [(0, "00:00"), (485, "08:05"), (13 * 60 + 50, "13:50")])
    func clockString(minutes: Int, expected: String) {
        #expect(minutes.clockString == expected)
    }
}

@Suite("Tagesfenster (iPhone)")
struct VisibleDaysTests {
    private let calendar = Calendar.school
    private let schoolDays = Array(0..<5)

    private func day(_ text: String) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? .now
    }

    @Test("Mitte der Woche: gestern, heute, morgen")
    func midWeek() {
        // Mi, 30.09.2026
        #expect(calendar.visibleDays(around: day("2026-09-30"), count: 3, weekdays: schoolDays)
            == [day("2026-09-29"), day("2026-09-30"), day("2026-10-01")])
    }

    @Test("Montag: Freitag davor statt Sonntag")
    func mondaySkipsWeekend() {
        #expect(calendar.visibleDays(around: day("2026-10-05"), count: 3, weekdays: schoolDays)
            == [day("2026-10-02"), day("2026-10-05"), day("2026-10-06")])
    }

    @Test("Samstag ohne Wochenende: rückt auf Montag")
    func weekendAnchor() {
        #expect(calendar.visibleDays(around: day("2026-10-03"), count: 3, weekdays: schoolDays)
            == [day("2026-10-02"), day("2026-10-05"), day("2026-10-06")])
    }

    @Test("Mit Wochenende: jeder Tag zählt")
    func withWeekends() {
        #expect(calendar.visibleDays(around: day("2026-10-05"), count: 3, weekdays: Array(0..<7))
            == [day("2026-10-04"), day("2026-10-05"), day("2026-10-06")])
    }

    @Test("Blättern um 3 angezeigte Tage")
    func paging() {
        #expect(calendar.addingVisibleDays(3, to: day("2026-10-01"), weekdays: schoolDays) == day("2026-10-06"))
        #expect(calendar.addingVisibleDays(-3, to: day("2026-10-06"), weekdays: schoolDays) == day("2026-10-01"))
    }
}
