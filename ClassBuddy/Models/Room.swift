import Foundation
import SwiftData

/// Raum der Schule mit Grundriss auf einem Punktraster (`RoomElement`).
/// Später Grundlage für den Sitzplan: jeder Tisch ist ein Sitzplatz.
@Model
final class Room {
    @Attribute(.unique) var id: UUID
    var lastModified: Date = Date.distantPast
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

    /// Termine in diesem Raum; beim Löschen des Raums bleiben sie ohne Raum erhalten.
    @Relationship(deleteRule: .nullify, inverse: \CalendarEntry.room)
    var calendarEntries: [CalendarEntry] = []

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
        // Auf einen Rasterpunkt verschieben, damit das Raster unter dem Raum gleich bleibt.
        let offset = RoomGeometry.roomBounds(shapes)?.min.gridFloor ?? .zero
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
    var lastModified: Date = Date.distantPast
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
    var lastModified: Date = Date.distantPast
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

/// Rasterpunkt: geräteunabhängig und exakt. Fast immer ein Punkt des Rasters; Kantenmitten aus dem Raum-Editor
/// liegen genau dazwischen (Hälfte, Viertel, Achtel). Darum zählen `x` und `y` in Achteln eines Rasterschritts,
/// als ganze Zahlen: Geometrie rechnet exakt, nichts wird gerundet, gemeinsame Kanten schließen lückenlos.
nonisolated struct GridPoint: Hashable, Sendable {
    /// Achtel je Rasterschritt.
    static let subdivisions = 8

    /// In Achteln eines Rasterschritts.
    var x: Int
    var y: Int

    /// Punkt des Rasters (ganze Rasterschritte).
    init(_ x: Int, _ y: Int) {
        self.init(eighths: x * Self.subdivisions, y * Self.subdivisions)
    }

    init(eighths x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    static let zero = GridPoint(0, 0)

    /// Liegt auf einem Punkt des Rasters.
    var isOnGrid: Bool { x.isMultiple(of: Self.subdivisions) && y.isMultiple(of: Self.subdivisions) }

    /// Nächster Rasterpunkt links oberhalb (oder der Punkt selbst).
    var gridFloor: GridPoint {
        GridPoint(Int(floor(Double(x) / Double(Self.subdivisions))), Int(floor(Double(y) / Double(Self.subdivisions))))
    }

    /// Genaue Mitte zwischen zwei Punkten; `nil`, wenn sie feiner als ein Achtel wäre.
    static func midpoint(_ first: GridPoint, _ second: GridPoint) -> GridPoint? {
        let sumX = first.x + second.x, sumY = first.y + second.y
        guard sumX.isMultiple(of: 2), sumY.isMultiple(of: 2) else { return nil }
        return GridPoint(eighths: sumX / 2, sumY / 2)
    }

    static func + (lhs: GridPoint, rhs: GridPoint) -> GridPoint { GridPoint(eighths: lhs.x + rhs.x, lhs.y + rhs.y) }
    static func - (lhs: GridPoint, rhs: GridPoint) -> GridPoint { GridPoint(eighths: lhs.x - rhs.x, lhs.y - rhs.y) }
}

/// Gespeichert wie bisher als ganze Rasterschritte `x`/`y`; nur Punkte zwischen dem Raster haben zusätzlich
/// `fx`/`fy` (Achtel 1 bis 7). Rasterpunkte und gespeicherte Räume älterer Versionen bleiben damit unverändert.
extension GridPoint: Codable {
    private enum CodingKeys: String, CodingKey {
        case x, y
        case fractionX = "fx"
        case fractionY = "fy"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fractionX = try container.decodeIfPresent(Int.self, forKey: .fractionX) ?? 0
        let fractionY = try container.decodeIfPresent(Int.self, forKey: .fractionY) ?? 0
        self.init(
            eighths: try container.decode(Int.self, forKey: .x) * Self.subdivisions + fractionX,
            try container.decode(Int.self, forKey: .y) * Self.subdivisions + fractionY
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let floor = gridFloor
        try container.encode(floor.x / Self.subdivisions, forKey: .x)
        try container.encode(floor.y / Self.subdivisions, forKey: .y)
        if x != floor.x { try container.encode(x - floor.x, forKey: .fractionX) }
        if y != floor.y { try container.encode(y - floor.y, forKey: .fractionY) }
    }
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
