import Foundation

/// Ermittelt, welche Stunde an einem Tag in einem Slot stattfindet
/// (Einzelstunde vor wiederkehrender Stunde, wiederkehrende Stunden entfallen in Ferien, „alle 2 Wochen“ nur in
/// jeder zweiten Woche). Eine Doppelstunde belegt auch den folgenden Slot, sofern dort keine eigene Stunde liegt.
///
/// Baut beim Erstellen einmal Nachschlage-Tabellen auf: Vorher durchsuchte jede Abfrage alle Stunden (jede
/// Eigenschaft ein SwiftData-Zugriff). „Wochenstunden“ fragt 7 Tage × alle Slots ab – das kostete beim Erzeugen
/// der Kachel über 100 ms und ließ die Übersicht beim Scrollen ruckeln.
struct LessonSchedule {
    let lessons: [Lesson]
    let holidays: [Holiday]
    let slots: [LessonSlot]

    private let calendar = Calendar.school
    /// Wiederkehrende Stunden nach Wochentag (0 = Montag) und Slot; es gilt die erste, die in der Woche stattfindet
    /// (so teilen sich zwei Stunden „alle 2 Wochen“ einen Slot).
    private let recurring: [RecurringKey: [Lesson]]
    /// Einzelstunden nach Tagesbeginn und Slot.
    private let single: [SingleKey: Lesson]
    /// Ferien als Tagesbereiche (Tagesbeginn, wie `Holiday.contains`).
    private let holidayDays: [HolidayDays]

    private struct HolidayDays {
        let start: Date
        let end: Date
        let holiday: Holiday
    }

    private struct RecurringKey: Hashable {
        let weekday: Int
        let slot: Int
    }

    private struct SingleKey: Hashable {
        let day: Date
        let slot: Int
    }

    init(lessons: [Lesson], holidays: [Holiday], slots: [LessonSlot]) {
        self.lessons = lessons
        self.holidays = holidays
        self.slots = slots
        var recurring: [RecurringKey: [Lesson]] = [:]
        var single: [SingleKey: Lesson] = [:]
        let calendar = Calendar.school
        for lesson in lessons {
            if lesson.isRecurring {
                recurring[RecurringKey(weekday: lesson.weekday, slot: lesson.slotIndex), default: []].append(lesson)
            } else if let date = lesson.date {
                let key = SingleKey(day: calendar.startOfDay(for: date), slot: lesson.slotIndex)
                if single[key] == nil { single[key] = lesson }
            }
        }
        self.recurring = recurring
        self.single = single
        let dayCalendar = Calendar.current
        holidayDays = holidays.map { holiday in
            HolidayDays(
                start: dayCalendar.startOfDay(for: holiday.startDate),
                end: dayCalendar.startOfDay(for: holiday.endDate),
                holiday: holiday
            )
        }
    }

    func holiday(on date: Date) -> Holiday? {
        let day = Calendar.current.startOfDay(for: date)
        return holidayDays.first { $0.start <= day && day <= $0.end }?.holiday
    }

    /// Stunde in diesem Slot, auch die zweite Hälfte einer Doppelstunde aus dem Slot davor.
    func lesson(on date: Date, slotIndex: Int) -> Lesson? {
        if let own = ownLesson(on: date, slotIndex: slotIndex) { return own }
        guard let previous = ownLesson(on: date, slotIndex: slotIndex - 1), previous.slotCount >= 2 else { return nil }
        return previous
    }

    /// Der Slot ist die zweite Hälfte einer Doppelstunde (Kalender und Listen zeigen sie nur einmal, ab dem ersten Slot).
    func isContinuation(on date: Date, slotIndex: Int) -> Bool {
        ownLesson(on: date, slotIndex: slotIndex) == nil && lesson(on: date, slotIndex: slotIndex) != nil
    }

    /// Belegte Slots ab `slotIndex` (2 bei einer Doppelstunde, deren zweiter Slot frei ist).
    func span(on date: Date, slotIndex: Int) -> Int {
        guard let lesson = ownLesson(on: date, slotIndex: slotIndex) else { return 1 }
        return lesson.slotCount >= 2 && isContinuation(on: date, slotIndex: slotIndex + 1)
            && slots.contains(where: { $0.index == slotIndex + 1 }) ? 2 : 1
    }

    /// Ende des letzten Slots der Stunde ab `slot` (Minuten seit Mitternacht).
    func end(on date: Date, from slot: LessonSlot) -> Int {
        guard span(on: date, slotIndex: slot.index) >= 2,
              let next = slots.first(where: { $0.index == slot.index + 1 })
        else { return slot.end }
        return next.end
    }

    /// Stunde, die in genau diesem Slot beginnt.
    private func ownLesson(on date: Date, slotIndex: Int) -> Lesson? {
        if let lesson = single[SingleKey(day: calendar.startOfDay(for: date), slot: slotIndex)] {
            return lesson
        }
        guard holiday(on: date) == nil else { return nil }
        return recurring[RecurringKey(weekday: calendar.mondayBasedWeekday(of: date), slot: slotIndex)]?
            .first { Self.occurs($0, inWeekOf: date, calendar: calendar) }
    }

