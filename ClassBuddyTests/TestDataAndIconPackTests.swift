import Foundation
import SwiftData
import Testing
import UIKit
@testable import ClassBuddy

#if DEBUG
@Suite("Testdaten (Debug-Menü)")
struct DummyDataTests {
    private static func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self, DashboardLink.self,
            Room.self, RoomElement.self, SeatAssignment.self, BoardPhoto.self,
            Checklist.self, ChecklistCheck.self, SubjectSettings.self, StudentObservation.self, Absence.self,
            Assessment.self, AssessmentResult.self, PeriodGrade.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test("Testdaten: vier Klassen mit Schülern, Stunden, Terminen und Raum")
    func insertsEverything() throws {
        let context = try Self.context()
        let first = DummyData.insert(into: context, slotCount: 8)
        try context.save()

        let classes = try context.fetch(FetchDescriptor<SchoolClass>())
        #expect(Set(classes.map(\.id)) == Set(DummyData.classIDs))
        #expect(first.id == DummyData.classIDs[0])
        #expect(try context.fetchCount(FetchDescriptor<Student>()) == 12 + 10 + 9 + 8)
        #expect(try context.fetchCount(FetchDescriptor<Lesson>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<CalendarEntry>()) > 0)
        #expect(try context.fetchCount(FetchDescriptor<Room>()) == 1)
        // Jede Klasse hat Schüler, jeder Schüler einen Namen.
        for schoolClass in classes {
            #expect(!schoolClass.students.isEmpty)
            #expect(schoolClass.students.allSatisfy { !$0.firstName.isEmpty && !$0.lastName.isEmpty })
        }
    }

    @Test("Testdaten lassen sich vollständig wieder entfernen")
    func removesEverything() throws {
        let context = try Self.context()
        DummyData.insert(into: context, slotCount: 8)
        try context.save()

        DummyData.remove(from: context, classes: try context.fetch(FetchDescriptor<SchoolClass>()))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<SchoolClass>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CalendarEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Room>()) == 0)
        #expect(try context.fetch(FetchDescriptor<Holiday>()).allSatisfy { !$0.id.hasPrefix("dummy-") })
    }

    @Test("Eigene Klassen bleiben beim Entfernen der Testdaten erhalten")
    func keepsOwnClasses() throws {
        let context = try Self.context()
        DummyData.insert(into: context, slotCount: 6)
        let own = SchoolClass(shortName: "10d", subjects: ["Physik"], color: .red)
        context.insert(own)
        try context.save()

        DummyData.remove(from: context, classes: try context.fetch(FetchDescriptor<SchoolClass>()))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<SchoolClass>()).map(\.id) == [own.id])
    }
}
#endif

@Suite("Icon-Pakete & Icon-Themes")
struct IconPackTests {
    /// Eindeutige Paket-ID je Test (Pakete liegen im echten Application-Support-Ordner des Simulators).
    private static func uniqueID() -> String {
        "test-" + UUID().uuidString.prefix(8).lowercased()
    }

