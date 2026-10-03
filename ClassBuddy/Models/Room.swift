import Foundation
import SwiftData

/// Raum der Schule mit Grundriss auf einem Punktraster (`RoomElement`).
/// Später Grundlage für den Sitzplan: jeder Tisch ist ein Sitzplatz.
@Model
final class Room {
    @Attribute(.unique) var id: UUID
    /// Kurzname, z. B. „R 204“.
    var name: String
    /// Zusatz, z. B. „Physikraum, 2. OG“.
    var subtitle: String
    var categoryRaw: String
    /// Fächer, die hier unterrichtet werden können; leer = alle Fächer (generischer Klassenraum).
    var assignments: [String] = []
    /// Ausstattung (Beamer, Whiteboard …), siehe `Room.suggestedEquipment`.
    var equipment: [String] = []
    var sortIndex: Int = 0
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RoomElement.room)
    var elements: [RoomElement] = []

    /// Stunden in diesem Raum; beim Löschen des Raums bleiben sie ohne Raum erhalten.
    @Relationship(deleteRule: .nullify, inverse: \Lesson.room)
    var lessons: [Lesson] = []

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String = "",
        category: RoomCategory = .classroom,
        assignments: [String] = [],
        sortIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.categoryRaw = category.rawValue
        self.assignments = assignments
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var category: RoomCategory {
        get { RoomCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Elemente in Zeichenreihenfolge als reine Werte (für Geometrie, Vorschau und Editor).
    var shapes: [RoomShape] {
        elements.sorted { $0.order < $1.order }.map(\.shape)
    }

    /// Sitzplätze = Tische.
    var seatCount: Int {
        elements.count { $0.kind == .table }
    }

    /// Fach darf hier unterrichtet werden (keine Zuordnung = alle Fächer).
    func allows(subject: String) -> Bool {
        assignments.isEmpty || subject.isEmpty || assignments.contains(subject)
    }

    /// „Physik, Chemie“ bzw. „Alle Fächer“.
    var assignmentsText: String {
        assignments.isEmpty ? loc("Alle Fächer") : assignments.map(SchoolClass.displayName(ofSubject:)).joined(separator: ", ")
    }

    /// Ersetzt die Elemente durch `shapes` (normalisiert). Elemente mit gleicher ID, Art und gleichen Punkten
    /// behalten ihre Sitzplatz-Zuordnungen; geänderte verlieren sie, entfernte werden gelöscht.
    func replaceElements(with shapes: [RoomShape], in context: ModelContext) {
        let offset = RoomGeometry.roomBounds(shapes)?.min ?? .zero
        let existing = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kept = RoomElementSync.unchangedIDs(old: self.shapes, new: shapes)
        var result: [RoomElement] = []
        for (order, shape) in shapes.enumerated() {
            let points = shape.points.map { $0 - offset }
            if let element = existing[shape.id] {
                if !kept.contains(shape.id) {
                    element.seatAssignments.forEach(context.delete)
                    element.kindRaw = shape.kind.rawValue
                }
                element.points = points
                element.order = order
                result.append(element)
            } else {
                let element = RoomElement(id: shape.id, kind: shape.kind, points: points, order: order)
                context.insert(element)
                result.append(element)
            }
        }
        let resultIDs = Set(result.map(\.id))
        for element in elements where !resultIDs.contains(element.id) {
            context.delete(element)
        }
        elements = result
        updatedAt = .now
    }

    /// Vorschläge für die Ausstattung; eigene Einträge sind möglich.
    static let suggestedEquipment = [
        "Beamer", "Whiteboard", "Kreidetafel", "Interaktive Tafel", "Dokumentenkamera", "Lautsprecher",
        "Steckdosen an den Tischen", "Waschbecken", "Abzug", "Computer", "Verdunkelung",
    ]

    /// Ausstattung in der App-Sprache (Vorschläge übersetzt, eigene Einträge unverändert).
    static func displayName(ofEquipment item: String) -> String {
        equipmentNames[item].map(loc) ?? item
    }

    private static let equipmentNames: [String: LocalizedStringResource] = [
        "Beamer": "Beamer",
        "Whiteboard": "Whiteboard",
        "Kreidetafel": "Kreidetafel",
        "Interaktive Tafel": "Interaktive Tafel",
        "Dokumentenkamera": "Dokumentenkamera",
        "Lautsprecher": "Lautsprecher",
        "Steckdosen an den Tischen": "Steckdosen an den Tischen",
        "Waschbecken": "Waschbecken",
        "Abzug": "Abzug",
        "Computer": "Computer",
        "Verdunkelung": "Verdunkelung",
    ]
}

/// Linienzug eines Raums (Umriss, Tisch, Tafel …). Bei Flächen geschlossen (letzter Punkt = erster Punkt).
@Model
final class RoomElement {
    /// Stabil über das Normalisieren hinweg – daran hängt später die Sitzplatz-Zuordnung.
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var points: [GridPoint] = []
    /// Zeichenreihenfolge (SwiftData-Beziehungen sind ungeordnet).
    var order: Int = 0
    var room: Room?

    /// Sitzplan-Zuordnungen dieses Tisches; gehen verloren, wenn der Tisch geändert, geteilt oder entfernt wird.
    @Relationship(deleteRule: .cascade, inverse: \SeatAssignment.element)
    var seatAssignments: [SeatAssignment] = []

    init(id: UUID = UUID(), kind: RoomElementKind, points: [GridPoint], order: Int = 0, room: Room? = nil) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.points = points
        self.order = order
        self.room = room
    }

    var kind: RoomElementKind { RoomElementKind(rawValue: kindRaw) ?? .board }

    var shape: RoomShape { RoomShape(id: id, kind: kind, points: points) }
}

