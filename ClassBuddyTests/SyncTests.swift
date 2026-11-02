import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

/// Zwei getrennte Datenbanken („Geräte“), die Pakete austauschen.
@Suite("Sync: Pakete schreiben und übernehmen")
@MainActor
struct SyncTests {
    private static let version = "1.0.0 (99)"

    init() {
        AppLanguage.current = .german
        SyncTracking.start()
    }

    /// Container festhalten: Ein Kontext ohne seinen Container stürzt beim nächsten Zugriff ab.
    private static var containers: [ModelContainer] = []

    private static func makeDevice() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self, DashboardLink.self,
            Room.self, RoomElement.self, SeatAssignment.self, BoardPhoto.self, Checklist.self, ChecklistCheck.self,
            SubjectSettings.self, StudentObservation.self, Absence.self, Assessment.self, AssessmentResult.self,
            PeriodGrade.self, DeletedRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        containers.append(container)
        return container.mainContext
    }

    /// Paket über JSON (wie beim echten Weg zwischen Geräten) von `source` nach `target`.
    @discardableResult
    private static func sync(from source: ModelContext, to target: ModelContext, since: Date? = nil) throws -> SyncResult {
        let package = try SyncEngine.makePackage(since: since, in: source, appVersion: version)
        let data = try JSONEncoder().encode(package)
        return try SyncEngine.apply(JSONDecoder().decode(SyncPackage.self, from: data), in: target, appVersion: version)
    }

    @Test("Erster Abgleich überträgt alles samt Beziehungen")
    func firstSync() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        deviceA.insert(schoolClass)
        let student = Student(firstName: "Emma", lastName: "Schneider", photo: Data([1, 2, 3]), schoolClass: schoolClass)
        deviceA.insert(student)
        let room = Room(name: "R 204")
        deviceA.insert(room)
        let points = [GridPoint(0, 0), GridPoint(eighths: 12, 4), GridPoint(0, 2), GridPoint(0, 0)]
        let table = RoomElement(kind: .table, points: points, room: room)
        deviceA.insert(table)
        deviceA.insert(SeatAssignment(element: table, student: student))
        deviceA.insert(StudentObservation(subject: "Mathematik", kind: .rating, scale: .sevenStep, value: 2, student: student))
        try deviceA.save()

        let result = try Self.sync(from: deviceA, to: deviceB)
        #expect(result.inserted == 6)
        let copied = try #require(try deviceB.fetch(FetchDescriptor<Student>()).first)
        #expect(copied.id == student.id && copied.fullName == "Emma Schneider" && copied.photo == Data([1, 2, 3]))
        #expect(copied.schoolClass?.shortName == "7b")
        #expect(copied.observations.first?.value == 2)
        #expect(copied.seatAssignments.first?.element?.points == table.points)
        #expect(copied.lastModified == student.lastModified)
    }

    @Test("Neuerer Stand gewinnt, älterer bleibt liegen")
    func newerWins() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice()
        let student = Student(firstName: "Emma", lastName: "Schneider")
        deviceA.insert(student)
        try deviceA.save()
        try Self.sync(from: deviceA, to: deviceB)

        let copy = try #require(try deviceB.fetch(FetchDescriptor<Student>()).first)
        copy.notes = "von B"
        try deviceB.save()
        let changeOnB = copy.lastModified

        // A hat nichts Neueres: B behält seinen Stand; B nach A überträgt die Notiz.
        #expect(try Self.sync(from: deviceA, to: deviceB).keptLocal == 1)
        #expect(copy.notes == "von B")
        #expect(try Self.sync(from: deviceB, to: deviceA, since: student.lastModified).updated == 1)
        #expect(student.notes == "von B")
        #expect(student.lastModified == changeOnB)
    }

    @Test("Löschen kommt an und wird weitergereicht, eine spätere Änderung gewinnt gegen das Löschen")
    func deletions() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice(), deviceC = try Self.makeDevice()
        let first = Student(firstName: "Ben", lastName: "Adler")
        let second = Student(firstName: "Lea", lastName: "Adler")
        deviceA.insert(first)
        deviceA.insert(second)
        try deviceA.save()
        try Self.sync(from: deviceA, to: deviceB)
        try Self.sync(from: deviceA, to: deviceC)

        deviceA.delete(first)
        deviceA.delete(second)
        try deviceA.save()
        // Auf C wurde Lea danach noch geändert.
        let leaOnC = try #require(try deviceC.fetch(FetchDescriptor<Student>()).first { $0.firstName == "Lea" })
        leaOnC.notes = "noch da"
        try deviceC.save()

        #expect(try Self.sync(from: deviceA, to: deviceB).deleted == 2)
        #expect(try deviceB.fetch(FetchDescriptor<Student>()).isEmpty)
        // B reicht die Löschungen an C weiter; Lea bleibt dort, weil später geändert.
        #expect(try Self.sync(from: deviceB, to: deviceC).deleted == 1)
        #expect(try deviceC.fetch(FetchDescriptor<Student>()).map(\.firstName) == ["Lea"])
        // Lea kommt mit ihrem neueren Stand auf B zurück, Ben bleibt gelöscht.
        try Self.sync(from: deviceC, to: deviceB)
        #expect(try deviceB.fetch(FetchDescriptor<Student>()).map(\.firstName) == ["Lea"])
    }

    @Test("Übernehmen stempelt nicht neu und hinterlässt keine eigenen Löschungen")
    func applyKeepsTimestamps() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice()
        let schoolClass = SchoolClass(shortName: "5a")
        deviceA.insert(schoolClass)
        try deviceA.save()
        try Self.sync(from: deviceA, to: deviceB)
        let copy = try #require(try deviceB.fetch(FetchDescriptor<SchoolClass>()).first)
        #expect(copy.lastModified == schoolClass.lastModified)
        // Nichts Neues seit dem letzten Stand von A: leeres Paket.
        let package = try SyncEngine.makePackage(since: schoolClass.lastModified, in: deviceB, appVersion: Self.version)
        #expect(package.entries.isEmpty && package.deletions.isEmpty)
    }

    @Test("Andere App-Version wird abgelehnt")
    func versionMismatch() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice()
        let package = try SyncEngine.makePackage(since: nil, in: deviceA, appVersion: "1.0.0 (11)")
        #expect(throws: SyncError.versionMismatch(remote: "1.0.0 (11)", local: Self.version)) {
            try SyncEngine.apply(package, in: deviceB, appVersion: Self.version)
        }
    }
}
