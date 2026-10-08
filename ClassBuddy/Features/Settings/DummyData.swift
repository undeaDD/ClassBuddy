#if DEBUG
import SwiftData
import SwiftUI
import UIKit

/// Automatische README-Screenshots (`scripts/screenshots.sh`): Start mit `-screenshots`
/// fügt die Testdaten ein, wählt die erste Testklasse und öffnet den Tab aus `-tab <name>`.
/// (Das Erscheinungsbild setzt das Skript direkt per `-app.appearance light|dark`.)
enum ScreenshotMode {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-screenshots") }

    static func prepare(app: AppModel, context: ModelContext, settings: SchoolSettings) {
        guard isActive else { return }
        // Beispiel-Schule für Wetter und Sekretariat (nur auf frisch installierten Screenshot-Simulatoren).
        if settings.values.school.city.isEmpty {
            settings.values.school = SchoolInfo(
                name: "Gymnasium am See", website: "example.org", street: "Domkloster 4", postalCode: "50667", city: "Köln",
                phone: "0221 1234567", email: "sekretariat@example.org"
            )
        }
        let classes = (try? context.fetch(FetchDescriptor<SchoolClass>())) ?? []
        let firstClass = classes.first { $0.id == DummyData.classIDs.first }
            ?? DummyData.insert(into: context, slotCount: settings.slots.count)
        try? context.save()
        app.selectedClassID = firstClass.id
        if let name = UserDefaults.standard.string(forKey: "tab"), let tab = AppTab(rawValue: name) {
            app.selectedTab = tab
        }
    }
}

/// Testdaten mit festen IDs: So lässt sich erkennen, ob sie schon eingefügt wurden,
/// und sie lassen sich gezielt wieder entfernen (Schüler und Stunden hängen per Cascade an der Klasse).
enum DummyData {
    private struct ClassSpec {
        let shortName: String
        let subjects: [String]
        let color: ClassColor
        let age: Int
        let studentCount: Int
    }

    private static let specs = [
        ClassSpec(shortName: "5a", subjects: ["Deutsch", "Englisch"], color: .blue, age: 10, studentCount: 12),
        ClassSpec(shortName: "7b", subjects: ["Mathematik"], color: .green, age: 12, studentCount: 10),
        ClassSpec(shortName: "9c", subjects: ["Biologie", "Chemie"], color: .orange, age: 14, studentCount: 9),
        ClassSpec(shortName: "Q1", subjects: ["Informatik"], color: .purple, age: 16, studentCount: 8),
    ]

    static let classIDs: [UUID] = (1...specs.count).map { fixedID(prefix: "DDDD0000", $0) }
    private static let entryIDs: [UUID] = (1...5).map { fixedID(prefix: "DDDD1111", $0) }
    /// Eigener Testraum, nur wenn es kein Demo-Klassenzimmer gibt (wird mit den Testdaten entfernt).
    private static let roomID = fixedID(prefix: "DDDD2222", 1)

    private static func fixedID(prefix: String, _ number: Int) -> UUID {
        UUID(uuidString: String(format: "%@-0000-0000-0000-%012d", prefix, number)) ?? UUID()
    }

    private static let femaleNames = ["Emma", "Mia", "Hannah", "Sofia", "Lina", "Lea", "Marie", "Clara", "Ella", "Johanna", "Frieda", "Ida"]
    private static let maleNames = ["Noah", "Ben", "Paul", "Leon", "Finn", "Elias", "Felix", "Jonas", "Luis", "Henry", "Emil", "Theo"]
    private static let lastNames = [
        "Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker",
        "Schulz", "Hoffmann", "Koch", "Richter", "Klein", "Wolf", "Neumann", "Schröder",
    ]

    /// Fügt alles ein und gibt die erste Klasse zurück (zum direkten Auswählen).
    @discardableResult
    static func insert(into context: ModelContext, slotCount: Int) -> SchoolClass {
        let calendar = Calendar.school
        let classes = zip(specs, classIDs).map { spec, id in
            SchoolClass(id: id, shortName: spec.shortName, subjects: spec.subjects, color: spec.color)
        }
        classes.forEach(context.insert)

        let students = zip(specs, classes).enumerated().map { index, pair in
            insertStudents(spec: pair.0, classIndex: index, into: pair.1, context: context)
        }
        let lessons = insertLessons(for: classes, slotCount: slotCount, calendar: calendar, context: context)
        insertEntries(calendar: calendar, classes: classes, context: context)
        insertSeatingPlans(students: students, lessons: lessons, context: context)
        insertDashboardData(classes: classes, students: students, context: context)
        return classes[0]
    }

    // MARK: Übersicht