    private static func manifest(id: String, name: String = "Testpaket") -> Data {
        Data(#"{"id": "\#(id)", "name": "\#(name)", "author": "Test", "version": "1.0"}"#.utf8)
    }

    /// Einfache einseitige PDF (Kreis) wie aus `scripts/build-icon-pack.sh`.
    private static let pdf: Data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 24, height: 24)).pdfData { context in
        context.beginPage()
        UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 20, height: 20)).fill()
    }

    @Test("Gültiges Paket: nur bekannte Icons werden übernommen, Bild lässt sich zeichnen")
    func installsValidPack() throws {
        let id = Self.uniqueID()
        let archive = ZipArchive.write([
            (path: "Pack/manifest.json", data: Self.manifest(id: id)),
            (path: "Pack/calendar.pdf", data: Self.pdf),
            (path: "Pack/trash.pdf", data: Self.pdf),
            (path: "Pack/unknown-icon.pdf", data: Self.pdf),
            (path: "Pack/readme.txt", data: Data("hi".utf8)),
        ])
        let pack = try IconPackStore.install(archive: archive)
        defer { IconPackStore.remove(pack) }

        #expect(pack.id == id)
        #expect(pack.name == "Testpaket")
        #expect(pack.author == "Test")
        #expect(IconPackStore.installed().contains { $0.id == id })
        let files = try FileManager.default.contentsOfDirectory(atPath: pack.directory.path).sorted()
        #expect(files == ["calendar.pdf", "manifest.json", "trash.pdf"])

        let image = try #require(IconPackStore.image(for: .calendar, in: pack))
        #expect(image.size == CGSize(width: 24, height: 24))
        #expect(image.renderingMode == .alwaysTemplate)
        #expect(IconPackStore.image(for: .homeAlt, in: pack) == nil)
    }

    @Test("Gleiche ID ersetzt das alte Paket, Entfernen löscht den Ordner")
    func replacesAndRemoves() throws {
        let id = Self.uniqueID()
        let first = try IconPackStore.install(archive: ZipArchive.write([
            (path: "manifest.json", data: Self.manifest(id: id, name: "Alt")),
            (path: "calendar.pdf", data: Self.pdf),
        ]))
        let second = try IconPackStore.install(archive: ZipArchive.write([
            (path: "manifest.json", data: Self.manifest(id: id, name: "Neu")),
            (path: "trash.pdf", data: Self.pdf),
        ]))
        #expect(first.directory == second.directory)
        #expect(IconPackStore.installed().first { $0.id == id }?.name == "Neu")
        #expect(!FileManager.default.fileExists(atPath: second.pdfURL(for: .calendar).path))

        IconPackStore.remove(second)
        #expect(!FileManager.default.fileExists(atPath: second.directory.path))
        #expect(!IconPackStore.installed().contains { $0.id == id })
    }

    @Test("Ungültige Pakete werden mit passendem Grund abgelehnt")
    func rejectsInvalidPacks() {
        #expect(throws: IconPackStore.InstallError.invalidArchive) {
            try IconPackStore.install(archive: Data("kein zip".utf8))
        }
        #expect(throws: IconPackStore.InstallError.missingManifest) {
            try IconPackStore.install(archive: ZipArchive.write([(path: "calendar.pdf", data: Self.pdf)]))
        }
        #expect(throws: IconPackStore.InstallError.invalidManifest) {
            try IconPackStore.install(archive: ZipArchive.write([(path: "manifest.json", data: Self.manifest(id: "Ungültige ID"))]))
        }
        #expect(throws: IconPackStore.InstallError.invalidManifest) {
            try IconPackStore.install(archive: ZipArchive.write([(path: "manifest.json", data: Self.manifest(id: "ok", name: "  "))]))
        }
        #expect(throws: IconPackStore.InstallError.noIcons) {
            try IconPackStore.install(archive: ZipArchive.write([
                (path: "manifest.json", data: Self.manifest(id: Self.uniqueID())),
                (path: "calendar.pdf", data: Data("keine pdf".utf8)),
            ]))
        }
        #expect(throws: IconPackStore.InstallError.tooLarge) {
            try IconPackStore.install(archive: Data(count: IconPackStore.maxArchiveSize + 1))
        }
    }

    @Test("Download nur über https")
    func downloadRequiresHTTPS() async throws {
        let url = try #require(URL(string: "http://example.com/pack.zip"))
        await #expect(throws: IconPackStore.InstallError.notHTTPS) {
            try await IconPackStore.download(from: url)
        }
    }

    @Test("Jeder Ablehnungsgrund hat einen Text", arguments: [
        IconPackStore.InstallError.notHTTPS, .tooLarge, .download("Zeitüberschreitung"), .invalidArchive,
        .missingManifest, .invalidManifest, .noIcons,
    ])
    func errorTexts(error: IconPackStore.InstallError) {
        #expect(!(error.errorDescription ?? "").isEmpty)
    }

    @Test("Eingebaute Themes: IDs, Titel, kein Paket")
    func builtInThemes() {
        #expect(IconTheme.builtInThemes.map(\.id) == ["builtIn", "sfSymbols"])
        #expect(IconTheme.builtInThemes.map(\.title) == ["Iconoir", "SF Symbols"])
        #expect(IconTheme.builtInThemes.allSatisfy { $0.pack == nil })
        let pack = IconPack(id: "abc", name: "ABC")
        #expect(IconTheme.pack(pack).id == "pack:abc")
        #expect(IconTheme.pack(pack).title == "ABC")
        #expect(IconTheme.pack(pack).pack == pack)
    }

    @Test("Vorschau: jedes Icon in jedem Theme hat ein Bild, ein Paket mit Lücken fällt auf Iconoir zurück")
    @MainActor
    func previews() throws {
        let pack = try IconPackStore.install(archive: ZipArchive.write([
            (path: "manifest.json", data: Self.manifest(id: Self.uniqueID())),
            (path: "calendar.pdf", data: Self.pdf),
        ]))
        defer { IconPackStore.remove(pack) }

        let manager = IconManager.shared
        for icon in AppIcon.allCases {
            _ = manager.preview(icon, in: .builtIn)
            _ = manager.preview(icon, in: .sfSymbols)
            _ = manager.preview(icon, in: .pack(pack))
            _ = manager.image(icon)
            #expect(manager.uiImage(icon) != nil, "\(icon.rawValue) fehlt im aktiven Theme")
            #expect(UIImage(resource: icon.resource).size.width > 0, "\(icon.rawValue) fehlt im Asset-Katalog")
        }
    }

    @Test("Installierte Pakete erscheinen in der Theme-Auswahl und verschwinden beim Entfernen")
    @MainActor
    func managerListsPacks() throws {
        let pack = try IconPackStore.install(archive: ZipArchive.write([
            (path: "manifest.json", data: Self.manifest(id: Self.uniqueID())),
            (path: "calendar.pdf", data: Self.pdf),
        ]))
        let manager = IconManager.shared
        manager.reloadPacks()
        #expect(manager.themes.contains(.pack(pack)))

        manager.remove(pack)
        #expect(!manager.themes.contains(.pack(pack)))
        #expect(!FileManager.default.fileExists(atPath: pack.directory.path))
    }
}