    /// „Alle 2 Wochen“: nur in Wochen mit geradem Abstand zur Woche von `date` (ohne Datum: zur Woche des Anlegens).
    static func occurs(_ lesson: Lesson, inWeekOf day: Date, calendar: Calendar = .school) -> Bool {
        let interval = lesson.weekInterval
        guard interval >= 2 else { return true }
        let anchor = calendar.startOfWeek(for: lesson.date ?? lesson.createdAt)
        let week = calendar.startOfWeek(for: day)
        let days = calendar.dateComponents([.day], from: anchor, to: week).day ?? 0
        let weeks = Int((Double(days) / 7).rounded())
        return weeks % interval == 0
    }

    /// Nächste (noch nicht beendete) Stunde einer Klasse ab `now`, max. 8 Wochen voraus;
    /// optional nur Stunden, die `matching` erfüllen (z. B. mit Raum).
    func nextLesson(forClass classID: UUID, after now: Date = .now, matching: (Lesson) -> Bool = { _ in true }) -> NextLesson? {
        let today = calendar.startOfDay(for: now)
        for offset in 0..<56 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for slot in slots where !isContinuation(on: day, slotIndex: slot.index) {
                guard let lesson = lesson(on: day, slotIndex: slot.index),
                      lesson.schoolClass?.id == classID,
                      matching(lesson),
                      let end = calendar.date(byAdding: .minute, value: end(on: day, from: slot), to: day),
                      end > now,
                      let start = calendar.date(byAdding: .minute, value: slot.start, to: day)
                else { continue }
                return NextLesson(start: start, slot: slot, lesson: lesson)
            }
        }
        return nil
    }
}

/// Raum für die Kachel „Aktueller Raum“: Raum der laufenden Stunde (egal welche Klasse),
/// sonst der Raum der nächsten Stunde der Klasse, der ein Raum zugeordnet ist.
enum RoomLocator {
    struct Result {
        let room: Room
        let next: NextLesson
        let isCurrent: Bool
    }

    static func locate(schedule: LessonSchedule, classID: UUID, now: Date = .now) -> Result? {
        let calendar = Calendar.school
        let day = calendar.startOfDay(for: now)
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if let slot = schedule.slots.first(where: { $0.start <= minute && minute < $0.end }),
           let lesson = schedule.lesson(on: now, slotIndex: slot.index),
           let room = lesson.room,
           let start = calendar.date(byAdding: .minute, value: slot.start, to: day) {
            return Result(room: room, next: NextLesson(start: start, slot: slot, lesson: lesson), isCurrent: true)
        }
        guard let next = schedule.nextLesson(forClass: classID, after: now, matching: { $0.room != nil }),
              let room = next.lesson.room
        else { return nil }
        return Result(room: room, next: next, isCurrent: next.start <= now)
    }
}

/// Nächste Stunde einer Klasse: Beginn, Slot im Raster und die Stunde selbst.
struct NextLesson {
    let start: Date
    let slot: LessonSlot
    let lesson: Lesson
}

/// Gleitendes Tagesfenster für schmale Ansichten (iPhone): nur angezeigte Wochentage
/// (ohne Wochenende, wenn es in den Schuleinstellungen ausgeblendet ist).
nonisolated extension Calendar {
    /// Erster angezeigter Tag ab `date` (inklusive) in Richtung `direction` (+1 / -1).
    func visibleDay(from date: Date, direction: Int, weekdays: [Int]) -> Date {
        var day = startOfDay(for: date)
        guard !weekdays.isEmpty else { return day }
        while !weekdays.contains(mondayBasedWeekday(of: day)) {
            day = self.date(byAdding: .day, value: direction, to: day) ?? day
        }
        return day
    }

    /// Um `steps` angezeigte Tage verschieben.
    func addingVisibleDays(_ steps: Int, to date: Date, weekdays: [Int]) -> Date {
        let direction = steps < 0 ? -1 : 1
        var day = visibleDay(from: date, direction: direction, weekdays: weekdays)
        for _ in 0..<abs(steps) {
            let next = self.date(byAdding: .day, value: direction, to: day) ?? day
            day = visibleDay(from: next, direction: direction, weekdays: weekdays)
        }
        return day
    }

    /// `count` angezeigte Tage mit `anchor` in der Mitte (bei 3: gestern, heute, morgen).
    func visibleDays(around anchor: Date, count: Int, weekdays: [Int]) -> [Date] {
        let center = visibleDay(from: anchor, direction: 1, weekdays: weekdays)
        let first = addingVisibleDays(-(count / 2), to: center, weekdays: weekdays)
        return (0..<count).map { addingVisibleDays($0, to: first, weekdays: weekdays) }
    }
}