    /// Kacheln, die die Testklassen zeigen (Reihenfolge); alle übrigen eingebauten stehen unter „Ausgeblendet“.
    private static let visibleCards: [DashboardBuiltInCard] = [
        .nextLesson, .room, .weeklyHours, .holidays, .attendance, .checklists, .quickNote, .timer, .groups,
        .weather, .students, .secretariat,
    ]
    /// Test-Ferien (feste ID, nur ohne importierte Ferien – werden mit den Testdaten entfernt).
    private static let holidayIDPrefix = "dummy-"

    private static let quickNotes = [
        "Hefte einsammeln, Elternbrief zum Ausflug austeilen",
        "Vokabeltest am Freitag ankündigen",
        "Protokoll Versuch 3 bis Mittwoch",
        "Projektgruppen für das Referat festlegen",
    ]

    /// Daten für die Kacheln: Checklisten, Fehlzeiten heute, Schnellnotiz, letzte Gruppen, Ferien; Kacheln eingeblendet.
    private static func insertDashboardData(classes: [SchoolClass], students: [[Student]], context: ModelContext) {
        let calendar = Calendar.school
        let today = calendar.startOfDay(for: .now)
        for (index, (schoolClass, classStudents)) in zip(classes, students).enumerated() {
            let cards = visibleCards.filter(\.isSupported).map(\.rawValue)
            let all = DashboardBuiltInCard.allCases.map(\.rawValue)
            schoolClass.dashboardOrder = cards + all.filter { !cards.contains($0) }
            schoolClass.dashboardHidden = all.filter { !cards.contains($0) }
            schoolClass.dashboardKnownCards = all

            // Zwei Checklisten: Fach (zu zwei Dritteln abgehakt) und alle Fächer (mit Enddatum, ein Drittel).
            let books = Checklist(
                title: loc("Name in die Bücher eingetragen"), subtitle: loc("Alle Schulbücher, bis Ende der Woche"),
                subject: schoolClass.subjects.first ?? "", createdAt: calendar.date(byAdding: .day, value: -3, to: .now) ?? .now,
                schoolClass: schoolClass
            )
            let letter = Checklist(
                title: loc("Elternbrief zurückgegeben"), subtitle: loc("Unterschrieben, für den Wandertag"),
                createdAt: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now, schoolClass: schoolClass
            )
            letter.dueDate = calendar.date(byAdding: .day, value: 4, to: today)
            [books, letter].forEach(context.insert)
            for (number, student) in classStudents.enumerated() {
                if number % 3 != 2 { books.check(student, at: calendar.date(byAdding: .day, value: -2, to: .now) ?? .now, in: context) }
                if number % 3 == 0 { letter.check(student, in: context) }
            }
            // Zuletzt bearbeitet = Kachel „Checklisten“.
            books.updatedAt = .now

            // Heute: eine Schülerin fehlt, einer kam zu spät.
            if classStudents.count > 3 {
                context.insert(Absence(subject: schoolClass.subjects.first ?? "", day: today, slotIndex: 0, kind: .absent,
                                       student: classStudents[1]))
                context.insert(Absence(subject: schoolClass.subjects.first ?? "", day: today, slotIndex: 0, kind: .late,
                                       arrivedAt: calendar.date(byAdding: .minute, value: 8 * 60 + 9, to: today),
                                       student: classStudents[2]))
            }

            schoolClass.quickNote = quickNotes[index % quickNotes.count]
            schoolClass.quickNoteEditedAt = calendar.date(byAdding: .minute, value: 7 * 60 + 52, to: today)
            schoolClass.lastGroups = StudentGroups.deal(
                classStudents.map(\.id), mode: .size, value: 3, date: calendar.date(byAdding: .hour, value: -2, to: .now) ?? .now
            )
        }

        // Herbstferien in knapp zwei Wochen, falls keine Ferien importiert sind (Kachel „Ferien“).
        let hasSchoolHolidays = ((try? context.fetch(FetchDescriptor<Holiday>())) ?? []).contains(where: \.isSchoolHoliday)
        if !hasSchoolHolidays,
           let start = calendar.date(byAdding: .day, value: 12, to: today),
           let end = calendar.date(byAdding: .day, value: 25, to: today) {
            context.insert(Holiday(id: holidayIDPrefix + "herbstferien", name: loc("Herbstferien"), startDate: start, endDate: end,
                                   isSchoolHoliday: true))
        }
    }

