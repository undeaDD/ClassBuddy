import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Räume: Editor, Abgleich & Verknüpfungen")
struct RoomEditorTests {
    init() {
        AppLanguage.current = .german
    }

    private static func p(_ x: Int, _ y: Int) -> GridPoint { GridPoint(x, y) }

    private static func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> [GridPoint] {
        [p(x, y), p(x + width, y), p(x + width, y + height), p(x, y + height), p(x, y)]
    }

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, Room.self, RoomElement.self, SeatAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Zeichnet einen geschlossenen Linienzug Strecke für Strecke.
    private static func draw(_ points: [GridPoint], in model: RoomEditorModel) {
        for (start, end) in zip(points, points.dropFirst()) {
            model.addSegment(from: start, to: end)
        }
    }

    // MARK: Zeichnen

    @Test("Linienzug läuft am letzten Punkt weiter und wird beim Erreichen des Starts geschlossen")
    func drawClosedOutline() throws {
        let model = RoomEditorModel(shapes: [])
        model.tool = .pen(.outline)
        Self.draw(Self.rect(0, 0, 6, 4), in: model)
        let outline = try #require(model.shapes.first)
        #expect(model.shapes.count == 1)
        #expect(outline.kind == .outline && outline.isClosed)
        #expect(model.anchor == nil)
        #expect(model.issues.isEmpty)
    }

    @Test("Antippen: Startpunkt, Verbinden, erneutes Antippen beendet die Linie")
    func tapToDraw() {
        let model = RoomEditorModel(shapes: [RoomShape(kind: .outline, points: Self.rect(0, 0, 6, 4))])
        model.tool = .pen(.board)
        model.tap(at: Self.p(1, 0))
        #expect(model.anchor == Self.p(1, 0))
        model.tap(at: Self.p(5, 0))
        #expect(model.shapes.last?.points == [Self.p(1, 0), Self.p(5, 0)])
        model.tap(at: Self.p(5, 0))
        #expect(model.anchor == nil)
        #expect(model.issues.isEmpty)
    }

    @Test("Neue Strecke an anderer Stelle beginnt ein neues Element; offene Fläche ist ungültig")
    func openAreaIsInvalid() {
        let model = RoomEditorModel(shapes: [RoomShape(kind: .outline, points: Self.rect(0, 0, 10, 8))])
        model.tool = .pen(.table)
        model.addSegment(from: Self.p(1, 1), to: Self.p(3, 1))
        model.addSegment(from: Self.p(5, 5), to: Self.p(6, 5))
        #expect(model.shapes.count == 3)
        #expect(model.issues.contains(.incomplete(model.shapes[1].id)))
        // Das Element, an dem gerade gezeichnet wird, ist nicht rot markiert.
        #expect(model.invalidIDs == [model.shapes[1].id])
    }

    @Test("Tisch-Stift von Rand zu Rand innerhalb eines Tisches teilt ihn")
    func splitWithTablePen() {
        let model = RoomEditorModel(shapes: [
            RoomShape(kind: .outline, points: Self.rect(0, 0, 10, 8)),
            RoomShape(kind: .table, points: Self.rect(2, 2, 4, 2)),
        ])
        model.tool = .pen(.table)
        model.addSegment(from: Self.p(4, 2), to: Self.p(4, 3))
        #expect(model.splitDraft != nil)
        model.addSegment(from: Self.p(4, 3), to: Self.p(4, 4))
        let tables = model.shapes.filter { $0.kind == .table }
        #expect(tables.count == 2)
        #expect(model.splitDraft == nil)
        #expect(model.issues.isEmpty)
    }

