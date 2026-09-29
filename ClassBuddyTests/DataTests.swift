import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

/// Tests mit einer In-Memory-Datenbank (berührt keine echten App-Daten).
@Suite("Daten")
struct DataTests {
    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self, DashboardLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        Calendar.school.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: Stundenplan

    @Test("Nächste Stunde: nächster passender Wochentag")
    func nextLesson() throws {
        let context = try Self.makeContext()
        let schoolClass = SchoolClass(shortName: "7b")
        context.insert(schoolClass)
        // Montag, 1. Stunde, wöchentlich
        context.insert(Lesson(weekday: 0, slotIndex: 0, subject: "Mathe", isRecurring: true, date: nil, schoolClass: schoolClass))

        let schedule = LessonSchedule(
            lessons: try context.fetch(FetchDescriptor<Lesson>()),
            holidays: [],
            slots: SchoolSettings.Values().slots
        )
        // Sonntag, 27.09.2026, 12 Uhr → Montag, 28.09.2026, 08:00
        let next = try #require(schedule.nextLesson(forClass: schoolClass.id, after: Self.day(2026, 9, 27, hour: 12)))

        #expect(next.start == Self.day(2026, 9, 28, hour: 8))
        #expect(next.slot.number == 1)
        #expect(next.lesson.subject == "Mathe")
    }

    @Test("Nächste Stunde: Ferien werden übersprungen")
    func nextLessonSkipsHolidays() throws {
        let context = try Self.makeContext()
        let schoolClass = SchoolClass(shortName: "7b")
        context.insert(schoolClass)
        context.insert(Lesson(weekday: 0, slotIndex: 0, subject: "", isRecurring: true, date: nil, schoolClass: schoolClass))
        let holiday = Holiday(
            id: "h", name: "Test", startDate: Self.day(2026, 9, 28), endDate: Self.day(2026, 9, 28), isSchoolHoliday: true
        )

        let schedule = LessonSchedule(
            lessons: try context.fetch(FetchDescriptor<Lesson>()),
            holidays: [holiday],
            slots: SchoolSettings.Values().slots
        )
        let next = try #require(schedule.nextLesson(forClass: schoolClass.id, after: Self.day(2026, 9, 27, hour: 12)))

        #expect(next.start == Self.day(2026, 10, 5, hour: 8))
    }

    @Test("Einzelstunde hat Vorrang vor der wöchentlichen Stunde")
    func singleLessonWins() throws {
        let context = try Self.makeContext()
        let schoolClass = SchoolClass(shortName: "7b")
        context.insert(schoolClass)
        context.insert(Lesson(weekday: 0, slotIndex: 0, subject: "Mathe", isRecurring: true, date: nil, schoolClass: schoolClass))
        context.insert(Lesson(
            weekday: 0, slotIndex: 0, subject: "Vertretung", isRecurring: false, date: Self.day(2026, 9, 28), schoolClass: schoolClass
        ))

        let schedule = LessonSchedule(lessons: try context.fetch(FetchDescriptor<Lesson>()), holidays: [], slots: [])

        #expect(schedule.lesson(on: Self.day(2026, 9, 28), slotIndex: 0)?.subject == "Vertretung")
        #expect(schedule.lesson(on: Self.day(2026, 10, 5), slotIndex: 0)?.subject == "Mathe")
    }

    // MARK: Export / Import