    /// Alle Testklassen sitzen im Demo-Klassenzimmer (sonst in einem eigenen Testraum mit demselben Grundriss);
    /// die meisten Stunden finden dort statt, damit Kalender und Sitzplan gefüllt sind.
    private static func insertSeatingPlans(students: [[Student]], lessons: [Lesson], context: ModelContext) {
        let demoName = loc("Demo-Klassenzimmer")
        let needed = students.map(\.count).max() ?? 0
        let rooms = (try? context.fetch(FetchDescriptor<Room>())) ?? []
        let room = rooms.first { $0.name == demoName && SeatingPlan.tables(in: $0).count >= needed } ?? {
            let room = Room(id: roomID, name: loc("Testraum 101"), subtitle: loc("Testdaten"), category: .classroom)
            context.insert(room)
            room.replaceElements(with: RoomDemo.shapes, in: context)
            return room
        }()
        let tables = SeatingPlan.tables(in: room)
        for classStudents in students {
            for (student, table) in zip(classStudents, tables) {
                SeatingPlan.assign(student, to: table, in: context)
            }
        }
        // Jede fünfte Stunde ohne Raum (zum Vergleich).
        for (index, lesson) in lessons.enumerated() where index % 5 != 4 {
            lesson.room = room
        }
    }

    @discardableResult
    private static func insertStudents(
        spec: ClassSpec, classIndex: Int, into schoolClass: SchoolClass, context: ModelContext
    ) -> [Student] {
        let calendar = Calendar.school
        var students: [Student] = []
        for number in 0..<spec.studentCount {
            let isFemale = number.isMultiple(of: 2)
            let names = isFemale ? femaleNames : maleNames
            let firstName = names[(number / 2 + classIndex * 3) % names.count]
            let lastName = lastNames[(number * 5 + classIndex * 7) % lastNames.count]
            // Ein Geburtstag pro Klasse liegt in den nächsten Tagen (Kachel „Nächster Geburtstag“).
            let daysFromNow = number == 0 ? classIndex + 2 : (number * 37 + classIndex * 11) % 365
            let birthdayThisYear = calendar.date(byAdding: .day, value: daysFromNow, to: calendar.startOfDay(for: .now)) ?? .now
            let birthday = calendar.date(byAdding: .year, value: -(spec.age + number % 2), to: birthdayThisYear)
            let gender: Gender? = number == spec.studentCount - 1 ? nil : (number % 7 == 5 ? .diverse : (isFemale ? .female : .male))
            let student = Student(
                firstName: firstName,
                lastName: lastName,
                birthday: birthday,
                gender: gender,
                notes: number % 4 == 1 ? "Sitzt gern vorne." : "",
                phone: number % 3 == 0 ? String(format: "+49 151 %04d %04d", 1000 + classIndex * 97 + number, 2000 + number * 31) : "",
                email: number % 2 == 0 ? Self.email(firstName: firstName, lastName: lastName) : "",
                otherContact: number % 5 == 2 ? "Mutter: 0234 \(5550 + number), nachmittags erreichbar" : "",
                photo: number % 4 == 0 ? Self.dummyPhoto(seed: number + classIndex * 13) : nil,
                // Vor einem Monat angelegt: so zählen vergangene Stunden für „seit X Stunden ohne Beobachtung“.
                createdAt: calendar.date(byAdding: .day, value: -30, to: .now) ?? .now,
                schoolClass: schoolClass
            )
            context.insert(student)
            students.append(student)
            // Jeder dritte Schüler wurde gestern beobachtet, die übrigen erscheinen im Sitzplan gestrichelt.
            if number.isMultiple(of: 3), let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) {
                for subject in spec.subjects {
                    context.insert(StudentObservation(
                        subject: subject, date: yesterday, kind: .rating, scale: .sevenStep,
                        value: number % 4 == 0 ? 2 : 1, student: student
                    ))
                }
            }
        }
        return students
    }

    /// vorname.nachname@example.org (Umlaute ersetzt, Domain für Beispiele reserviert).
    private static func email(firstName: String, lastName: String) -> String {
        let local = "\(firstName).\(lastName)".lowercased()
            .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
        return "\(local)@example.org"
    }

    /// Platzhalter-Foto: Farbverlauf mit Tier-Emoji (kein echtes Foto).
    private static func dummyPhoto(seed: Int) -> Data? {
        let emojis = ["🦊", "🐼", "🐯", "🐸", "🐨", "🦁", "🐙", "🐧"]
        let colors: [UIColor] = [.systemTeal, .systemOrange, .systemPurple, .systemGreen, .systemPink, .systemIndigo]
        let size = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let top = colors[seed % colors.count], bottom = colors[(seed + 2) % colors.count]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [top.cgColor, bottom.cgColor] as CFArray,
                locations: [0, 1]
            )
            if let gradient {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            let emoji = emojis[seed % emojis.count] as NSString
            let font = UIFont.systemFont(ofSize: 150)
            let textSize = emoji.size(withAttributes: [.font: font])
            emoji.draw(
                at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: [.font: font]
            )
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    /// Wöchentlicher Stundenplan Mo–Fr plus drei einmalige Stunden in freien Slots dieser Woche.
    @discardableResult
    private static func insertLessons(for classes: [SchoolClass], slotCount: Int, calendar: Calendar, context: ModelContext) -> [Lesson] {
        let slots = min(slotCount, 6)
        guard slots > 0 else { return [] }
        var inserted: [Lesson] = []
        var free: [(weekday: Int, slot: Int)] = []

        for weekday in 0..<5 {
            for slot in 0..<slots {
                // Muster mit Freistunden: jede 5. Kombination bleibt leer.
                let pick = (weekday * 3 + slot) % (classes.count + 1)
                guard pick < classes.count else {
                    free.append((weekday, slot))
                    continue
                }
                let schoolClass = classes[pick]
                let subjects = schoolClass.subjects
                let lesson = Lesson(
                    weekday: weekday,
                    slotIndex: slot,
                    subject: subjects[(weekday + slot) % subjects.count],
                    isRecurring: true,
                    date: nil,
                    schoolClass: schoolClass
                )
                context.insert(lesson)
                inserted.append(lesson)
            }
        }

        let weekStart = calendar.startOfWeek(for: .now)
        for (index, spot) in free.prefix(3).enumerated() {
            let schoolClass = classes[index % classes.count]
            let day = calendar.date(byAdding: .day, value: spot.weekday, to: weekStart) ?? weekStart
            let lesson = Lesson(
                weekday: spot.weekday,
                slotIndex: spot.slot,
                subject: schoolClass.subjects[0],
                isRecurring: false,
                date: calendar.startOfDay(for: day),
                schoolClass: schoolClass
            )
            context.insert(lesson)
            inserted.append(lesson)
        }
        return inserted
    }

    private struct EntrySpec {
        let title: String
        let weekday: Int
        let hour: Int
        let minute: Int
        let minutes: Int
        let notes: String
        /// Index in `specs` (nil = Termin ohne Klasse).
        var classIndex: Int?
    }

    private static func insertEntries(calendar: Calendar, classes: [SchoolClass], context: ModelContext) {
        let weekStart = calendar.startOfWeek(for: .now)
        let entries = [
            EntrySpec(title: "Fachkonferenz Mathematik", weekday: 0, hour: 15, minute: 0, minutes: 90, notes: "Raum 204"),
            EntrySpec(title: "Lehrerkonferenz", weekday: 2, hour: 14, minute: 30, minutes: 90, notes: ""),
            EntrySpec(
                title: "Elterngespräch Fam. Müller", weekday: 3, hour: 13, minute: 15, minutes: 30,
                notes: "Leistungsstand", classIndex: 1
            ),
            // Mit Klasse außerhalb der Schulzeit bzw. mitten im Schultag.
            EntrySpec(title: "Elternabend", weekday: 1, hour: 18, minute: 0, minutes: 90, notes: "Aula", classIndex: 0),
            EntrySpec(title: "Museumsbesuch", weekday: 4, hour: 9, minute: 0, minutes: 180, notes: "", classIndex: 2),
        ]
        for (entry, id) in zip(entries, entryIDs) {
            let day = calendar.date(byAdding: .day, value: entry.weekday, to: weekStart) ?? weekStart
            let start = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day) ?? day
            let end = start.addingTimeInterval(TimeInterval(entry.minutes * 60))
            let schoolClass = entry.classIndex.map { classes[$0] }
            context.insert(CalendarEntry(id: id, title: entry.title, start: start, end: end, notes: entry.notes, schoolClass: schoolClass))
        }
    }

    static func remove(from context: ModelContext, classes: [SchoolClass]) {
        for schoolClass in classes where classIDs.contains(schoolClass.id) {
            context.delete(schoolClass)
        }
        // Einzeln statt per Batch-Delete: Das scheitert still an Terminen, deren Klasse gerade gelöscht wird.
        let ids = entryIDs
        for entry in (try? context.fetch(FetchDescriptor<CalendarEntry>(predicate: #Predicate { ids.contains($0.id) }))) ?? [] {
            context.delete(entry)
        }
        let roomID = roomID
        if let room = try? context.fetch(FetchDescriptor<Room>(predicate: #Predicate { $0.id == roomID })).first {
            context.delete(room)
        }
        let prefix = holidayIDPrefix
        try? context.delete(model: Holiday.self, where: #Predicate { $0.id.starts(with: prefix) })
    }
}
#endif
