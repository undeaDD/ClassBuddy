import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Neu-Formulare: Zuletzt angelegt & alternatives App-Icon")
struct LastCreatedTests {
    private struct Fixture {
        let context: ModelContext
        let defaults: UserDefaults
        let schoolClass: SchoolClass
    }

    init() {
        AppLanguage.current = .german
    }

    /// Eigene UserDefaults-Suite je Test, damit nichts in die App-Einstellungen gelangt.
    private static func fixture() throws -> Fixture {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Checklist.self, ChecklistCheck.self, CalendarEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let suite = "LastCreatedTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        context.insert(schoolClass)
        try context.save()
        return Fixture(context: context, defaults: defaults, schoolClass: schoolClass)
    }

    private static func addStudent(_ name: String, to fixture: Fixture) throws -> Student {
        let student = Student(firstName: name, lastName: "Muster", schoolClass: fixture.schoolClass)
        fixture.context.insert(student)
        try fixture.context.save()
        LastCreated.record(student.id, as: .student, defaults: fixture.defaults)
        return student
    }

    @Test("Ohne angelegten Eintrag gibt es nichts anzuzeigen")
    func emptyByDefault() throws {
        let fixture = try Self.fixture()
        #expect(LastCreated.student(in: fixture.context, defaults: fixture.defaults) == nil)
        #expect(LastCreated.checklist(in: fixture.context, defaults: fixture.defaults) == nil)
        #expect(LastCreated.calendarEntry(in: fixture.context, defaults: fixture.defaults) == nil)
        for kind in LastCreated.Kind.allCases {
            #expect(LastCreated.id(of: kind, defaults: fixture.defaults) == nil)
        }
    }

    @Test("Jede Art hat einen eigenen Schlüssel")
    func distinctKeys() {
        let keys = Set(LastCreated.Kind.allCases.map(\.defaultsKey))
        #expect(keys.count == LastCreated.Kind.allCases.count)
    }

    @Test("Der zuletzt angelegte Schüler bleibt über das Schließen hinweg erhalten, der neueste gewinnt")
    func studentPersists() throws {
        let fixture = try Self.fixture()
        _ = try Self.addStudent("Anna", to: fixture)
        let ben = try Self.addStudent("Ben", to: fixture)

        // Neues Formular: liest nur aus Datenbestand und UserDefaults.
        let shown = LastCreated.student(in: fixture.context, defaults: fixture.defaults)
        #expect(shown?.id == ben.id)
        #expect(shown?.fullName == "Ben Muster")
    }

    @Test("Gelöschter Schüler wird nicht mehr angezeigt und die Kennung verworfen")
    func deletedStudentIsHidden() throws {
        let fixture = try Self.fixture()
        let anna = try Self.addStudent("Anna", to: fixture)
        fixture.context.delete(anna)
        try fixture.context.save()

        #expect(LastCreated.student(in: fixture.context, defaults: fixture.defaults) == nil)
        #expect(LastCreated.id(of: .student, defaults: fixture.defaults) == nil)

        // Danach angelegte Schüler erscheinen wieder.
        let ben = try Self.addStudent("Ben", to: fixture)
        #expect(LastCreated.student(in: fixture.context, defaults: fixture.defaults)?.id == ben.id)
    }

    @Test("Löschen eines älteren Schülers lässt den zuletzt angelegten stehen")
    func deletingOtherStudentKeepsLast() throws {
        let fixture = try Self.fixture()
        let anna = try Self.addStudent("Anna", to: fixture)
        let ben = try Self.addStudent("Ben", to: fixture)
        fixture.context.delete(anna)
        try fixture.context.save()
        #expect(LastCreated.student(in: fixture.context, defaults: fixture.defaults)?.id == ben.id)
    }

    @Test("Löschen der Klasse entfernt auch den zuletzt angelegten Schüler")
    func deletedClassHidesStudent() throws {
        let fixture = try Self.fixture()
        _ = try Self.addStudent("Anna", to: fixture)
        fixture.context.delete(fixture.schoolClass)
        try fixture.context.save()
        #expect(LastCreated.student(in: fixture.context, defaults: fixture.defaults) == nil)
    }

    @Test("Umbenennen zeigt den aktuellen Namen")
    func renamedStudentShowsCurrentName() throws {
        let fixture = try Self.fixture()
        let anna = try Self.addStudent("Anna", to: fixture)
        anna.firstName = "Annika"
        try fixture.context.save()
        #expect(LastCreated.student(in: fixture.context, defaults: fixture.defaults)?.fullName == "Annika Muster")
    }

    @Test("Checkliste: anzeigen, nach dem Löschen ausblenden")
    func checklist() throws {
        let fixture = try Self.fixture()
        let checklist = Checklist(title: "Bücher", subject: "Mathematik", schoolClass: fixture.schoolClass)
        fixture.context.insert(checklist)
        try fixture.context.save()
        LastCreated.record(checklist.id, as: .checklist, defaults: fixture.defaults)
        #expect(LastCreated.checklist(in: fixture.context, defaults: fixture.defaults)?.title == "Bücher")

        fixture.context.delete(checklist)
        try fixture.context.save()
        #expect(LastCreated.checklist(in: fixture.context, defaults: fixture.defaults) == nil)
        #expect(LastCreated.id(of: .checklist, defaults: fixture.defaults) == nil)
    }

    @Test("Termin: Titel, ohne Titel Datum und Uhrzeit; nach dem Löschen ausgeblendet")
    func calendarEntry() throws {
        let fixture = try Self.fixture()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = CalendarEntry(title: "", start: start, end: start.addingTimeInterval(3600))
        fixture.context.insert(entry)
        try fixture.context.save()
        LastCreated.record(entry.id, as: .calendarEntry, defaults: fixture.defaults)

        let shown = try #require(LastCreated.calendarEntry(in: fixture.context, defaults: fixture.defaults))
        #expect(LastCreated.displayTitle(of: shown) == start.appDateTime)
        shown.title = "Elternabend"
        #expect(LastCreated.displayTitle(of: shown) == "Elternabend")

        fixture.context.delete(entry)
        try fixture.context.save()
        #expect(LastCreated.calendarEntry(in: fixture.context, defaults: fixture.defaults) == nil)
    }

    @Test("Arten sind getrennt: ein Schüler zählt nicht als Checkliste")
    func kindsAreSeparate() throws {
        let fixture = try Self.fixture()
        let anna = try Self.addStudent("Anna", to: fixture)
        #expect(LastCreated.checklist(in: fixture.context, defaults: fixture.defaults) == nil)
        #expect(LastCreated.calendarEntry(in: fixture.context, defaults: fixture.defaults) == nil)
        #expect(LastCreated.id(of: .student, defaults: fixture.defaults) == anna.id)
    }

    @Test("Ungültige gespeicherte Kennung wird ignoriert")
    func invalidStoredID() throws {
        let fixture = try Self.fixture()
        fixture.defaults.set("keine-uuid", forKey: LastCreated.Kind.student.defaultsKey)
        #expect(LastCreated.id(of: .student, defaults: fixture.defaults) == nil)
        #expect(LastCreated.student(in: fixture.context, defaults: fixture.defaults) == nil)
    }

    @Test("Das klassische App-Icon ist als alternatives Icon im Bundle eingetragen")
    func alternateIconRegistered() throws {
        let icons = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let alternates = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
        #expect(alternates[AppIconRow.classicIconName] != nil)
    }
}
