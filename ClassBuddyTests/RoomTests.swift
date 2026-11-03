import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Räume: Geometrie & Gültigkeit")
struct RoomTests {
    init() {
        AppLanguage.current = .german
    }

    private static func p(_ x: Int, _ y: Int) -> GridPoint { GridPoint(x, y) }

    /// `doubleArea` rechnet in Achteln je Richtung.
    private static let eighthsSquared = GridPoint.subdivisions * GridPoint.subdivisions

    /// Geschlossenes Rechteck von (x, y) mit Breite und Höhe.
    private static func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> [GridPoint] {
        [p(x, y), p(x + width, y), p(x + width, y + height), p(x, y + height), p(x, y)]
    }

    private static let outline = RoomShape(kind: .outline, points: rect(0, 0, 10, 8))

    // MARK: Einrasten & Grundlagen

    @Test("Einrasten auf den nächsten Rasterpunkt, auch negativ")
    func snapping() {
        #expect(RoomGeometry.snap(CGPoint(x: 31, y: 44), spacing: 20) == Self.p(2, 2))
        #expect(RoomGeometry.snap(CGPoint(x: 29, y: 51), spacing: 20) == Self.p(1, 3))
        #expect(RoomGeometry.snap(CGPoint(x: -31, y: -9), spacing: 20) == Self.p(-2, 0))
        #expect(RoomGeometry.position(of: Self.p(3, -1), spacing: 20) == CGPoint(x: 60, y: -20))
    }

    @Test("Punkt in Polygon: innen, Rand, außen – auch bei konkaven Flächen")
    func pointInPolygon() {
        // L-Form: unten rechts fehlt ein Quadrat.
        let shape = [Self.p(0, 0), Self.p(4, 0), Self.p(4, 2), Self.p(2, 2), Self.p(2, 4), Self.p(0, 4), Self.p(0, 0)]
        #expect(RoomGeometry.locate(Self.p(1, 1), in: shape) == .inside)
        #expect(RoomGeometry.locate(Self.p(3, 3), in: shape) == .outside)
        #expect(RoomGeometry.locate(Self.p(2, 3), in: shape) == .boundary)
        #expect(RoomGeometry.locate(Self.p(0, 0), in: shape) == .boundary)
        #expect(RoomGeometry.locate(Self.p(5, 1), in: shape) == .outside)
    }

    @Test("Kantenmitte: exakt in Achteln, Rasterpunkt erkannt, zu fein ergibt nil")
    func midpoints() throws {
        let half = try #require(GridPoint.midpoint(Self.p(0, 0), Self.p(3, 1)))
        #expect(half == GridPoint(eighths: 12, 4) && !half.isOnGrid)
        #expect(RoomGeometry.vector(half) == [1.5, 0.5])
        #expect(GridPoint.midpoint(Self.p(0, 0), Self.p(2, 4)) == Self.p(1, 2))
        #expect(GridPoint.midpoint(Self.p(0, 0), Self.p(2, 4))?.isOnGrid == true)
        // Mitte von Mitte bis zum Achtel, danach nicht mehr.
        let quarter = try #require(GridPoint.midpoint(Self.p(0, 0), half))
        let eighth = try #require(GridPoint.midpoint(Self.p(0, 0), quarter))
        #expect(eighth == GridPoint(eighths: 3, 1))
        #expect(GridPoint.midpoint(Self.p(0, 0), eighth) == nil)
        #expect(GridPoint(eighths: -3, 12).gridFloor == Self.p(-1, 1))
    }

