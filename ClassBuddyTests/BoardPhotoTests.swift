import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Tafelbild: Ersetzen, Löschregeln, Import")
struct BoardPhotoTests {
    init() {
        AppLanguage.current = .german
    }

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, BoardPhoto.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test("Ein Foto je Klasse und Fach; das neue ersetzt das alte")
    func replacePerSubject() throws {
        let context = try Self.makeContext()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik", "Deutsch"])
        context.insert(schoolClass)
        schoolClass.setBoardPhoto(Data([1]), subject: "Mathematik", takenAt: .now.addingTimeInterval(-60), in: context)
        schoolClass.setBoardPhoto(Data([2]), subject: "Deutsch", takenAt: .now.addingTimeInterval(-30), in: context)
        schoolClass.setBoardPhoto(Data([3]), subject: "Mathematik", in: context)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<BoardPhoto>()) == 2)
        #expect(schoolClass.boardPhoto(for: "Mathematik")?.imageData == Data([3]))
        #expect(schoolClass.latestBoardPhoto?.subject == "Mathematik")
    }

    @Test("Entferntes Fach und gelöschte Klasse löschen die Tafelbilder")
    func deletionRules() throws {
        let context = try Self.makeContext()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik", "Deutsch"])
        context.insert(schoolClass)
        schoolClass.setBoardPhoto(Data([1]), subject: "Mathematik", in: context)
        schoolClass.setBoardPhoto(Data([2]), subject: "Deutsch", in: context)
        try context.save()

        schoolClass.subjects = ["Deutsch"]
        schoolClass.removeBoardPhotosOfRemovedSubjects(in: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<BoardPhoto>()).map(\.subject) == ["Deutsch"])

        context.delete(schoolClass)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<BoardPhoto>()) == 0)
    }

    @Test("Excel-Import behält Tafelbilder von Klassen mit gleicher ID")
    func importKeepsPhotos() throws {
        let context = try Self.makeContext()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        context.insert(schoolClass)
        schoolClass.setBoardPhoto(Data([7]), subject: "Mathematik", in: context)
        try context.save()

        let data = try Backup.export(context: context, settings: SchoolSettings.Values(), appearance: .system, funStats: [:])
        _ = try Backup.import(data, context: context, currentSettings: SchoolSettings.Values())

        let photos = try context.fetch(FetchDescriptor<BoardPhoto>())
        #expect(photos.count == 1)
        #expect(photos.first?.imageData == Data([7]))
        #expect(photos.first?.schoolClass?.id == schoolClass.id)
    }
}
