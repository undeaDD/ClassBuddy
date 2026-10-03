import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Sitzplan: Zuordnen, Freigeben, Zufällig verteilen")
struct SeatingPlanTests {
    init() {
        AppLanguage.current = .german
    }

    private static func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> [GridPoint] {
        [GridPoint(x, y), GridPoint(x + width, y), GridPoint(x + width, y + height), GridPoint(x, y + height), GridPoint(x, y)]
    }

    /// Raum mit drei Tischen und zwei Klassen (je zwei Schüler).
    private struct Fixture {
        let context: ModelContext
        let room: Room
        let tables: [RoomElement]
        let first: SchoolClass
        let second: SchoolClass
    }

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, Room.self, RoomElement.self, SeatAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func fixture() throws -> Fixture {
        let context = try makeContext()
        let room = Room(name: "R 1")
        context.insert(room)
        let shapes = [RoomShape(kind: .outline, points: rect(0, 0, 10, 6))]
            + (0..<3).map { RoomShape(kind: .table, points: rect(1 + 3 * $0, 1, 2, 1)) }
        room.replaceElements(with: shapes, in: context)
        let first = SchoolClass(shortName: "7b"), second = SchoolClass(shortName: "8a")
        context.insert(first)
        context.insert(second)
        for (schoolClass, names) in [(first, ["Emma", "Ben"]), (second, ["Lea", "Tom"])] {
            for name in names {
                let student = Student(firstName: name, lastName: "S")
                context.insert(student)
                student.schoolClass = schoolClass
            }
        }
        try context.save()
        return Fixture(context: context, room: room, tables: SeatingPlan.tables(in: room), first: first, second: second)
    }

    @Test("Umsetzen gibt den alten Platz frei, besetzter Tisch wird ersetzt, andere Klassen bleiben")
    func seatingAssign() throws {
        let fixture = try Self.fixture()
        let (context, room, tables, first, second) = (fixture.context, fixture.room, fixture.tables, fixture.first, fixture.second)
        let emma = try #require(first.students.first { $0.firstName == "Emma" })
        let ben = try #require(first.students.first { $0.firstName == "Ben" })
        let lea = try #require(second.students.first)

        SeatingPlan.assign(emma, to: tables[0], in: context)
        SeatingPlan.assign(lea, to: tables[0], in: context)
        SeatingPlan.assign(emma, to: tables[1], in: context)
        try context.save()
        #expect(SeatingPlan.occupants(in: room, schoolClass: first).mapValues(\.id) == [tables[1].id: emma.id])
        #expect(SeatingPlan.occupants(in: room, schoolClass: second).mapValues(\.id) == [tables[0].id: lea.id])

        SeatingPlan.assign(ben, to: tables[1], in: context)
        try context.save()
        #expect(SeatingPlan.occupants(in: room, schoolClass: first).mapValues(\.id) == [tables[1].id: ben.id])
        #expect(emma.seatAssignments.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<SeatAssignment>()) == 2)
    }

