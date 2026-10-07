import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Checklisten: Abhaken, Löschregeln, Gruppen, Excel")
struct ChecklistTests {
    init() {
        AppLanguage.current = .german
    }

    private struct Fixture {
        let context: ModelContext
        let schoolClass: SchoolClass
        let students: [Student]
    }

    private static func fixture() throws -> Fixture {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Checklist.self, ChecklistCheck.self, BoardPhoto.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik", "Deutsch"])
        context.insert(schoolClass)
        let students = ["Anna", "Ben", "Cem"].map { Student(firstName: $0, lastName: "X", schoolClass: schoolClass) }
        students.forEach(context.insert)
        try context.save()
        return Fixture(context: context, schoolClass: schoolClass, students: students)
    }

    @Test("Abhaken setzt das Datum, Zurücknehmen entfernt es; Fortschritt zählt nur Schüler der Klasse")
    func checkAndUncheck() throws {
        let fixture = try Self.fixture()
        let checklist = Checklist(title: "Bücher", subject: "Mathematik", schoolClass: fixture.schoolClass)
        fixture.context.insert(checklist)
        let date = Date(timeIntervalSince1970: 1_000_000)
        checklist.check(fixture.students[0], at: date, in: fixture.context)
        checklist.check(fixture.students[0], at: .now, in: fixture.context)
        checklist.check(fixture.students[1], in: fixture.context)
        try fixture.context.save()

        #expect(checklist.check(for: fixture.students[0])?.checkedAt == date)
        #expect(checklist.progress.done == 2)
        #expect(checklist.progress.total == 3)

        checklist.uncheck(fixture.students[1], in: fixture.context)
        try fixture.context.save()
        #expect(checklist.check(for: fixture.students[1]) == nil)
        #expect(checklist.progress.done == 1)
    }

    @Test("Gelöschter Schüler, entferntes Fach und gelöschte Klasse räumen auf")
    func deletionRules() throws {
        let fixture = try Self.fixture()
        let math = Checklist(title: "Mathe", subject: "Mathematik", schoolClass: fixture.schoolClass)
        let global = Checklist(title: "Alle", schoolClass: fixture.schoolClass)
        [math, global].forEach(fixture.context.insert)
        global.check(fixture.students[0], in: fixture.context)
        try fixture.context.save()

        fixture.context.delete(fixture.students[0])
        try fixture.context.save()
        #expect(try fixture.context.fetchCount(FetchDescriptor<ChecklistCheck>()) == 0)

        fixture.schoolClass.subjects = ["Deutsch"]
        fixture.schoolClass.removeChecklistsOfRemovedSubjects(in: fixture.context)
        try fixture.context.save()
        #expect(try fixture.context.fetch(FetchDescriptor<Checklist>()).map(\.title) == ["Alle"])

        fixture.context.delete(fixture.schoolClass)
        try fixture.context.save()
        #expect(try fixture.context.fetchCount(FetchDescriptor<Checklist>()) == 0)
    }

    @Test("Gruppen: aktuelles Fach zuerst, dann alle Fächer, dann übrige Fächer")
    func grouping() {
        let ids = (0..<4).map { _ in UUID() }
        let now = Date.now
        let items = [
            ChecklistGrouping.Item(id: ids[0], subject: "Deutsch", updatedAt: now),
            ChecklistGrouping.Item(id: ids[1], subject: "", updatedAt: now),
            ChecklistGrouping.Item(id: ids[2], subject: "Mathematik", updatedAt: now.addingTimeInterval(-60)),
            ChecklistGrouping.Item(id: ids[3], subject: "Mathematik", updatedAt: now),
        ]
        let groups = ChecklistGrouping.groups(items, subjects: ["Mathematik", "Deutsch"], current: "Deutsch")
        #expect(groups.map(\.subject) == ["Deutsch", nil, "Mathematik"])
        #expect(groups[0].isCurrent)
        #expect(groups[2].ids == [ids[3], ids[2]])

        let withoutCurrent = ChecklistGrouping.groups(items, subjects: ["Mathematik", "Deutsch"], current: nil)
        #expect(withoutCurrent.map(\.subject) == [nil, "Mathematik", "Deutsch"])
    }

    @Test("Excel-Export und -Import behalten Checklisten und Haken")
    func backupRoundTrip() throws {
        let fixture = try Self.fixture()
        let checklist = Checklist(title: "Bücher", subtitle: "Bis Freitag", subject: "Deutsch", schoolClass: fixture.schoolClass)
        fixture.context.insert(checklist)
        checklist.check(fixture.students[2], in: fixture.context)
        try fixture.context.save()

        let data = try Backup.export(context: fixture.context, settings: SchoolSettings.Values(), appearance: .system, funStats: [:])
        let result = try Backup.import(data, context: fixture.context, currentSettings: SchoolSettings.Values())
        #expect(result.summary.checklists == 1)

        let imported = try #require(try fixture.context.fetch(FetchDescriptor<Checklist>()).first)
        #expect(imported.id == checklist.id)
        #expect(imported.subtitle == "Bis Freitag")
        #expect(imported.subject == "Deutsch")
        #expect(imported.checks.compactMap { $0.student?.firstName } == ["Cem"])
    }

    @Test("Alle lokalen Daten löschen entfernt auch Checklisten, Haken und Tafelbilder")
    func deleteAll() throws {
        let fixture = try Self.fixture()
        let checklist = Checklist(title: "Bücher", schoolClass: fixture.schoolClass)
        fixture.context.insert(checklist)
        checklist.check(fixture.students[0], in: fixture.context)
        fixture.schoolClass.setBoardPhoto(Data([1]), subject: "Deutsch", in: fixture.context)
        try fixture.context.save()

        try LocalDataStore.deleteAll(in: fixture.context)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Checklist>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<ChecklistCheck>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<BoardPhoto>()) == 0)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Student>()) == 0)
    }

    @Test("PDF wird erzeugt, auch über mehrere Seiten")
    @MainActor
    func pdf() throws {
        let fixture = try Self.fixture()
        let checklist = Checklist(title: "Bücher", schoolClass: fixture.schoolClass)
        fixture.context.insert(checklist)
        let many = (0..<40).map { Student(firstName: "S\($0)", lastName: "X", schoolClass: fixture.schoolClass) }
        many.forEach(fixture.context.insert)
        let url = try #require(ChecklistPDF.make(checklist: checklist, students: fixture.schoolClass.sortedStudents))
        #expect(try Data(contentsOf: url).count > 1000)
    }
}