    @Test("Radierer entfernt nur beim Treffen der Linie; Rückgängig und Wiederholen")
    func eraseAndUndo() {
        let table = RoomShape(kind: .table, points: Self.rect(2, 2, 2, 2))
        let board = RoomShape(kind: .board, points: [Self.p(1, 0), Self.p(5, 0)])
        let model = RoomEditorModel(shapes: [RoomShape(kind: .outline, points: Self.rect(0, 0, 10, 8)), table, board])
        model.tool = .eraser
        // Mitte des Tisches: keine Kante getroffen.
        model.erase(at: RoomGeometry.Vector(3, 3), tolerance: 0.3)
        #expect(model.shapes.contains(table))
        model.erase(at: RoomGeometry.Vector(3, 2.1), tolerance: 0.3)
        #expect(!model.shapes.contains(table))
        model.erase(at: RoomGeometry.Vector(3, 0.1), tolerance: 0.3)
        #expect(!model.shapes.contains(board))
        #expect(model.hasChanges)

        model.undo()
        #expect(model.shapes.contains(board))
        model.undo()
        #expect(model.shapes.contains(table))
        #expect(!model.hasChanges)
        model.redo()
        #expect(!model.shapes.contains(table))
    }

    @Test("Verschieben ist Standard: Antippen und Strecken zeichnen nichts")
    func moveToolDrawsNothing() {
        let model = RoomEditorModel(shapes: [])
        #expect(model.tool == .move)
        model.tap(at: Self.p(1, 1))
        model.addSegment(from: Self.p(1, 1), to: Self.p(3, 1))
        #expect(model.shapes.isEmpty && model.anchor == nil)
    }

    @Test("Pencil-Doppeltippen wechselt zwischen Stift und Radierer")
    func toggleEraser() {
        let model = RoomEditorModel(shapes: [])
        model.tool = .pen(.desk)
        model.toggleEraser()
        #expect(model.tool == .eraser)
        model.toggleEraser()
        #expect(model.tool == .pen(.desk))
    }

    @Test("Einrasten und Zoomen um einen festen Punkt")
    func viewport() {
        let model = RoomEditorModel(shapes: [])
        model.pan = CGSize(width: 10, height: 20)
        #expect(model.snap(CGPoint(x: 10 + 2.4 * RoomEditorModel.gridSpacing, y: 20)) == Self.p(2, 0))
        let focus = CGPoint(x: 100, y: 100)
        let before = model.gridLocation(focus)
        model.zoom(by: 2, around: focus)
        #expect(model.zoom == 2)
        let after = model.gridLocation(focus)
        #expect(abs(before.x - after.x) < 1e-9 && abs(before.y - after.y) < 1e-9)
    }

    // MARK: Abgleich beim Speichern

    @Test("Geänderte und entfernte Tische verlieren ihre Zuordnung, unveränderte nicht")
    func changedTables() {
        let kept = RoomShape(kind: .table, points: Self.rect(1, 1, 1, 1))
        let moved = RoomShape(kind: .table, points: Self.rect(3, 1, 1, 1))
        let removed = RoomShape(kind: .table, points: Self.rect(5, 1, 1, 1))
        var movedNew = moved
        movedNew.points = Self.rect(3, 2, 1, 1)
        #expect(RoomElementSync.changedTableIDs(old: [kept, moved, removed], new: [kept, movedNew]) == [moved.id, removed.id])
    }

    @Test("Speichern normalisiert, behält Zuordnungen unveränderter Tische und löscht die anderen")
    func replaceElementsKeepsAssignments() throws {
        let context = try Self.makeContext()
        let room = Room(name: "R 1")
        context.insert(room)
        let outline = RoomShape(kind: .outline, points: Self.rect(0, 0, 8, 6))
        let first = RoomShape(kind: .table, points: Self.rect(1, 1, 2, 1))
        let second = RoomShape(kind: .table, points: Self.rect(4, 1, 2, 1))
        room.replaceElements(with: [outline, first, second], in: context)
        let student = Student(firstName: "Emma", lastName: "S")
        context.insert(student)
        for element in room.elements where element.kind == .table {
            context.insert(SeatAssignment(element: element, student: student))
        }
        try context.save()

        // Raum nach links erweitert (Normalisieren verschiebt alles), zweiter Tisch entfernt.
        let wider = RoomShape(id: outline.id, kind: .outline, points: Self.rect(-2, 0, 10, 6))
        room.replaceElements(with: [wider, first], in: context)
        try context.save()

        #expect(room.elements.count == 2)
        let table = try #require(room.elements.first { $0.id == first.id })
        #expect(table.points == Self.rect(3, 1, 2, 1))
        #expect(table.seatAssignments.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<SeatAssignment>()) == 1)
        #expect(RoomGeometry.roomBounds(room.shapes)?.min == .zero)
    }