    @Test("Freigeben und alle freigeben betreffen nur die eigene Klasse")
    func seatingClear() throws {
        let fixture = try Self.fixture()
        let (context, room, tables, first, second) = (fixture.context, fixture.room, fixture.tables, fixture.first, fixture.second)
        for (index, student) in first.students.enumerated() {
            SeatingPlan.assign(student, to: tables[index], in: context)
        }
        SeatingPlan.assign(try #require(second.students.first), to: tables[0], in: context)
        SeatingPlan.clear(tables[0], schoolClass: first, in: context)
        try context.save()
        #expect(SeatingPlan.occupants(in: room, schoolClass: first).count == 1)

        SeatingPlan.clearAll(in: room, schoolClass: first, in: context)
        try context.save()
        #expect(SeatingPlan.occupants(in: room, schoolClass: first).isEmpty)
        #expect(SeatingPlan.occupants(in: room, schoolClass: second).count == 1)
    }

    @Test("zufällig verteilen nutzt jeden Tisch höchstens einmal")
    func seatingShuffle() throws {
        let fixture = try Self.fixture()
        let (context, room, first) = (fixture.context, fixture.room, fixture.first)
        #expect(SeatingPlan.shuffle(in: room, schoolClass: first, in: context) == 0)
        try context.save()
        let occupants = SeatingPlan.occupants(in: room, schoolClass: first)
        #expect(Set(occupants.values.map(\.id)) == Set(first.students.map(\.id)))

        let students = (0..<5).map { _ in UUID() }, tables = (0..<3).map { _ in UUID() }
        var generator = SystemRandomNumberGenerator()
        let plan = SeatingPlan.randomPlan(students: students, tables: tables, using: &generator)
        #expect(plan.count == 3)
        #expect(Set(plan.values) == Set(tables))
        #expect(SeatingPlan.randomPlan(students: Array(students.prefix(2)), tables: tables, using: &generator).count == 2)
    }

    @Test("Ziehen auf einen besetzten Tisch tauscht die Plätze; aus der Liste ersetzt es den Schüler")
    func seatingMove() throws {
        let fixture = try Self.fixture()
        let (context, room, tables, first) = (fixture.context, fixture.room, fixture.tables, fixture.first)
        let emma = try #require(first.students.first { $0.firstName == "Emma" })
        let ben = try #require(first.students.first { $0.firstName == "Ben" })
        SeatingPlan.assign(emma, to: tables[0], in: context)
        SeatingPlan.assign(ben, to: tables[1], in: context)

        SeatingPlan.move(emma, to: tables[1], in: context)
        try context.save()
        #expect(SeatingPlan.occupants(in: room, schoolClass: first).mapValues(\.id) == [tables[1].id: emma.id, tables[0].id: ben.id])

        SeatingPlan.move(emma, to: tables[2], in: context)
        try context.save()
        #expect(SeatingPlan.occupants(in: room, schoolClass: first).mapValues(\.id) == [tables[2].id: emma.id, tables[0].id: ben.id])

        SeatingPlan.clear(tables[2], schoolClass: first, in: context)
        SeatingPlan.move(emma, to: tables[0], in: context)
        try context.save()
        #expect(SeatingPlan.occupants(in: room, schoolClass: first).mapValues(\.id) == [tables[0].id: emma.id])
        #expect(try context.fetchCount(FetchDescriptor<SeatAssignment>()) == 1)
    }

    @Test("Excel: Sitzplätze überstehen Export und Import")
    func seatingBackupRoundTrip() throws {
        let fixture = try Self.fixture()
        let (context, room, tables, first, second) = (fixture.context, fixture.room, fixture.tables, fixture.first, fixture.second)
        for (index, student) in first.students.enumerated() {
            SeatingPlan.assign(student, to: tables[index], in: context)
        }
        SeatingPlan.assign(try #require(second.students.first), to: tables[0], in: context)
        try context.save()
        let expectedFirst = SeatingPlan.occupants(in: room, schoolClass: first).mapValues(\.id)
        let expectedSecond = SeatingPlan.occupants(in: room, schoolClass: second).mapValues(\.id)

        let data = try Backup.export(context: context, settings: SchoolSettings.Values(), appearance: .system)
        let target = try Self.makeContext()
        let result = try Backup.import(data, context: target, currentSettings: SchoolSettings.Values())

        #expect(result.summary.seats == 3)
        let importedRoom = try #require(try target.fetch(FetchDescriptor<Room>()).first)
        let classes = try target.fetch(FetchDescriptor<SchoolClass>())
        let importedFirst = try #require(classes.first { $0.id == first.id })
        let importedSecond = try #require(classes.first { $0.id == second.id })
        #expect(SeatingPlan.occupants(in: importedRoom, schoolClass: importedFirst).mapValues(\.id) == expectedFirst)
        #expect(SeatingPlan.occupants(in: importedRoom, schoolClass: importedSecond).mapValues(\.id) == expectedSecond)
    }

    @Test("Notizen-Tab steht nach den Räumen und nutzt die Klassenauswahl")
    func notesTab() {
        #expect(AppTabSection.schoolClass.tabs == [.rooms, .notes])
        #expect(AppTab.notes.usesClassSelection)
        #expect(AppTab.notes.symbol == .custom(.notes))
    }

    @Test("PDF des Sitzplans wird erzeugt")
    @MainActor
    func seatingPDF() throws {
        let fixture = try Self.fixture()
        let student = try #require(fixture.first.students.first)
        SeatingPlan.assign(student, to: fixture.tables[0], in: fixture.context)
        let occupants = SeatingPlan.occupants(in: fixture.room, schoolClass: fixture.first)
        let url = try #require(SeatingPlanPDF.make(room: fixture.room, subtitle: "R 1 · Klasse 7b", occupants: occupants))
        #expect(try Data(contentsOf: url).count > 1000)
    }

    @Test("Termin mit Raum: übersteht Excel, Raum löschen lässt den Termin ohne Raum")
    func entryRoom() throws {
        let fixture = try Self.fixture()
        let (context, room) = (fixture.context, fixture.room)
        let entry = CalendarEntry(title: "Vertretung", start: .now, end: .now.addingTimeInterval(2700))
        context.insert(entry)
        entry.room = room
        try context.save()

        let data = try Backup.export(context: context, settings: SchoolSettings.Values(), appearance: .system)
        let target = try Self.makeContext()
        _ = try Backup.import(data, context: target, currentSettings: SchoolSettings.Values())
        let imported = try #require(try target.fetch(FetchDescriptor<CalendarEntry>()).first)
        #expect(imported.room?.id == room.id)

        context.delete(room)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<CalendarEntry>()).first?.room == nil)
    }

    @Test("Geschlechts-Symbole werden auf ihre sichtbare Mitte verschoben", arguments: [Gender.female, .male, .diverse])
    @MainActor
    func glyphCentering(gender: Gender) {
        let offset = GlyphCentering.offset(of: gender.symbol, size: 20, weight: .bold)
        #expect(abs(offset.width) < 10 && abs(offset.height) < 10)
        #expect(GlyphCentering.offset(of: "", size: 20, weight: .bold) == .zero)
    }
}
