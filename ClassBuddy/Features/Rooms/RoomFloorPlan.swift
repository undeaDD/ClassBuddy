import SwiftUI

extension RoomElementKind {
    /// Stiftfarbe (System-Farben, hell und dunkel lesbar).
    var color: Color {
        switch self {
        case .outline: .primary
        case .table: .brown
        case .desk: .orange
        case .board: .green
        case .door: .gray
        case .window: .blue
        }
    }

    /// Zeichenebene: Raumfläche unten, Tür und Fenster ganz oben (gut sichtbar auf dem Umriss).
    var layer: Int {
        switch self {
        case .outline: 0
        case .table, .desk: 1
        case .board: 2
        case .door, .window: 3
        }
    }

    /// Tafel, Tür und Fenster: dicke Linien, damit sie auf dem Umriss gut sichtbar sind.
    var isThickLine: Bool { self == .board || isOnOutline }

    /// Deckkraft der Füllung bei Flächen.
    var fillOpacity: Double {
        self == .outline ? 0.12 : 0.22
    }
}

/// Zeichnet Raumelemente in einen `GraphicsContext` – gemeinsam für Vorschau, Editor, Sitzplan und PDF.
enum RoomDrawing {
    /// - Parameters:
    ///   - map: Rasterpunkt → Position in der Zeichenfläche.
    ///   - invalid: Elemente, die rot markiert werden (Editor).
    ///   - labels: Text mittig auf Tischen (Sitzplan).
    static func draw(
        _ shapes: [RoomShape],
        in context: GraphicsContext,
        lineWidth: CGFloat,
        invalid: Set<UUID> = [],
        labels: [UUID: String] = [:],
        map: (GridPoint) -> CGPoint
    ) {
        for shape in shapes.sorted(by: { $0.kind.layer < $1.kind.layer }) {
            let path = path(for: shape, map: map)
            if shape.kind.isArea, shape.isClosed {
                context.fill(path, with: .color(shape.kind.color.opacity(shape.kind.fillOpacity)))
            }
            let width = shape.kind.isThickLine ? lineWidth * 2.2 : lineWidth
            context.stroke(path, with: .color(shape.kind.color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            if invalid.contains(shape.id) {
                context.stroke(
                    path,
                    with: .color(.red),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [width * 2, width * 2])
                )
            }
        }
        guard !labels.isEmpty else { return }
        // Lineare Abbildung → Bruchteile über die Einheitsvektoren umrechnen.
        let origin = map(.zero), unitX = map(GridPoint(1, 0)), unitY = map(GridPoint(0, 1))
        for shape in shapes where shape.kind == .table {
            guard let label = labels[shape.id], let center = RoomGeometry.centroid(of: shape.points) else { continue }
            let position = CGPoint(
                x: origin.x + (unitX.x - origin.x) * center.x + (unitY.x - origin.x) * center.y,
                y: origin.y + (unitX.y - origin.y) * center.x + (unitY.y - origin.y) * center.y
            )
            context.draw(Text(label).font(.caption2.weight(.medium)).foregroundStyle(.primary), at: position, anchor: .center)
        }
    }

    static func path(for shape: RoomShape, map: (GridPoint) -> CGPoint) -> Path {
        Path { path in
            guard let first = shape.points.first else { return }
            path.move(to: map(first))
            for point in shape.points.dropFirst() { path.addLine(to: map(point)) }
            if shape.isClosed { path.closeSubpath() }
        }
    }

    /// Abbildung, die die Raumgrenzen mittig und seitentreu in `size` einpasst.
    static func fitting(_ shapes: [RoomShape], in size: CGSize, padding: CGFloat) -> (scale: CGFloat, map: (GridPoint) -> CGPoint)? {
        guard let bounds = RoomGeometry.roomBounds(shapes) else { return nil }
        let width = CGFloat(max(bounds.max.x - bounds.min.x, 1))
        let height = CGFloat(max(bounds.max.y - bounds.min.y, 1))
        let scale = max(min((size.width - 2 * padding) / width, (size.height - 2 * padding) / height), 0.1)
        let originX = (size.width - width * scale) / 2
        let originY = (size.height - height * scale) / 2
        return (scale, { point in
            CGPoint(x: originX + CGFloat(point.x - bounds.min.x) * scale, y: originY + CGFloat(point.y - bounds.min.y) * scale)
        })
    }
}

/// Grundriss, eingepasst in den verfügbaren Platz (Karten, Sitzplan, PDF).
struct RoomFloorPlanView: View {
    let shapes: [RoomShape]
    var padding: CGFloat = 8
    var lineWidth: CGFloat = 1.5
    var labels: [UUID: String] = [:]

    var body: some View {
        Canvas { context, size in
            guard let fit = RoomDrawing.fitting(shapes, in: size, padding: padding) else { return }
            RoomDrawing.draw(shapes, in: context, lineWidth: lineWidth, labels: labels, map: fit.map)
        }
        .accessibilityHidden(true)
    }
}
