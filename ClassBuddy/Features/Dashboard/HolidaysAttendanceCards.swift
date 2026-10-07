import SwiftData
import SwiftUI

/// Kachel „Ferien“: Schultage bis zu den nächsten Ferien (wie in den Statistiken), in den Ferien deren Ende.
/// Ohne importierte Ferien ein Hinweis; Antippen öffnet dann die Einstellungen, sonst den Kalender am Ferienbeginn.
struct HolidaysCard: View {
    @Environment(AppModel.self) private var app
    @Environment(SchoolSettings.self) private var settings
    @Query private var holidays: [Holiday]

    private struct Display {
        let value: String
        let detail: String
        /// Ferienbeginn (Antippen öffnet dort den Kalender); `nil` = Einstellungen öffnen.
        let date: Date?
    }

    var body: some View {
        let card = DashboardBuiltInCard.holidays
        TimelineView(.everyMinute) { context in
            let state = state(at: context.date)
            StatCard(title: card.title, value: state.value, detail: state.detail, symbol: card.symbol, isSensitive: false) {
                if let date = state.date {
                    app.openCalendar(focusing: nil, at: date)
                } else {
                    app.open(.settings)
                }
            }
        }
    }

    private func state(at now: Date) -> Display {
        let ranges = holidays.map { HolidayRange(name: $0.name, start: $0.startDate, end: $0.endDate, isSchoolHoliday: $0.isSchoolHoliday) }
        guard ranges.contains(where: \.isSchoolHoliday) else {
            return Display(value: "–", detail: loc("Ferien in den Schuleinstellungen importieren"), date: nil)
        }
        if let current = ranges.first(where: { $0.isSchoolHoliday && $0.contains(now, calendar: .school) }) {
            return Display(value: loc("Ferien"), detail: loc("\(current.name) · bis \(current.end.appDate)"), date: current.start)
        }
        guard let next = StatsLogic.nextHoliday(ranges, weekdays: settings.visibleWeekdays, today: now) else {
            return Display(value: "–", detail: loc("Keine weiteren Ferien importiert"), date: nil)
        }
        return Display(value: loc("\(next.schoolDays) Tage"), detail: loc("Schultage bis \(next.name)"), date: next.start)
    }
}

/// Kachel „Anwesenheit“: wer heute in einer Stunde der Klasse fehlte oder zu spät kam (Erfassung im Sitzplan).
/// Antippen öffnet den Sitzplan der laufenden bzw. nächsten Stunde mit Raum, sonst die Raumübersicht.
struct AttendanceCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.device) private var device
    @Environment(SchoolSettings.self) private var settings
    @Query private var lessons: [Lesson]
    @Query private var holidays: [Holiday]
    let schoolClass: SchoolClass

    var body: some View {
        let card = DashboardBuiltInCard.attendance
        TimelineView(.everyMinute) { context in
            let summary = Self.summary(of: schoolClass.students, on: context.date)
            StatCard(
                title: card.title,
                value: schoolClass.students.isEmpty ? "–" : "\(summary.present)/\(schoolClass.students.count)",
                detail: detail(summary),
                symbol: card.symbol
            ) {
                openSeatingPlan(now: context.date)
            }
        }
    }

    struct Summary: Equatable {
        var absent = 0
        var late = 0
        var present = 0
    }

    /// Je Schüler zählt der schwerste Eintrag des Tages (abwesend vor verspätet).
    static func summary(of students: [Student], on day: Date) -> Summary {
        var summary = Summary()
        for student in students {
            let today = student.absences.filter { Calendar.school.isDate($0.day, inSameDayAs: day) }
            if today.contains(where: { $0.kind == .absent }) {
                summary.absent += 1
            } else {
                if today.contains(where: { $0.kind == .late }) { summary.late += 1 }
                summary.present += 1
            }
        }
        return summary
    }

    private func detail(_ summary: Summary) -> String {
        if schoolClass.students.isEmpty { return loc("Noch keine Schüler") }
        if summary.absent == 0 && summary.late == 0 { return loc("Heute keine Fehlzeiten") }
        return [
            summary.absent > 0 ? loc("\(summary.absent) abwesend") : nil,
            summary.late > 0 ? loc("\(summary.late) verspätet") : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func openSeatingPlan(now: Date) {
        let schedule = LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots)
        if let result = RoomLocator.locate(schedule: schedule, classID: schoolClass.id, now: now),
           result.next.lesson.schoolClass?.id == schoolClass.id {
            app.openSeatingPlan(room: result.room, schoolClass: schoolClass, subject: result.next.lesson.subject)
        } else {
            app.openRooms(isPhone: device.isPhone)
        }
    }
}
