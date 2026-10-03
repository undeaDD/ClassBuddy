// Geometrie-Notation (Strecke a–b, Punkt p, Parameter t) ist kürzer und lesbarer als lange Namen.
// swiftlint:disable identifier_name

import CoreGraphics
import Foundation

/// Reine Geometrie auf dem Punktraster: Einrasten, Schnitt, Punkt-in-Polygon, Teilen, Normalisieren.
/// Orientierungstests rechnen exakt mit ganzen Zahlen; nur Teilstrecken-Mittelpunkte brauchen `Double`.
nonisolated enum RoomGeometry {
    typealias Vector = SIMD2<Double>

    /// Lage eines Punktes zu einer geschlossenen Fläche.
    enum Location {
        case inside, boundary, outside
    }

    private static let epsilon = 1e-9

    // MARK: Einrasten

    /// Nächster Rasterpunkt zu einer Position (in Punkten, Raster-Ursprung bei 0/0).
    static func snap(_ point: CGPoint, spacing: CGFloat) -> GridPoint {
        GridPoint(Int((point.x / spacing).rounded()), Int((point.y / spacing).rounded()))
    }

    static func position(of point: GridPoint, spacing: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(point.x) * spacing, y: CGFloat(point.y) * spacing)
    }

    // MARK: Grundlagen

    /// Kreuzprodukt (a − o) × (b − o): > 0 links, < 0 rechts, 0 kollinear.
    static func cross(_ o: GridPoint, _ a: GridPoint, _ b: GridPoint) -> Int {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    /// Strecken eines Linienzugs.
    static func segments(_ points: [GridPoint]) -> [(GridPoint, GridPoint)] {
        zip(points, points.dropFirst()).map { ($0, $1) }
    }

    /// Doppelte vorzeichenbehaftete Fläche eines geschlossenen Linienzugs (Shoelace).
    static func doubleArea(_ ring: [GridPoint]) -> Int {
        segments(ring).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }
    }

    /// `p` liegt auf der Strecke a–b (Endpunkte eingeschlossen) – exakt.
    static func isOnSegment(_ p: GridPoint, _ a: GridPoint, _ b: GridPoint) -> Bool {
        cross(a, b, p) == 0
            && min(a.x, b.x) <= p.x && p.x <= max(a.x, b.x)
            && min(a.y, b.y) <= p.y && p.y <= max(a.y, b.y)
    }

    /// Geschlossene Strecken berühren oder schneiden sich (auch an Endpunkten oder kollinear).
    static func intersects(_ a: GridPoint, _ b: GridPoint, _ c: GridPoint, _ d: GridPoint) -> Bool {
        let d1 = cross(c, d, a).signum(), d2 = cross(c, d, b).signum()
        let d3 = cross(a, b, c).signum(), d4 = cross(a, b, d).signum()
        if d1 * d2 < 0 && d3 * d4 < 0 { return true }
        return isOnSegment(a, c, d) || isOnSegment(b, c, d) || isOnSegment(c, a, b) || isOnSegment(d, a, b)
    }

    /// Echte Kreuzung im Inneren beider Strecken (kein Berühren, kein kollineares Überlappen).
    static func crossesProperly(_ a: GridPoint, _ b: GridPoint, _ c: GridPoint, _ d: GridPoint) -> Bool {
        cross(c, d, a).signum() * cross(c, d, b).signum() < 0
            && cross(a, b, c).signum() * cross(a, b, d).signum() < 0
    }

    static func vector(_ p: GridPoint) -> Vector { Vector(Double(p.x), Double(p.y)) }

    private static func isOnSegment(_ p: Vector, _ a: GridPoint, _ b: GridPoint) -> Bool {
        let a = vector(a), b = vector(b)
        let ab = b - a, ap = p - a
        let length = (ab * ab).sum().squareRoot()
        guard length > 0 else { return ((p - a) * (p - a)).sum() < epsilon }
        let crossValue = ab.x * ap.y - ab.y * ap.x
        let dot = (ab * ap).sum()
        return abs(crossValue) / length < epsilon && dot >= -epsilon && dot <= length * length + epsilon
    }

    /// Kleinster Abstand eines Punktes zu einem Linienzug (Radierer).
    static func distance(from p: Vector, to points: [GridPoint]) -> Double {
        if points.count == 1, let only = points.first { return ((p - vector(only)) * (p - vector(only))).sum().squareRoot() }
        return segments(points).map { a, b in
            let a = vector(a), b = vector(b)
            let ab = b - a
            let lengthSquared = (ab * ab).sum()
            let t = lengthSquared > 0 ? min(max(((p - a) * ab).sum() / lengthSquared, 0), 1) : 0
            let closest = a + ab * t
            return ((p - closest) * (p - closest)).sum().squareRoot()
        }.min() ?? .infinity
    }

    // MARK: Punkt in Polygon

    /// Lage eines Punktes zu einem geschlossenen Linienzug (Rand zählt als eigene Lage).
    static func locate(_ p: Vector, in ring: [GridPoint]) -> Location {
        let edges = segments(ring)
        if edges.contains(where: { isOnSegment(p, $0.0, $0.1) }) { return .boundary }
        var inside = false
        for (a, b) in edges {
            let a = vector(a), b = vector(b)
            if (a.y > p.y) != (b.y > p.y) {
                let x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if p.x < x { inside.toggle() }
            }
        }
        return inside ? .inside : .outside
    }

    static func locate(_ p: GridPoint, in ring: [GridPoint]) -> Location {
        locate(vector(p), in: ring)
    }

    /// Mittelpunkte der Teilstücke einer Strecke, zerschnitten an allen Berührungen mit `edges`.
    /// Jedes Teilstück liegt damit ganz innen, ganz außen oder ganz auf dem Rand.
    static func pieceMidpoints(_ a: GridPoint, _ b: GridPoint, cutBy edges: [(GridPoint, GridPoint)]) -> [Vector] {
        let direction = b - a
        let lengthSquared = Double(direction.x * direction.x + direction.y * direction.y)
        guard lengthSquared > 0 else { return [] }
        func parameter(_ p: GridPoint) -> Double {
            Double((p.x - a.x) * direction.x + (p.y - a.y) * direction.y) / lengthSquared
        }
        var cuts: [Double] = [0, 1]
        for (c, d) in edges {
            let edge = d - c
            let denominator = direction.x * edge.y - direction.y * edge.x
            if denominator == 0 {
                guard cross(a, b, c) == 0 else { continue }
                cuts += [parameter(c), parameter(d)].filter { $0 > 0 && $0 < 1 }
            } else {
                let ac = c - a
                let t = Double(ac.x * edge.y - ac.y * edge.x) / Double(denominator)
                let u = Double(ac.x * direction.y - ac.y * direction.x) / Double(denominator)
                if t > 0, t < 1, u >= 0, u <= 1 { cuts.append(t) }
            }
        }
        let sorted = cuts.sorted()
        let start = vector(a), delta = vector(b) - start
        return zip(sorted, sorted.dropFirst())
            .filter { $1 - $0 > epsilon }
            .map { start + delta * (($0 + $1) / 2) }
    }

    /// Lagen aller Teilstücke eines Linienzugs relativ zu einer Fläche.
    static func pieceLocations(of points: [GridPoint], relativeTo ring: [GridPoint]) -> [Location] {
        let edges = segments(ring)
        return segments(points).flatMap { a, b in
            pieceMidpoints(a, b, cutBy: edges).map { locate($0, in: ring) }
        }
    }

    // MARK: Formen

    /// Einfache geschlossene Fläche: mindestens drei Ecken, keine Selbstberührung, Fläche > 0.
    static func isSimplePolygon(_ ring: [GridPoint]) -> Bool {
        guard ring.count >= 4, ring.first == ring.last else { return false }
        let vertices = ring.dropLast()
        guard Set(vertices).count == vertices.count, doubleArea(ring) != 0 else { return false }
        let edges = segments(ring)
        for i in edges.indices {
            let (a, b) = edges[i]
            // Benachbarte Kante darf nicht zurücklaufen.
            let (_, c) = edges[(i + 1) % edges.count]
            if cross(a, b, c) == 0, ((b - a).x * (c - b).x + (b - a).y * (c - b).y) < 0 { return false }
            for j in edges.indices where j >= i + 2 && !(i == 0 && j == edges.count - 1) {
                if intersects(a, b, edges[j].0, edges[j].1) { return false }
            }
        }
        return true
    }

    /// Offener Linienzug ohne Strecken der Länge 0.
    static func isValidLine(_ points: [GridPoint]) -> Bool {
        points.count >= 2 && !segments(points).contains { $0.0 == $0.1 }
    }

    /// Linienzug kreuzt oder überdeckt sich selbst nicht (Strecken teilen nur ihren gemeinsamen Endpunkt).
    static func isSimplePath(_ points: [GridPoint]) -> Bool {
        guard isValidLine(points) else { return false }
        let edges = segments(points)
        for i in edges.indices {
            let (a, b) = edges[i]
            if i + 1 < edges.count {
                let c = edges[i + 1].1
                if cross(a, b, c) == 0, ((b - a).x * (c - b).x + (b - a).y * (c - b).y) < 0 { return false }
            }
            for j in edges.indices where j > i + 1 && intersects(a, b, edges[j].0, edges[j].1) {
                return false
            }
        }
        return true
    }

    /// Flächenschwerpunkt eines geschlossenen Linienzugs (z. B. für Beschriftungen auf Tischen).
    static func centroid(of ring: [GridPoint]) -> Vector? {
        let area = Double(doubleArea(ring))
        guard area != 0 else { return nil }
        var sum = Vector(0, 0)
        for (a, b) in segments(ring) {
            let factor = Double(a.x * b.y - b.x * a.y)
            sum += (vector(a) + vector(b)) * factor
        }
        return sum / (3 * area)
    }

    // MARK: Grenzen und Normalisieren

    /// Kleinste und größte Koordinate aller Punkte.
    static func bounds(of points: [GridPoint]) -> (min: GridPoint, max: GridPoint)? {
        guard let first = points.first else { return nil }
        return points.reduce((first, first)) { result, p in
            (GridPoint(min(result.0.x, p.x), min(result.0.y, p.y)), GridPoint(max(result.1.x, p.x), max(result.1.y, p.y)))
        }
    }

    /// Raumgrenzen = Grenzen des Raumumrisses (ohne Umriss: alle Punkte).
    static func roomBounds(_ shapes: [RoomShape]) -> (min: GridPoint, max: GridPoint)? {
        let outline = shapes.first { $0.kind == .outline }?.points ?? []
        return bounds(of: outline.isEmpty ? shapes.flatMap(\.points) : outline)
    }

    /// Verschiebt alle Punkte so, dass die linke obere Ecke des Raums bei 0/0 liegt.
    static func normalized(_ shapes: [RoomShape]) -> [RoomShape] {
        guard let origin = roomBounds(shapes)?.min, origin != .zero else { return shapes }
        return shapes.map { shape in
            var shape = shape
            shape.points = shape.points.map { $0 - origin }
            return shape
        }
    }

    // MARK: Teilen

    /// Teilt eine Fläche entlang eines Linienzugs von Rand zu Rand, der sonst nur innen verläuft.
    /// Ergebnis: zwei angrenzende geschlossene Flächen, oder `nil`, wenn der Linienzug keine gültige Trennlinie ist.
    static func split(_ ring: [GridPoint], along path: [GridPoint]) -> (first: [GridPoint], second: [GridPoint])? {
        guard isSimplePolygon(ring), isSimplePath(path),
              let start = path.first, let end = path.last, start != end,
              locate(start, in: ring) == .boundary, locate(end, in: ring) == .boundary,
              path.dropFirst().dropLast().allSatisfy({ locate($0, in: ring) == .inside }),
              pieceLocations(of: path, relativeTo: ring).allSatisfy({ $0 == .inside })
        else { return nil }

        var vertices = Array(ring.dropLast())
        guard let startIndex = insert(start, into: &vertices) else { return nil }
        guard let endIndex = insert(end, into: &vertices) else { return nil }
        // Einfügen von `end` vor `start` verschiebt dessen Index.
        let fromIndex = vertices.firstIndex(of: start) ?? startIndex

        func arc(from: Int, to: Int) -> [GridPoint] {
            var result = [vertices[from]]
            var index = from
            while index != to {
                index = (index + 1) % vertices.count
                result.append(vertices[index])
            }
            return result
        }
        let first = arc(from: fromIndex, to: endIndex) + path.reversed().dropFirst()
        let second = arc(from: endIndex, to: fromIndex) + path.dropFirst()
        guard isSimplePolygon(first), isSimplePolygon(second) else { return nil }
        return (first, second)
    }

    /// Fügt einen Randpunkt als Ecke ein (falls noch keine) und liefert seinen Index.
    private static func insert(_ point: GridPoint, into vertices: inout [GridPoint]) -> Int? {
        if let index = vertices.firstIndex(of: point) { return index }
        for index in vertices.indices {
            let next = vertices[(index + 1) % vertices.count]
            if isOnSegment(point, vertices[index], next) {
                vertices.insert(point, at: index + 1)
                return index + 1
            }
        }
        return nil
    }
}

// swiftlint:enable identifier_name