    @Test("Excel-Export und -Import ergeben dieselben Daten")
    func backupRoundTrip() throws {
        let source = try Self.makeContext()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik", "Physik"], schoolYear: "2026/27", color: .green)
        source.insert(schoolClass)
        source.insert(Student(
            firstName: "Emma", lastName: "Schneider", birthday: Self.day(2014, 3, 1),
            gender: .female, notes: "Notiz", schoolClass: schoolClass
        ))
        source.insert(Lesson(weekday: 2, slotIndex: 3, subject: "Physik", isRecurring: true, date: nil, schoolClass: schoolClass))
        source.insert(CalendarEntry(title: "Konferenz", start: Self.day(2026, 10, 1, hour: 14), end: Self.day(2026, 10, 1, hour: 16)))
        source.insert(DashboardLink(title: "Vertretungsplan", kind: .website, location: "https://example.org/plan", schoolClass: schoolClass))
        try source.save()

        var settings = SchoolSettings.Values()
        settings.school.name = "Testschule"
        settings.teacher.firstName = "Dominic"
        settings.lessonDuration = 60

        let data = try Backup.export(context: source, settings: settings, appearance: .dark)

        let target = try Self.makeContext()
        let result = try Backup.import(data, context: target, currentSettings: SchoolSettings.Values())

        #expect(result.summary.classes == 1)
        #expect(result.summary.students == 1)
        #expect(result.summary.lessons == 1)
        #expect(result.summary.entries == 1)
        #expect(result.summary.links == 1)

        let importedClass = try #require(try target.fetch(FetchDescriptor<SchoolClass>()).first)
        #expect(importedClass.id == schoolClass.id)
        #expect(importedClass.subjects == ["Mathematik", "Physik"])
        #expect(importedClass.color == .green)

        let student = try #require(importedClass.students.first)
        #expect(student.fullName == "Emma Schneider")
        #expect(student.gender == .female)
        #expect(student.birthday == Self.day(2014, 3, 1))

        let lesson = try #require(importedClass.lessons.first)
        #expect(lesson.weekday == 2 && lesson.slotIndex == 3 && lesson.isRecurring)

        let entry = try #require(try target.fetch(FetchDescriptor<CalendarEntry>()).first)
        #expect(entry.start == Self.day(2026, 10, 1, hour: 14))

        #expect(importedClass.dashboardLinks.first?.location == "https://example.org/plan")
        #expect(result.settings.values.school.name == "Testschule")
        #expect(result.settings.values.teacher.firstName == "Dominic")
        #expect(result.settings.values.lessonDuration == 60)
        #expect(result.settings.appearance == .dark)
    }

    @Test("In Excel bearbeitete Datei (komprimiert, Datum/Wahrheitswert als Zahl) wird importiert")
    func importsExcelEditedFile() throws {
        let url = try #require(Bundle(for: FixtureToken.self).url(forResource: "excel-edited", withExtension: "xlsx"))
        let context = try Self.makeContext()

        let result = try Backup.import(try Data(contentsOf: url), context: context, currentSettings: SchoolSettings.Values())

        #expect(result.summary.classes == 1)
        #expect(result.summary.students == 1)
        #expect(result.summary.lessons == 1)

        let schoolClass = try #require(try context.fetch(FetchDescriptor<SchoolClass>()).first)
        #expect(schoolClass.shortName == "5a")
        #expect(schoolClass.subjects == ["Deutsch", "Kunst"])
        #expect(schoolClass.color == .teal)

        let student = try #require(schoolClass.students.first)
        #expect(student.fullName == "Jörg Müller")
        #expect(student.gender == .male)
        #expect(student.birthday == Self.day(2015, 5, 17))

        let lesson = try #require(schoolClass.lessons.first)
        #expect(lesson.weekday == 1)
        #expect(lesson.slotIndex == 1)
        #expect(lesson.isRecurring)
        #expect(lesson.subject == "Kunst")
    }

    @Test("Import lehnt fremde Dateien ab")
    func importRejectsForeignWorkbook() throws {
        let data = XLSX.write([XLSXSheet(name: "Tabelle1", rows: [["A"], ["1"]])])

        #expect(throws: Backup.ImportError.self) {
            try Backup.import(data, context: try Self.makeContext(), currentSettings: SchoolSettings.Values())
        }
    }

    // MARK: Hilfen

    @Test("Web-Adressen und App-Links", arguments: [
        ("schule.de", "https://schule.de"),
        ("https://example.org/a", "https://example.org/a"),
        ("  schule.de/plan  ", "https://schule.de/plan"),
        ("schule.de:8080/plan", "https://schule.de:8080/plan"),
        ("notability://open", "notability://open"),
        ("mailto:sekretariat@schule.de", "mailto:sekretariat@schule.de"),
    ])
    func webURL(input: String, expected: String) {
        #expect(URL.web(input)?.absoluteString == expected)
    }

    @Test("Ungültige oder unsichere Adressen", arguments: [
        "", "mit leerzeichen.de", "   ", "http://schule.de", "HTTP://schule.de", "ftp://server.de",
        "file:///etc/hosts", "javascript:alert(1)", "data:text/html,x", "notability:",
    ])
    func invalidWebURL(input: String) {
        #expect(URL.web(input) == nil)
    }
}

/// Anker für das Test-Bundle (Fixtures).
private final class FixtureToken {}
