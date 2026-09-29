import Foundation

/// Kommende Geburtstage einer Klasse (reine Berechnung, testbar).
enum Birthdays {
    struct Upcoming {
        let student: Student
        /// Nächster Geburtstag (Tagesbeginn), heute zählt mit.
        let date: Date
        let daysUntil: Int
        let turningAge: Int
    }

    /// Alle Schüler mit Geburtstag, nach dem nächsten Termin sortiert.
    /// 29. Februar: in Nicht-Schaltjahren am 1. März.
    static func upcoming(in students: [Student], today: Date = .now) -> [Upcoming] {
        let calendar = Calendar.school
        let start = calendar.startOfDay(for: today)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: start) else { return [] }

        return students.compactMap { student -> Upcoming? in
            guard let birthday = student.birthday else { return nil }
            let parts = calendar.dateComponents([.month, .day], from: birthday)
            guard let next = calendar.nextDate(after: yesterday, matching: parts, matchingPolicy: .nextTime) else { return nil }
            return Upcoming(
                student: student,
                date: next,
                daysUntil: calendar.dateComponents([.day], from: start, to: next).day ?? 0,
                turningAge: calendar.component(.year, from: next) - calendar.component(.year, from: birthday)
            )
        }
        .sorted { $0.date < $1.date }
    }

    /// „Heute 🎉 · wird 13 · +1“ für die Kachel.
    static func detail(for upcoming: [Upcoming]) -> String {
        guard let first = upcoming.first else { return "Keine Geburtstage eingetragen" }
        let when = first.daysUntil == 0 ? "Heute 🎉" : first.daysUntil == 1 ? "Morgen" : "in \(first.daysUntil) Tagen"
        let sameDay = upcoming.filter { $0.daysUntil == first.daysUntil }.count - 1
        return "\(when) · wird \(first.turningAge)" + (sameDay > 0 ? " · +\(sameDay)" : "")
    }
}

/// Stand der laufenden Stunde für die Kachel „Aktuelle Stunde“ (reine Berechnung, testbar).
enum LessonProgress {
    /// Wert (Restzeit oder Hinweis) und Detailzeile zum Zeitpunkt `now`.
    static func state(schedule: LessonSchedule, visibleWeekdays: [Int], now: Date) -> (value: String, detail: String) {
        let calendar = Calendar.school
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let second = calendar.component(.second, from: now)
        let isSchoolDay = visibleWeekdays.contains(calendar.mondayBasedWeekday(of: now)) && schedule.holiday(on: now) == nil

        guard isSchoolDay, let slot = schedule.slots.first(where: { $0.start <= minute && minute < $0.end }) else {
            let next = isSchoolDay ? schedule.slots.first { $0.start > minute } : nil
            let hint = next.map { "Nächste: \($0.number). Stunde um \($0.start.clockString)" } ?? "Heute kein Unterricht mehr"
            return ("Keine aktive Stunde", hint)
        }

        // Auf volle Minuten aufrunden: 22:10 übrig → „23 min“.
        let remainingSeconds = slot.end * 60 - (minute * 60 + second)
        let remaining = (remainingSeconds + 59) / 60
        let value = remaining >= 60 ? "\(remaining / 60) h \(remaining % 60) min" : "\(remaining) min"

        var parts = ["\(slot.number). Stunde"]
        if let lesson = schedule.lesson(on: now, slotIndex: slot.index), let schoolClass = lesson.schoolClass {
            parts.append(schoolClass.shortName)
            if !lesson.subject.isEmpty { parts.append(lesson.subject) }
        } else {
            parts.append("frei")
        }
        return (value, parts.joined(separator: " · "))
    }
}

/// Unterrichtszeit der aktuellen Woche laut Kalender (reine Berechnung, testbar).
enum WeeklyWorkload {
    struct Result: Equatable {
        /// Bereits gehaltene Minuten (laufende Stunde anteilig).
        let doneMinutes: Int
        let totalMinutes: Int

        var fraction: Double { totalMinutes == 0 ? 0 : Double(doneMinutes) / Double(totalMinutes) }
    }

    /// Alle Stunden der Woche von `now` (Montag bis Sonntag), Ferien und Einzelstunden berücksichtigt.
    static func compute(schedule: LessonSchedule, now: Date) -> Result {
        let calendar = Calendar.school
        let weekStart = calendar.startOfWeek(for: now)
        var done = 0
        var total = 0

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            for slot in schedule.slots where schedule.lesson(on: day, slotIndex: slot.index) != nil {
                let length = slot.end - slot.start
                total += length
                guard let start = calendar.date(byAdding: .minute, value: slot.start, to: day),
                      let end = calendar.date(byAdding: .minute, value: slot.end, to: day)
                else { continue }
                if now >= end {
                    done += length
                } else if now > start {
                    done += Int(now.timeIntervalSince(start) / 60)
                }
            }
        }
        return Result(doneMinutes: done, totalMinutes: total)
    }

    /// Minuten → „12,5 h“ (deutsches Format, höchstens eine Nachkommastelle).
    static func hours(_ minutes: Int) -> String {
        let value = (Double(minutes) / 60).formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "de_DE")))
        return "\(value) h"
    }
}
