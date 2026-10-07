import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Zufallsgruppen: Aufteilung, Vorbelegung, Speichern")
struct RandomGroupsTests {
    init() {
        AppLanguage.current = .german
    }

    @Test("Nach Größe: möglichst nah an der Wunschgröße, bei Gleichstand größere Gruppen")
    func sizesBySize() {
        #expect(GroupSplit.sizes(studentCount: 24, mode: .size, value: 4) == [4, 4, 4, 4, 4, 4])
        #expect(GroupSplit.sizes(studentCount: 26, mode: .size, value: 4) == [5, 5, 4, 4, 4, 4])
        #expect(GroupSplit.sizes(studentCount: 11, mode: .size, value: 4) == [4, 4, 3])
        #expect(GroupSplit.sizes(studentCount: 9, mode: .size, value: 2) == [3, 2, 2, 2])
        #expect(GroupSplit.sizes(studentCount: 3, mode: .size, value: 2) == [3])
        #expect(GroupSplit.sizes(studentCount: 0, mode: .size, value: 4).isEmpty)
    }

    @Test("Nach Anzahl: Rest auf die ersten Gruppen verteilt")
    func sizesByCount() {
        #expect(GroupSplit.sizes(studentCount: 26, mode: .count, value: 5) == [6, 5, 5, 5, 5])
        #expect(GroupSplit.sizes(studentCount: 3, mode: .count, value: 5) == [1, 1, 1])
    }

    @Test("Vorbelegung: gleich große Gruppen, wenn möglich")
    func suggestion() {
        #expect(GroupSplit.suggestedValue(studentCount: 24, mode: .size) == 4)
        #expect(GroupSplit.suggestedValue(studentCount: 27, mode: .size) == 3)
        #expect(GroupSplit.suggestedValue(studentCount: 25, mode: .size) == 5)
        #expect(GroupSplit.suggestedValue(studentCount: 23, mode: .size) == 4)
        #expect(GroupSplit.suggestedValue(studentCount: 5, mode: .size) == 2)
        #expect(GroupSplit.suggestedValue(studentCount: 24, mode: .count) == 6)
    }

    @Test("Moduswechsel übernimmt die Aufteilung")
    func convert() {
        #expect(GroupSplit.convert(4, from: .size, studentCount: 24) == 6)
        #expect(GroupSplit.convert(6, from: .count, studentCount: 24) == 4)
    }

    @Test("Vorschau als ganzer Satz")
    func sentence() {
        #expect(GroupSplit.sentence(sizes: [4, 4]) == "Es entstehen 2 Gruppen mit je 4 Schülern.")
        #expect(GroupSplit.sentence(sizes: [5, 4]) == "Es entstehen 2 Gruppen mit 4 bis 5 Schülern.")
        #expect(GroupSplit.sentence(sizes: [3]) == "Es entsteht eine Gruppe mit allen 3 Schülern.")
        #expect(GroupSplit.shortSummary(sizes: [5, 5, 4]) == "3 × 4–5")
    }

    @Test("Jeder Schüler landet genau einmal in einer Gruppe")
    func dealUsesEveryone() {
        let ids = (0..<26).map { _ in UUID() }
        let result = StudentGroups.deal(ids, mode: .size, value: 4)
        #expect(result.groups.map(\.count) == [5, 5, 4, 4, 4, 4])
        #expect(Set(result.groups.flatMap { $0 }) == Set(ids))
        #expect(result.groups.flatMap { $0 }.count == ids.count)
    }

    @Test("Gespeichert je Klasse; gelöschte Schüler und leere Gruppen fallen weg")
    func storeAndResolve() throws {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let schoolClass = SchoolClass(shortName: "7b")
        context.insert(schoolClass)
        let students = ["Anna", "Ben", "Cem"].map { Student(firstName: $0, lastName: "X") }
        for student in students {
            context.insert(student)
            student.schoolClass = schoolClass
        }
        let groups = StudentGroups(mode: .count, value: 2, groups: [[students[0].id, students[1].id], [UUID()]], date: .now)
        schoolClass.lastGroups = groups
        try context.save()

        #expect(schoolClass.lastGroups == groups)
        let resolved = groups.resolved(in: schoolClass.sortedStudents)
        #expect(resolved.count == 1)
        #expect(Set(resolved[0].map(\.id)) == [students[0].id, students[1].id])
    }
}
