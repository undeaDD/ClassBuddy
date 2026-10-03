import Foundation
import SwiftData

/// Unterrichtsstunde im Kalender: Klasse + Fach in einem Stunden-Slot.
/// Wöchentlich (`isRecurring`, gilt für `weekday`) oder einmalig (`date`).
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
    /// Tagesbeginn des Termins bei einmaligen Stunden.
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
