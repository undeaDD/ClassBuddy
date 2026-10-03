import Foundation
import SwiftData

/// Demo-Klassenzimmer beim ersten App-Start: ein normaler, editierbarer Raum ohne Sitzplan.
/// Wird es entfernt, kommt es nicht wieder.
enum RoomDemo {
    static let storageKey = "rooms.demoCreated"

    static func createIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        upgradeUnchangedDemo(in: context, defaults: defaults)
        guard !defaults.bool(forKey: storageKey) else { return }
        defaults.set(true, forKey: storageKey)
        // Wer schon Räume hat (z. B. per Import), braucht kein Beispiel.
        guard (try? context.fetchCount(FetchDescriptor<Room>())) == 0 else { return }
        let room = Room(name: loc("Demo-Klassenzimmer"), subtitle: loc("Beispielraum, frei bearbeitbar"), category: .classroom)
        context.insert(room)
        room.replaceElements(with: shapes, in: context)
        try? context.save()
    }

    /// 18 × 19 Raster: Tafel vorne, Pult links vorne, Tür rechts auf Höhe des Pults, Fenster links,
    /// 12 Tische in Zweiergruppen mit Abstand zwischen den Reihen und Platz bis zur Rückwand.
    static var shapes: [RoomShape] {
        var shapes = [
            RoomShape(kind: .outline, points: rect(0, 0, 18, 19)),
            RoomShape(kind: .board, points: [GridPoint(5, 0), GridPoint(13, 0)]),
            RoomShape(kind: .desk, points: rect(2, 2, 4, 2)),
            RoomShape(kind: .window, points: [GridPoint(0, 5), GridPoint(0, 9)]),
            RoomShape(kind: .window, points: [GridPoint(0, 11), GridPoint(0, 15)]),
            RoomShape(kind: .door, points: [GridPoint(18, 2), GridPoint(18, 4)]),
        ]
        for row in [6, 10, 14] {
            for column in [2, 5, 10, 13] {
                shapes.append(RoomShape(kind: .table, points: rect(column, row, 3, 2)))
            }
        }
        return shapes
    }

    // MARK: Erste Version

    private static let upgradeKey = "rooms.demoUpgraded.v2"

    /// Ein unverändertes Demo-Klassenzimmer der ersten Version bekommt den neuen Grundriss.
    private static func upgradeUnchangedDemo(in context: ModelContext, defaults: UserDefaults) {
        guard !defaults.bool(forKey: upgradeKey) else { return }
        defaults.set(true, forKey: upgradeKey)
        let old = geometry(of: firstVersionShapes)
        guard let rooms = try? context.fetch(FetchDescriptor<Room>()),
              let demo = rooms.first(where: { geometry(of: $0.shapes) == old })
        else { return }
        demo.replaceElements(with: shapes, in: context)
        try? context.save()
    }

    /// Art und Punkte ohne IDs, unabhängig von der Reihenfolge.
    private static func geometry(of shapes: [RoomShape]) -> [String] {
        shapes.map { "\($0.kind.rawValue):\($0.points.map { "\($0.x),\($0.y)" }.joined(separator: ";"))" }.sorted()
    }

    private static var firstVersionShapes: [RoomShape] {
        var shapes = [
            RoomShape(kind: .outline, points: rect(0, 0, 18, 14)),
            RoomShape(kind: .board, points: [GridPoint(5, 0), GridPoint(13, 0)]),
            RoomShape(kind: .desk, points: rect(7, 2, 4, 2)),
            RoomShape(kind: .window, points: [GridPoint(0, 3), GridPoint(0, 6)]),
            RoomShape(kind: .window, points: [GridPoint(0, 8), GridPoint(0, 11)]),
            RoomShape(kind: .door, points: [GridPoint(18, 10), GridPoint(18, 12)]),
        ]
        for row in [6, 9, 12] {
            for column in [2, 5, 10, 13] {
                shapes.append(RoomShape(kind: .table, points: rect(column, row, 3, 2)))
            }
        }
        return shapes
    }

    private static func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> [GridPoint] {
        [GridPoint(x, y), GridPoint(x + width, y), GridPoint(x + width, y + height), GridPoint(x, y + height), GridPoint(x, y)]
    }
}
