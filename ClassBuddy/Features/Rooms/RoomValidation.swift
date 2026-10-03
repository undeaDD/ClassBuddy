// Geometrie-Notation (Strecke a–b, Punkt p, Parameter t) ist kürzer und lesbarer als lange Namen.
// swiftlint:disable identifier_name

import Foundation

/// Grund, warum ein Raum (noch) nicht gespeichert werden kann.
nonisolated enum RoomIssue: Hashable, Sendable {
    case missingOutline
    case multipleOutlines([UUID])
    /// Fläche nicht geschlossen bzw. Linie ohne Länge.
    case incomplete(UUID)
    case selfIntersecting(UUID)
    case outsideRoom(UUID)
    case notOnOutline(UUID)
    case overlap(UUID, UUID)

    /// Betroffene Elemente (zum Markieren im Editor).
    var elementIDs: [UUID] {
        switch self {
        case .missingOutline: []
        case .multipleOutlines(let ids): ids
        case .incomplete(let id), .selfIntersecting(let id), .outsideRoom(let id), .notOnOutline(let id): [id]
        case .overlap(let first, let second): [first, second]
        }
    }

    var message: String {
        switch self {
        case .missingOutline: loc("Zeichnen Sie einen geschlossenen Raumumriss.")
        case .multipleOutlines: loc("Ein Raum hat genau einen Raumumriss.")
        case .incomplete: loc("Flächen müssen geschlossen sein.")
        case .selfIntersecting: loc("Eine Fläche überschneidet sich selbst.")
        case .outsideRoom: loc("Elemente müssen innerhalb des Raumumrisses liegen.")
        case .notOnOutline: loc("Türen und Fenster liegen auf dem Raumumriss.")
        case .overlap: loc("Elemente dürfen sich nicht überschneiden.")
        }
    }
}

/// Gültigkeit eines Raums: Speichern nur ohne `issues`.
nonisolated enum RoomValidation {
    typealias Location = RoomGeometry.Location

    static func isValid(_ shapes: [RoomShape]) -> Bool { issues(shapes).isEmpty }

    static func issues(_ shapes: [RoomShape]) -> [RoomIssue] {
        var issues: [RoomIssue] = []
        var valid: [RoomShape] = []
        for shape in shapes {
            if let issue = formIssue(shape) { issues.append(issue) } else { valid.append(shape) }
        }

        let outlines = shapes.filter { $0.kind == .outline }
        guard outlines.count == 1, let outline = outlines.first else {
            issues.append(outlines.isEmpty ? .missingOutline : .multipleOutlines(outlines.map(\.id)))
            return issues
        }
        guard valid.contains(outline) else { return issues }

        let elements = valid.filter { $0.kind != .outline }
        for element in elements {
            let locations = RoomGeometry.pieceLocations(of: element.points, relativeTo: outline.points)
            if element.kind.isOnOutline {
                if locations.contains(where: { $0 != .boundary }) { issues.append(.notOnOutline(element.id)) }
            } else if locations.contains(.outside) {
                issues.append(.outsideRoom(element.id))
            }
        }

        for (index, first) in elements.enumerated() {
            for second in elements.dropFirst(index + 1) where overlaps(first, second) {
                issues.append(.overlap(first.id, second.id))
            }
        }
        return issues
    }

    /// Fehler der Form selbst (ohne Bezug zu anderen Elementen).
    private static func formIssue(_ shape: RoomShape) -> RoomIssue? {
        if shape.kind.isArea {
            guard shape.isClosed else { return .incomplete(shape.id) }
            return RoomGeometry.isSimplePolygon(shape.points) ? nil : .selfIntersecting(shape.id)
        }
        return RoomGeometry.isValidLine(shape.points) ? nil : .incomplete(shape.id)
    }

    /// Überlappung zweier Elemente; Angrenzen über gemeinsame Punkte und Kanten ist erlaubt.
    static func overlaps(_ first: RoomShape, _ second: RoomShape) -> Bool {
        switch (first.kind.isArea, second.kind.isArea) {
        case (true, true):
            let firstInSecond = RoomGeometry.pieceLocations(of: first.points, relativeTo: second.points)
            let secondInFirst = RoomGeometry.pieceLocations(of: second.points, relativeTo: first.points)
            if firstInSecond.contains(.inside) || secondInFirst.contains(.inside) { return true }
            // Gleiche Fläche: Ränder decken sich vollständig.
            return firstInSecond.allSatisfy { $0 == .boundary }
        case (false, true):
            return RoomGeometry.pieceLocations(of: first.points, relativeTo: second.points).contains(.inside)
        case (true, false):
            return overlaps(second, first)
        case (false, false):
            return linesOverlap(first.points, second.points)
        }
    }

    /// Linien kreuzen sich oder verlaufen ein Stück weit aufeinander; Berühren an einem Punkt ist erlaubt.
    private static func linesOverlap(_ first: [GridPoint], _ second: [GridPoint]) -> Bool {
        let firstSegments = RoomGeometry.segments(first), secondSegments = RoomGeometry.segments(second)
        for (a, b) in firstSegments {
            for (c, d) in secondSegments {
                if RoomGeometry.crossesProperly(a, b, c, d) { return true }
                // Kollinear mit gemeinsamem Stück positiver Länge.
                if RoomGeometry.cross(a, b, c) == 0, RoomGeometry.cross(a, b, d) == 0 {
                    let pieces = RoomGeometry.pieceMidpoints(a, b, cutBy: [(c, d)])
                    if pieces.contains(where: { isOnSegment($0, c, d) }) { return true }
                }
            }
        }
        return false
    }

    private static func isOnSegment(_ p: RoomGeometry.Vector, _ c: GridPoint, _ d: GridPoint) -> Bool {
        RoomGeometry.locate(p, in: [c, d]) == .boundary
    }
}

// swiftlint:enable identifier_name
