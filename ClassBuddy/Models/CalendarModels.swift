import Foundation
import SwiftData

/// Unterrichtsstunde im Kalender: Klasse + Fach in einem Stunden-Slot.
/// Wiederkehrend (`isRecurring`, gilt für `weekday` jede bzw. jede zweite Woche) oder einmalig (`date`).
/// Als Doppelstunde belegt sie auch den folgenden Slot.
/// Gebunden an die Stundennummer, nicht an Uhrzeiten – ändert sich das Raster,
/// wandert die Stunde mit.
@Model
final class Lesson {
    @Attribute(.unique) var id: UUID
    /// 0 = Montag … 6 = Sonntag
    var weekday: Int
    var slotIndex: Int
    var subject: String
    var isRecurring: Bool
    /// Wiederkehrende Stunden: alle wie viele Wochen (1 = jede, 2 = jede zweite).
    var weekInterval: Int = 1
    /// Belegte Slots ab `slotIndex` (2 = Doppelstunde).
    var slotCount: Int = 1
    /// Tagesbeginn des Termins bei einmaligen Stunden; bei „alle 2 Wochen“ ein Tag in einer der Wochen.
    var date: Date?
    var createdAt: Date
    var schoolClass: SchoolClass?
    /// Optionaler Raum (öffnet beim Antippen den Sitzplan der Klasse in diesem Raum).
    var room: Room?

    init(
        id: UUID = UUID(),
        weekday: Int,
        slotIndex: Int,
        subject: String,
        isRecurring: Bool,
        date: Date?,
        schoolClass: SchoolClass?
    ) {
        self.id = id
        self.weekday = weekday
        self.slotIndex = slotIndex
        self.subject = subject
        self.isRecurring = isRecurring
        self.date = date
        self.createdAt = .now
        self.schoolClass = schoolClass
    }

    var repetition: LessonRepetition {
        get {
            guard isRecurring else { return .once }
            return weekInterval >= 2 ? .everyOtherWeek : .weekly
        }
        set {
            isRecurring = newValue != .once
            weekInterval = newValue == .everyOtherWeek ? 2 : 1
        }
    }

    var isDouble: Bool {
        get { slotCount >= 2 }
        set { slotCount = newValue ? 2 : 1 }
    }
}

/// Wiederholung einer Stunde im Stunden-Editor.
nonisolated enum LessonRepetition: String, CaseIterable, Identifiable {
    case once, weekly, everyOtherWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: loc("Einmalig")
        case .weekly: loc("Jede Woche")
        case .everyOtherWeek: loc("Alle 2 Wochen")
        }
    }
}

/// Freier Termin (Konferenz, Elterngespräch, Ausflug …), optional einer Klasse zugeordnet
/// (dann in deren Farbe wie eine Unterrichtsstunde).
@Model
final class CalendarEntry {
    @Attribute(.unique) var id: UUID
    var title: String
    var start: Date
    var end: Date
    var notes: String
    var schoolClass: SchoolClass?
    /// Optionaler Raum (z. B. Vertretung, AG): Antippen öffnet den Sitzplan, ohne Klasse leer zum Drucken.
    var room: Room?

    init(id: UUID = UUID(), title: String, start: Date, end: Date, notes: String = "", schoolClass: SchoolClass? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
        self.schoolClass = schoolClass
    }
}

/// Importierte Schulferien bzw. gesetzliche Feiertage (ganztägig, Ende inklusive).
@Model
final class Holiday {
    @Attribute(.unique) var id: String
    var name: String
    var startDate: Date
    var endDate: Date
    var isSchoolHoliday: Bool

    init(id: String, name: String, startDate: Date, endDate: Date, isSchoolHoliday: Bool) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.isSchoolHoliday = isSchoolHoliday
    }

    func contains(_ day: Date) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let day = calendar.startOfDay(for: day)
        return start <= day && day <= end
    }
}

nonisolated extension Calendar {
    /// Deutscher Kalender: Woche beginnt Montag, ISO-Kalenderwochen.
    static let school: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "de_DE")
        calendar.timeZone = .current
        return calendar
    }()

    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }

    /// 0 = Montag … 6 = Sonntag
    func mondayBasedWeekday(of date: Date) -> Int {
        (component(.weekday, from: date) + 5) % 7
    }
}