    @Test("Speicherformat: Rasterpunkte wie bisher, Zwischenpunkte mit Achteln, alte Daten lesbar")
    func gridPointCoding() throws {
        let points = [Self.p(3, -2), GridPoint(eighths: 20, -3), GridPoint(eighths: -12, 7)]
        let data = try JSONEncoder().encode(points)
        #expect(try JSONDecoder().decode([GridPoint].self, from: data) == points)
        let whole = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.p(3, -2))) as? [String: Int]
        #expect(whole == ["x": 3, "y": -2])
        let old = Data(#"[{"x":4,"y":5}]"#.utf8)
        #expect(try JSONDecoder().decode([GridPoint].self, from: old) == [Self.p(4, 5)])
    }

    @Test("Schräger Tisch an Kantenmitten geteilt: Teile schließen lückenlos an den Mitten an")
    func splitAtMidpoints() throws {
        // Raute: Kanten schräg, ihre Mitten liegen zwischen den Rasterpunkten.
        let diamond = [Self.p(3, 0), Self.p(6, 1), Self.p(3, 2), Self.p(0, 1), Self.p(3, 0)]
        let start = try #require(GridPoint.midpoint(Self.p(3, 0), Self.p(6, 1)))
        let end = try #require(GridPoint.midpoint(Self.p(3, 2), Self.p(0, 1)))
        let result = try #require(RoomGeometry.split(diamond, along: [start, end]))
        #expect(result.first.contains(start) && result.first.contains(end))
        #expect(result.second.contains(start) && result.second.contains(end))
        // Zusammen genau die Fläche der Raute.
        let area = abs(RoomGeometry.doubleArea(result.first)) + abs(RoomGeometry.doubleArea(result.second))
        #expect(area == abs(RoomGeometry.doubleArea(diamond)))
    }

    @Test("Normalisieren mit Ecke zwischen dem Raster: Verschiebung nur um ganze Rasterschritte")
    func normalizingKeepsGrid() {
        let outline = RoomShape(kind: .outline, points: [
            GridPoint(eighths: 12, 4), Self.p(6, 1), Self.p(6, 5), Self.p(2, 5), GridPoint(eighths: 12, 4),
        ])
        let result = RoomGeometry.normalized([outline])
        #expect(result[0].points.first == GridPoint(eighths: 4, 4))
        #expect(result[0].points[1] == Self.p(5, 1))
    }

    @Test("Breite auf einer waagerechten Linie: Rechteck, Raute, L-Form, außen")
    func horizontalWidth() {
        #expect(RoomGeometry.horizontalWidth(at: [2, 1], in: Self.rect(0, 0, 4, 2)) == 4)
        // Raute (schräger Tisch): in der Mitte am breitesten, weiter oben schmaler.
        let diamond = [Self.p(2, 0), Self.p(4, 2), Self.p(2, 4), Self.p(0, 2), Self.p(2, 0)]
        #expect(RoomGeometry.horizontalWidth(at: [2, 2], in: diamond) == 4)
        #expect(RoomGeometry.horizontalWidth(at: [2, 1], in: diamond) == 2)
        // U-Form: nur der Abschnitt, in dem der Punkt liegt.
        let shape = [Self.p(0, 0), Self.p(1, 0), Self.p(1, 2), Self.p(2, 2), Self.p(2, 0), Self.p(3, 0),
                     Self.p(3, 3), Self.p(0, 3), Self.p(0, 0)]
        #expect(RoomGeometry.horizontalWidth(at: [0.5, 1], in: shape) == 1)
        #expect(RoomGeometry.horizontalWidth(at: [1.5, 1], in: shape) == nil)
    }

    @Test("Schnitte: echte Kreuzung, Berührung, kollinear")
    func intersections() {
        #expect(RoomGeometry.crossesProperly(Self.p(0, 0), Self.p(2, 2), Self.p(0, 2), Self.p(2, 0)))
        #expect(!RoomGeometry.crossesProperly(Self.p(0, 0), Self.p(2, 0), Self.p(1, 0), Self.p(1, 2)))
        #expect(RoomGeometry.intersects(Self.p(0, 0), Self.p(2, 0), Self.p(1, 0), Self.p(1, 2)))
        #expect(RoomGeometry.intersects(Self.p(0, 0), Self.p(3, 0), Self.p(2, 0), Self.p(5, 0)))
        #expect(!RoomGeometry.intersects(Self.p(0, 0), Self.p(1, 0), Self.p(2, 0), Self.p(5, 0)))
    }

    @Test("Einfache Flächen: Schleife, Selbstüberschneidung, Fläche 0, offen")
    func simplePolygons() {
        #expect(RoomGeometry.isSimplePolygon(Self.rect(0, 0, 2, 2)))
        // Schräge Kanten sind erlaubt.
        #expect(RoomGeometry.isSimplePolygon([Self.p(0, 0), Self.p(3, 1), Self.p(1, 3), Self.p(0, 0)]))
        // Schleife (Achterform).
        #expect(!RoomGeometry.isSimplePolygon([Self.p(0, 0), Self.p(2, 2), Self.p(2, 0), Self.p(0, 2), Self.p(0, 0)]))
        // Auf einer Linie hin und zurück.
        #expect(!RoomGeometry.isSimplePolygon([Self.p(0, 0), Self.p(2, 0), Self.p(1, 0), Self.p(0, 0)]))
        #expect(!RoomGeometry.isSimplePolygon([Self.p(0, 0), Self.p(2, 0), Self.p(2, 2)]))
    }

    // MARK: Normalisieren

    @Test("Normalisieren verschiebt die Umriss-Ecke auf 0/0, IDs bleiben")
    func normalizing() throws {
        let outline = RoomShape(kind: .outline, points: Self.rect(-3, 5, 4, 4))
        let table = RoomShape(kind: .table, points: Self.rect(-2, 6, 1, 1))
        let result = RoomGeometry.normalized([outline, table])
        #expect(result[0].points == Self.rect(0, 0, 4, 4))
        #expect(result[1].points == Self.rect(1, 1, 1, 1))
        #expect(result.map(\.id) == [outline.id, table.id])
        let bounds = try #require(RoomGeometry.roomBounds(result))
        #expect(bounds.min == .zero && bounds.max == Self.p(4, 4))
    }

    // MARK: Teilen

    @Test("Tisch teilen: gerade Linie von Kante zu Kante ergibt zwei angrenzende Tische")
    func splitStraight() throws {
        let result = try #require(RoomGeometry.split(Self.rect(0, 0, 4, 2), along: [Self.p(2, 0), Self.p(2, 2)]))
        // Doppelte Fläche in Rasterschritten (intern Achtel, darum durch 8 × 8).
        let areas = [result.first, result.second].map { abs(RoomGeometry.doubleArea($0)) / Self.eighthsSquared }
        #expect(areas == [8, 8])
        let tables = [result.first, result.second].map { RoomShape(kind: .table, points: $0) }
        #expect(RoomValidation.isValid([Self.outline] + tables))
    }

    @Test("Tisch teilen: Knick-Linie und Start in einer Ecke")
    func splitBent() throws {
        let result = try #require(RoomGeometry.split(Self.rect(0, 0, 4, 4), along: [Self.p(0, 0), Self.p(2, 2), Self.p(4, 2)]))
        let areas = Set([result.first, result.second].map { abs(RoomGeometry.doubleArea($0)) / Self.eighthsSquared })
        #expect(areas == [12, 20])
    }

    @Test("Ungültige Trennlinien: nach außen, nur am Rand entlang, endet innen")
    func splitInvalid() {
        let table = Self.rect(0, 0, 4, 2)
        #expect(RoomGeometry.split(table, along: [Self.p(2, 0), Self.p(2, 3)]) == nil)
        #expect(RoomGeometry.split(table, along: [Self.p(0, 0), Self.p(4, 0)]) == nil)
        #expect(RoomGeometry.split(table, along: [Self.p(2, 0), Self.p(2, 1)]) == nil)
        #expect(RoomGeometry.split(table, along: [Self.p(2, 0), Self.p(2, 0)]) == nil)
        // Verläuft kurz außerhalb des konkaven Tisches.
        let lShape = [Self.p(0, 0), Self.p(4, 0), Self.p(4, 2), Self.p(2, 2), Self.p(2, 4), Self.p(0, 4), Self.p(0, 0)]
        #expect(RoomGeometry.split(lShape, along: [Self.p(4, 1), Self.p(1, 4)]) == nil)
    }

    // MARK: Gültigkeit

    @Test("Nur ein Raumumriss ist Pflicht")
    func outlineRequired() {
        #expect(RoomValidation.issues([]) == [.missingOutline])
        #expect(RoomValidation.isValid([Self.outline]))
        let second = RoomShape(kind: .outline, points: Self.rect(20, 0, 2, 2))
        #expect(RoomValidation.issues([Self.outline, second]) == [.multipleOutlines([Self.outline.id, second.id])])
        let open = RoomShape(kind: .outline, points: [Self.p(0, 0), Self.p(4, 0), Self.p(4, 4)])
        #expect(RoomValidation.issues([open]) == [.incomplete(open.id)])
    }

    @Test("Offene und sich selbst schneidende Tische")
    func tableForm() {
        let open = RoomShape(kind: .table, points: [Self.p(1, 1), Self.p(3, 1), Self.p(3, 3)])
        let loop = RoomShape(kind: .desk, points: [Self.p(1, 1), Self.p(3, 3), Self.p(3, 1), Self.p(1, 3), Self.p(1, 1)])
        #expect(RoomValidation.issues([Self.outline, open, loop]) == [.incomplete(open.id), .selfIntersecting(loop.id)])
    }

    @Test("Innerhalb des Umrisses; auf dem Umriss ist erlaubt (Tafel)")
    func insideOutline() {
        let board = RoomShape(kind: .board, points: [Self.p(2, 0), Self.p(8, 0)])
        let table = RoomShape(kind: .table, points: Self.rect(0, 6, 2, 2))
        let outside = RoomShape(kind: .table, points: Self.rect(9, 1, 2, 2))
        #expect(RoomValidation.issues([Self.outline, board, table, outside]) == [.outsideRoom(outside.id)])
    }

    @Test("Konkaver Raum: Linie zwischen zwei Randpunkten quer durch die Aussparung")
    func concaveOutline() {
        let lRoom = RoomShape(
            kind: .outline,
            points: [Self.p(0, 0), Self.p(4, 0), Self.p(4, 2), Self.p(2, 2), Self.p(2, 4), Self.p(0, 4), Self.p(0, 0)]
        )
        let board = RoomShape(kind: .board, points: [Self.p(4, 1), Self.p(1, 4)])
        #expect(RoomValidation.issues([lRoom, board]) == [.outsideRoom(board.id)])
    }

    @Test("Tür und Fenster nur auf dem Umriss, auch über eine Ecke hinweg")
    func doorsAndWindows() {
        let door = RoomShape(kind: .door, points: [Self.p(0, 6), Self.p(0, 8), Self.p(1, 8)])
        let window = RoomShape(kind: .window, points: [Self.p(3, 0), Self.p(7, 0)])
        let floating = RoomShape(kind: .window, points: [Self.p(3, 1), Self.p(7, 1)])
        #expect(RoomValidation.issues([Self.outline, door, window, floating]) == [.notOnOutline(floating.id)])
    }

    @Test("Angrenzende Tische mit gemeinsamer Kante, Ecke oder T-Stoß sind erlaubt")
    func adjacency() {
        let first = RoomShape(kind: .table, points: Self.rect(1, 1, 2, 2))
        let edge = RoomShape(kind: .table, points: Self.rect(3, 1, 2, 2))
        let corner = RoomShape(kind: .table, points: Self.rect(5, 3, 2, 2))
        let tee = RoomShape(kind: .desk, points: Self.rect(2, 3, 2, 2))
        #expect(RoomValidation.isValid([Self.outline, first, edge, corner, tee]))
    }

    @Test("Überlappungen: Tische, gleiche Fläche, enthalten, Linie durch Tisch, Linien")
    func overlaps() {
        let table = RoomShape(kind: .table, points: Self.rect(2, 2, 4, 4))
        let crossing = RoomShape(kind: .table, points: Self.rect(4, 4, 4, 2))
        let same = RoomShape(kind: .desk, points: Self.rect(2, 2, 4, 4))
        let inner = RoomShape(kind: .table, points: Self.rect(3, 3, 1, 1))
        for other in [crossing, same, inner] {
            #expect(RoomValidation.issues([Self.outline, table, other]) == [.overlap(table.id, other.id)])
        }
        let board = RoomShape(kind: .board, points: [Self.p(1, 4), Self.p(7, 4)])
        #expect(RoomValidation.issues([Self.outline, table, board]) == [.overlap(table.id, board.id)])
        // Tafel an der Tischkante entlang ist erlaubt.
        let alongEdge = RoomShape(kind: .board, points: [Self.p(2, 2), Self.p(6, 2)])
        #expect(RoomValidation.isValid([Self.outline, table, alongEdge]))

        let door = RoomShape(kind: .door, points: [Self.p(0, 1), Self.p(0, 3)])
        let window = RoomShape(kind: .window, points: [Self.p(0, 2), Self.p(0, 5)])
        let touching = RoomShape(kind: .window, points: [Self.p(0, 3), Self.p(0, 5)])
        #expect(RoomValidation.issues([Self.outline, door, window]) == [.overlap(door.id, window.id)])
        #expect(RoomValidation.isValid([Self.outline, door, touching]))
    }

    // MARK: Modell

    @Test("Room speichert Elemente in Zeichenreihenfolge und zählt Tische als Plätze")
    func model() throws {
        let container = try ModelContainer(
            for: Room.self, RoomElement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let room = Room(name: "R 204", subtitle: "Physikraum", category: .specialist, assignments: ["Physik"])
        context.insert(room)
        room.elements = [
            RoomElement(kind: .table, points: Self.rect(1, 1, 1, 1), order: 2),
            RoomElement(kind: .outline, points: Self.rect(0, 0, 4, 4), order: 0),
            RoomElement(kind: .table, points: Self.rect(2, 1, 1, 1), order: 1),
        ]
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Room>()).first)
        #expect(fetched.category == .specialist)
        #expect(fetched.seatCount == 2)
        #expect(fetched.shapes.map(\.kind) == [.outline, .table, .table])
        #expect(RoomValidation.isValid(fetched.shapes))

        context.delete(fetched)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<RoomElement>()) == 0)
    }
}