/// Schüler auf einem Tisch (Sitzplan). Hängt am Tisch, nicht an einer Platznummer.
@Model
final class SeatAssignment {
    @Attribute(.unique) var id: UUID
    var element: RoomElement?
    var student: Student?
    var createdAt: Date

    init(id: UUID = UUID(), element: RoomElement?, student: Student?) {
        self.id = id
        self.element = element
        self.student = student
        self.createdAt = .now
    }
}

/// Abgleich alter und neuer Elemente beim Speichern (reine Logik, testbar).
nonisolated enum RoomElementSync {
    /// IDs der Elemente, die unverändert bleiben (gleiche ID, Art und Punkte). Die Punkte der neuen Elemente
    /// sind noch nicht normalisiert – der Editor arbeitet in denselben Koordinaten wie der gespeicherte Raum,
    /// darum ändert Normalisieren allein nichts.
    static func unchangedIDs(old: [RoomShape], new: [RoomShape]) -> Set<UUID> {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(new.filter { shape in
            guard let previous = oldByID[shape.id] else { return false }
            return previous.kind == shape.kind && previous.points == shape.points
        }.map(\.id))
    }

    /// Tische, deren Zuordnungen beim Speichern verloren gehen (geändert, geteilt oder entfernt).
    static func changedTableIDs(old: [RoomShape], new: [RoomShape]) -> Set<UUID> {
        let kept = unchangedIDs(old: old, new: new)
        return Set(old.filter { $0.kind == .table && !kept.contains($0.id) }.map(\.id))
    }
}

/// Rasterpunkt: geräteunabhängig, nur ganze Zahlen.
nonisolated struct GridPoint: Codable, Hashable, Sendable {
    var x: Int
    var y: Int

    init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    static let zero = GridPoint(0, 0)

    static func + (lhs: GridPoint, rhs: GridPoint) -> GridPoint { GridPoint(lhs.x + rhs.x, lhs.y + rhs.y) }
    static func - (lhs: GridPoint, rhs: GridPoint) -> GridPoint { GridPoint(lhs.x - rhs.x, lhs.y - rhs.y) }
}

nonisolated enum RoomCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case classroom, specialist, gym, hall, other

    var id: String { rawValue }

    /// Wert im Excel-Backup und Erkennung beim Import (immer Deutsch).
    var title: String {
        switch self {
        case .classroom: "Klassenraum"
        case .specialist: "Fachraum"
        case .gym: "Sporthalle"
        case .hall: "Aula"
        case .other: "Sonstiges"
        }
    }

    var displayTitle: String {
        switch self {
        case .classroom: loc("Klassenraum")
        case .specialist: loc("Fachraum")
        case .gym: loc("Sporthalle")
        case .hall: loc("Aula")
        case .other: loc("Sonstiges")
        }
    }
}

/// Art eines Raumelements = Stift in der Toolbox.
nonisolated enum RoomElementKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case outline, table, desk, board, door, window

    var id: String { rawValue }

    /// Geschlossene Fläche (sonst nur Linie).
    var isArea: Bool { self == .outline || self == .table || self == .desk }

    /// Liegt nur auf dem Raumumriss.
    var isOnOutline: Bool { self == .door || self == .window }

    /// Wert im Excel-Backup und Erkennung beim Import (immer Deutsch).
    var title: String {
        switch self {
        case .outline: "Raumumriss"
        case .table: "Tisch"
        case .desk: "Lehrerpult"
        case .board: "Tafel"
        case .door: "Tür"
        case .window: "Fenster"
        }
    }

    var displayTitle: String {
        switch self {
        case .outline: loc("Raumumriss")
        case .table: loc("Tisch")
        case .desk: loc("Lehrerpult")
        case .board: loc("Tafel")
        case .door: loc("Tür")
        case .window: loc("Fenster")
        }
    }
}

/// Raumelement als reiner Wert – Grundlage für Geometrie, Editor und Vorschau.
nonisolated struct RoomShape: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var kind: RoomElementKind
    var points: [GridPoint]

    init(id: UUID = UUID(), kind: RoomElementKind, points: [GridPoint]) {
        self.id = id
        self.kind = kind
        self.points = points
    }

    /// Geschlossener Linienzug (mindestens ein Dreieck, letzter Punkt = erster Punkt).
    var isClosed: Bool { points.count >= 4 && points.first == points.last }
}
