import Foundation

/// Ermittelt, welche Stunde an einem Tag in einem Slot stattfindet
/// (Einzelstunde vor wöchentlicher Stunde, wöchentliche Stunden entfallen in Ferien).
struct LessonSchedule {
    let lessons: [Lesson]
    let holidays: [Holiday]
    let slots: [LessonSlot]

    private let calendar = Calendar.school

    func holiday(on date: Date) -> Holiday? {
        holidays.first { $0.contains(date) }
    }

    func lesson(on date: Date, slotIndex: Int) -> Lesson? {
        if let single = lessons.first(where: {
            !$0.isRecurring && $0.slotIndex == slotIndex && $0.date.map { calendar.isDate($0, inSameDayAs: date) } == true
        }) {
            return single
        }
        guard holiday(on: date) == nil else { return nil }
        let weekday = calendar.mondayBasedWeekday(of: date)
        return lessons.first { $0.isRecurring && $0.weekday == weekday && $0.slotIndex == slotIndex }
    }

    /// Nächste (noch nicht beendete) Stunde einer Klasse ab `now`, max. 8 Wochen voraus.
    func nextLesson(forClass classID: UUID, after now: Date = .now) -> NextLesson? {
        let today = calendar.startOfDay(for: now)
        for offset in 0..<56 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for slot in slots {
                guard let lesson = lesson(on: day, slotIndex: slot.index),
                      lesson.schoolClass?.id == classID,
                      let end = calendar.date(byAdding: .minute, value: slot.end, to: day),
                      end > now,
                      let start = calendar.date(byAdding: .minute, value: slot.start, to: day)
                else { continue }
                return NextLesson(start: start, slot: slot, lesson: lesson)
            }
        }
        return nil
    }
}

/// Nächste Stunde einer Klasse: Beginn, Slot im Raster und die Stunde selbst.
struct NextLesson {
    let start: Date
    let slot: LessonSlot
    let lesson: Lesson
}
