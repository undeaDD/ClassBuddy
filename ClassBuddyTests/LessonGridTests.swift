import Foundation
import Testing
@testable import ClassBuddy

@Suite("Stundenraster")
struct LessonGridTests {
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