    @Test("Demo-Klassenzimmer ist gültig und wird nur einmal angelegt")
    func demoRoom() throws {
        #expect(RoomValidation.isValid(RoomDemo.shapes))
        let context = try Self.makeContext()
        let defaults = try #require(UserDefaults(suiteName: "RoomEditorTests.demo"))
        defaults.removePersistentDomain(forName: "RoomEditorTests.demo")
        RoomDemo.createIfNeeded(in: context, defaults: defaults)
        let room = try #require(try context.fetch(FetchDescriptor<Room>()).first)
        #expect(room.seatCount == 12)
        context.delete(room)
        try context.save()
        RoomDemo.createIfNeeded(in: context, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<Room>()) == 0)
    }

    // MARK: Verknüpfungen

    @Test("Fächer-Zuordnung: leer = alle Fächer")
    func subjectAssignment() {
        let generic = Room(name: "R 1")
        let lab = Room(name: "Physik", assignments: ["Physik", "Chemie"])
        #expect(generic.allows(subject: "Sport"))
        #expect(lab.allows(subject: "Chemie"))
        #expect(!lab.allows(subject: "Deutsch"))
        #expect(generic.assignmentsText == "Alle Fächer")
    }

    @Test("Aktueller Raum: laufende Stunde vor nächster Stunde der Klasse")
    func roomLocator() throws {
        let context = try Self.makeContext()
        let schoolClass = SchoolClass(shortName: "7b")
        let room = Room(name: "R 204")
        context.insert(schoolClass)
        context.insert(room)
        // Montag, 2. Stunde (09:00–09:45) im Raum, 1. Stunde ohne Raum.
        let withRoom = Lesson(weekday: 0, slotIndex: 1, subject: "Physik", isRecurring: true, date: nil, schoolClass: schoolClass)
        let withoutRoom = Lesson(weekday: 0, slotIndex: 0, subject: "Mathe", isRecurring: true, date: nil, schoolClass: schoolClass)
        context.insert(withRoom)
        context.insert(withoutRoom)
        withRoom.room = room
        let slots = [LessonSlot(index: 0, start: 8 * 60, end: 8 * 60 + 45), LessonSlot(index: 1, start: 9 * 60, end: 9 * 60 + 45)]
        let schedule = LessonSchedule(lessons: [withRoom, withoutRoom], holidays: [], slots: slots)
        let monday = try #require(Calendar.school.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8, minute: 10)))

        let next = try #require(RoomLocator.locate(schedule: schedule, classID: schoolClass.id, now: monday))
        #expect(!next.isCurrent && next.room.name == "R 204" && next.next.slot.index == 1)

        let during = try #require(RoomLocator.locate(schedule: schedule, classID: schoolClass.id, now: monday.addingTimeInterval(60 * 60)))
        #expect(during.isCurrent)
    }

    @Test("Punkte im Excel-Format")
    func pointCells() {
        let points = [Self.p(0, 0), Self.p(12, -3)]
        #expect(Backup.Cell.points(points) == "0,0; 12,-3")
        #expect(Backup.Cell.parsePoints(" 0, 0 ;12,-3 ") == points)
        #expect(Backup.Cell.parsePoints("0,0; x,1") == nil)
        #expect(Backup.Cell.parseRoomElementKind("tisch") == .table)
        #expect(Backup.Cell.parseRoomCategory("Aula") == .hall)
    }

    // MARK: Excel

    @Test("Excel: Räume, Elemente und Raum der Stunde überstehen Export und Import")
    func backupRoundTrip() throws {
        let source = try Self.makeContext()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Physik"])
        source.insert(schoolClass)
        let room = Room(name: "R 204", subtitle: "2. OG", category: .specialist, assignments: ["Physik"], sortIndex: 3)
        room.equipment = ["Beamer", "Eigene Lampe"]
        source.insert(room)
        let shapes = [
            RoomShape(kind: .outline, points: Self.rect(0, 0, 8, 6)),
            RoomShape(kind: .table, points: Self.rect(1, 1, 2, 1)),
            RoomShape(kind: .door, points: [Self.p(8, 2), Self.p(8, 4)]),
        ]
        room.replaceElements(with: shapes, in: source)
        let lesson = Lesson(weekday: 1, slotIndex: 2, subject: "Physik", isRecurring: true, date: nil, schoolClass: schoolClass)
        source.insert(lesson)
        lesson.room = room
        try source.save()

        let data = try Backup.export(context: source, settings: SchoolSettings.Values(), appearance: .system)
        let target = try Self.makeContext()
        let result = try Backup.import(data, context: target, currentSettings: SchoolSettings.Values())

        #expect(result.summary.rooms == 1)
        #expect(result.summary.invalidRooms.isEmpty)
        let imported = try #require(try target.fetch(FetchDescriptor<Room>()).first)
        #expect(imported.id == room.id)
        #expect(imported.name == "R 204" && imported.subtitle == "2. OG" && imported.category == .specialist)
        #expect(imported.assignments == ["Physik"] && imported.equipment == ["Beamer", "Eigene Lampe"])
        #expect(imported.sortIndex == 3)
        #expect(imported.shapes == shapes)
        let importedLesson = try #require(try target.fetch(FetchDescriptor<Lesson>()).first)
        #expect(importedLesson.room?.id == room.id)
    }

    @Test("Excel: ungültige Räume werden übersprungen")
    func importSkipsInvalidRooms() throws {
        let data = XLSX.write([
            XLSXSheet(name: Backup.Sheet.info, rows: [["Schlüssel", "Wert"], ["Format", Backup.formatName]]),
            XLSXSheet(name: Backup.Sheet.rooms, rows: [
                ["ID", "Name", "Kategorie"],
                ["11111111-1111-1111-1111-111111111111", "Gut", "Aula"],
                ["22222222-2222-2222-2222-222222222222", "Offen", "Aula"],
                ["33333333-3333-3333-3333-333333333333", "Unlesbar", "Aula"],
            ]),
            XLSXSheet(name: Backup.Sheet.roomElements, rows: [
                ["Raum-ID", "Art", "Punkte"],
                ["11111111-1111-1111-1111-111111111111", "Raumumriss", "0,0; 4,0; 4,4; 0,4; 0,0"],
                ["22222222-2222-2222-2222-222222222222", "Raumumriss", "0,0; 4,0; 4,4"],
                ["33333333-3333-3333-3333-333333333333", "Sofa", "0,0; 4,0; 4,4; 0,0"],
            ]),
        ])
        let result = try Backup.import(data, context: try Self.makeContext(), currentSettings: SchoolSettings.Values())
        #expect(result.summary.rooms == 1)
        #expect(result.summary.invalidRooms == ["Offen", "Unlesbar"])
    }

    @Test("Excel: ältere Datei ohne Raum-Blätter lässt vorhandene Räume unverändert")
    func importKeepsRoomsForOlderFiles() throws {
        let context = try Self.makeContext()
        let room = Room(name: "Bleibt")
        context.insert(room)
        room.replaceElements(with: [RoomShape(kind: .outline, points: Self.rect(0, 0, 4, 4))], in: context)
        try context.save()

        let data = XLSX.write([
            XLSXSheet(name: Backup.Sheet.info, rows: [["Schlüssel", "Wert"], ["Format", Backup.formatName]]),
            XLSXSheet(name: Backup.Sheet.classes, rows: [["ID", "Kürzel"], [UUID().uuidString, "5a"]]),
        ])
        let result = try Backup.import(data, context: context, currentSettings: SchoolSettings.Values())
        #expect(result.summary.classes == 1)
        #expect(try context.fetch(FetchDescriptor<Room>()).map(\.name) == ["Bleibt"])
        #expect(try context.fetchCount(FetchDescriptor<RoomElement>()) == 1)
    }
}
