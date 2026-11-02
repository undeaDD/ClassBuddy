import SwiftUI

/// Abbildung Raster → Bildschirm: Grundriss eingepasst, darüber Zoom und Verschiebung.
struct SeatingPlanTransform {
    let origin: CGPoint
    let scale: CGFloat

    init?(shapes: [RoomShape], size: CGSize, padding: CGFloat, zoom: CGFloat = 1, pan: CGSize = .zero) {
        guard let fit = RoomDrawing.fitting(shapes, in: size, padding: padding) else { return nil }
        let base = fit.map(.zero)
        origin = CGPoint(x: base.x * zoom + pan.width, y: base.y * zoom + pan.height)
        scale = fit.scale * zoom
    }

    func point(_ point: GridPoint) -> CGPoint {
        self.point(RoomGeometry.vector(point))
    }

    func point(_ vector: RoomGeometry.Vector) -> CGPoint {
        CGPoint(x: origin.x + vector.x * scale, y: origin.y + vector.y * scale)
    }

    func grid(_ location: CGPoint) -> RoomGeometry.Vector {
        RoomGeometry.Vector((location.x - origin.x) / scale, (location.y - origin.y) / scale)
    }

    /// Tisch an dieser Stelle (Rand zählt dazu).
    func table(at location: CGPoint, in shapes: [RoomShape]) -> UUID? {
        let vector = grid(location)
        return shapes.first { $0.kind == .table && RoomGeometry.locate(vector, in: $0.points) != .outside }?.id
    }
}

/// Grundriss mit Schülern auf den Tischen (Foto/Initialen, Geschlecht, voller Name)
/// und der Lehrkraft am Lehrerpult (falls vorhanden). Ohne Gesten – gemeinsam für die Ansicht und das PDF.
struct SeatingPlanFloor: View {
    @Environment(\.appAccent) private var accent
    let shapes: [RoomShape]
    let occupants: [UUID: Student]
    /// Lehrkraft am ersten Lehrerpult (nicht verschieb- oder bearbeitbar); `nil` = keine.
    var teacher: TeacherProfile?
    var selected: UUID?
    /// Gestrichelt umrandete Tische (lange ohne Beobachtung).
    var dashed: Set<UUID> = []
    /// Abgeblendete Schüler (abwesend).
    var dimmed: Set<UUID> = []
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    var padding: CGFloat = 24
    /// Fläche hinter dem Grundriss (für den ausgeschnittenen Geschlechts-Kreis).
    var background = Color(.systemGroupedBackground)
    /// Raumfläche einfärben; im PDF aus (Tische und Pult bleiben gefüllt).
    var fillsOutline = true
    /// Antippen, Menü und Ziehen der Schüler; `nil` = nur Anzeige (PDF, Privatsphäre-Modus).
    var actions: SeatActions?

    var body: some View {
        GeometryReader { proxy in
            if let transform = SeatingPlanTransform(shapes: shapes, size: proxy.size, padding: padding, zoom: zoom, pan: pan) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        draw(in: context, transform: transform)
                    }
                    if let teacher, let desk = deskPlacement(transform: transform) {
                        SeatLabel(
                            initials: teacher.initials, photo: teacher.photo, gender: teacher.gender,
                            name: teacher.fullName.isEmpty ? loc("Lehrkraft") : teacher.fullName, fit: desk.fit
                        )
                        .allowsHitTesting(false)
                        .environment(\.avatarCutout, cutout(on: .desk))
                        .position(desk.center)
                    }
                    ForEach(seats(transform: transform), id: \.table) { seat in
                        seatView(seat)
                            .environment(\.avatarCutout, cutout(on: .table))
                            .position(seat.center)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Hintergrund unter dem Avatar: Fläche plus halbtransparente Füllung des Tisches bzw. Pults.
    private func cutout(on kind: RoomElementKind) -> [Color] {
        [background, kind.color.opacity(kind.fillOpacity)]
    }

    private func draw(in context: GraphicsContext, transform: SeatingPlanTransform) {
        let lineWidth = min(max(transform.scale * 0.08, 1.5), 4)
        RoomDrawing.draw(shapes, in: context, lineWidth: lineWidth, fillsOutline: fillsOutline, map: transform.point)
        // Gestrichelt: durchgehende Linie mit dem Hintergrund überdecken, dann orange Striche darüber.
        for shape in shapes where dashed.contains(shape.id) {
            let path = RoomDrawing.path(for: shape, map: transform.point)
            let width = lineWidth * 1.4
            context.stroke(path, with: .color(background), style: StrokeStyle(lineWidth: width + 1, lineJoin: .round))
            let dash = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [width * 2.5, width * 2])
            context.stroke(path, with: .color(.orange), style: dash)
        }
        guard let selected, let shape = shapes.first(where: { $0.id == selected }) else { return }
        let path = RoomDrawing.path(for: shape, map: transform.point)
        context.fill(path, with: .color(accent.opacity(0.3)))
        context.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: lineWidth * 1.5, lineJoin: .round))
    }

    private struct Seat {
        let table: UUID
        let student: Student
        let center: CGPoint
        let fit: SeatFit
    }

    /// Alle Schüler gleich groß: Kreis nach dem engsten Tisch des Raums (auch freie Tische, damit sich die Größe
    /// beim Umsetzen nicht ändert). Nur die Breite für den Namen gilt je Tisch.
    private func seats(transform: SeatingPlanTransform) -> [Seat] {
        let tables = shapes.filter { $0.kind == .table }
        let space = tables.compactMap { Self.layout(of: $0)?.space }.min()
        return tables.compactMap { shape in
            guard let student = occupants[shape.id], let space, let layout = Self.layout(of: shape) else { return nil }
            let fit = SeatFit(space: space * transform.scale, width: layout.width * transform.scale)
            return Seat(table: shape.id, student: student, center: transform.point(layout.center), fit: fit)
        }
    }

    private func deskPlacement(transform: SeatingPlanTransform) -> (center: CGPoint, fit: SeatFit)? {
        guard let desk = shapes.first(where: { $0.kind == .desk }), let layout = Self.layout(of: desk) else { return nil }
        return (transform.point(layout.center), SeatFit(space: layout.space * transform.scale, width: layout.width * transform.scale))
    }

    /// Platz einer Fläche in Rastereinheiten. Anders als das umschließende Rechteck bleibt er bei schrägen Tischen
    /// so klein, wie der Tisch wirklich ist.
    private struct Layout {
        /// Schwerpunkt der Fläche.
        let center: RoomGeometry.Vector
        /// Doppelter Abstand vom Schwerpunkt zum nächsten Rand (Platz für den Kreis; bei Rechtecken die kürzere Seite).
        let space: Double
        /// Breite der Fläche auf Höhe des Schwerpunkts (Platz für den Namen).
        let width: Double
    }

    private static func layout(of shape: RoomShape) -> Layout? {
        guard let centroid = RoomGeometry.centroid(of: shape.points) else { return nil }
        let space = 2 * RoomGeometry.distance(from: centroid, to: shape.points)
        let width = RoomGeometry.horizontalWidth(at: centroid, in: shape.points) ?? space
        return Layout(center: centroid, space: space, width: width)
    }

    @ViewBuilder
    private func seatView(_ seat: Seat) -> some View {
        let label = SeatLabel(student: seat.student, fit: seat.fit)
            .opacity(dimmed.contains(seat.table) ? 0.35 : 1)
        if let actions {
            label
                .contentShape(.rect)
                .onTapGesture { actions.open(seat.student) }
                // Langes Drücken: Menü; gedrückt halten und ziehen: auf einen anderen Tisch setzen.
                .draggable(seat.student.id.uuidString) {
                    StudentAvatar(student: seat.student, size: 48)
                }
                .contextMenu {
                    Button("Schüler bearbeiten", icon: .editPencil) { actions.edit(seat.student) }
                    Button("Platz freigeben", destructiveIcon: .userXmark) { actions.clear(seat.table) }
                }
        } else {
            label
        }
    }
}

/// Aktionen auf besetzten Tischen.
struct SeatActions {
    /// Antippen → Schnell-Leiste bzw. Akte des Schülers.
    let open: (Student) -> Void
    /// Langes Drücken → „Schüler bearbeiten“.
    let edit: (Student) -> Void
    /// Langes Drücken → „Platz freigeben“ (Tisch-ID).
    let clear: (UUID) -> Void
}

/// Platz für eine Person auf dem Bildschirm: `space` bestimmt Kreis und Schrift, `width` die Breite des Namens.
private struct SeatFit {
    let space: CGFloat
    let width: CGFloat
}

/// Person auf einem Tisch bzw. Pult: Kreis wie in der Schülerliste, darunter der volle Name.
private struct SeatLabel: View {
    let initials: String
    let photo: Data?
    let gender: Gender?
    let name: String
    let fit: SeatFit

    init(student: Student, fit: SeatFit) {
        self.init(initials: student.initials, photo: student.photo, gender: student.gender, name: student.fullName, fit: fit)
    }

    init(initials: String, photo: Data?, gender: Gender?, name: String, fit: SeatFit) {
        self.initials = initials
        self.photo = photo
        self.gender = gender
        self.name = name
        self.fit = fit
    }

    var body: some View {
        let diameter = min(max(fit.space * 0.5, 14), 72)
        VStack(spacing: diameter * 0.1) {
            StudentAvatar(initials: initials, photo: photo, gender: gender, size: diameter)
            Text(name)
                .font(.system(size: max(diameter * 0.24, 7), weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                // Namen (auch der Lehrkraft) im Privatsphäre-Modus schwärzen.
                .sensitive()
        }
        .frame(width: max(fit.width - 4, diameter * 1.6))
    }
}

extension TeacherProfile {
    var initials: String {
        [firstName.first, lastName.first].compactMap { $0 }.map(String.init).joined()
    }
}

/// Sitzplan mit Gesten: Antippen eines Tisches, Verschieben und Zoomen, Ablegen von Schülern
/// (von einem anderen Tisch oder auf dem iPad aus der Seitenleiste).
struct SeatingPlanCanvas: View {
    let shapes: [RoomShape]
    let occupants: [UUID: Student]
    var teacher: TeacherProfile?
    var selected: UUID?
    var dashed: Set<UUID> = []
    var dimmed: Set<UUID> = []
    var isEditable: Bool
    /// Antippen eines freien Tisches bzw. daneben (`nil`).
    let onTap: (UUID?) -> Void
    let actions: SeatActions
    /// Abgelegter Schüler (ID als Text) auf einem Tisch.
    let onDrop: (UUID, UUID) -> Void

    private static let zoomRange: ClosedRange<CGFloat> = 1...5
    private static let padding: CGFloat = 24

    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var size: CGSize = .zero
    @State private var zoomStart: (zoom: CGFloat, pan: CGSize)?
    @GestureState private var dragTranslation: CGSize = .zero

    private var effectivePan: CGSize {
        CGSize(width: pan.width + dragTranslation.width, height: pan.height + dragTranslation.height)
    }

    var body: some View {
        SeatingPlanFloor(
            shapes: shapes,
            occupants: occupants,
            teacher: teacher,
            selected: selected,
            dashed: dashed,
            dimmed: dimmed,
            zoom: zoom,
            pan: effectivePan,
            padding: Self.padding,
            actions: isEditable ? actions : nil
        )
        .contentShape(.rect)
        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        .onTapGesture { location in
            guard isEditable else { return }
            onTap(transform?.table(at: location, in: shapes))
        }
        .simultaneousGesture(dragGesture)
        .simultaneousGesture(magnifyGesture)
        .dropDestination(for: String.self) { items, location in
            guard isEditable, let studentID = items.first.flatMap(UUID.init(uuidString:)),
                  let table = transform?.table(at: location, in: shapes) else { return false }
            onDrop(studentID, table)
            return true
        }
        .clipped()
    }

    private var transform: SeatingPlanTransform? {
        SeatingPlanTransform(shapes: shapes, size: size, padding: Self.padding, zoom: zoom, pan: pan)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                pan.width += value.translation.width
                pan.height += value.translation.height
            }
    }

    /// Zoom um den Startpunkt der Geste; zurück auf 1 → Grundriss wieder eingepasst.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? (zoom, pan)
                zoomStart = start
                let newZoom = min(max(start.zoom * value.magnification, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
                let factor = newZoom / start.zoom
                let focus = value.startLocation
                pan = CGSize(width: focus.x - (focus.x - start.pan.width) * factor, height: focus.y - (focus.y - start.pan.height) * factor)
                zoom = newZoom
            }
            .onEnded { _ in
                zoomStart = nil
                if zoom < 1.05 {
                    withAnimation(.smooth) {
                        zoom = 1
                        pan = .zero
                    }
                }
            }
    }
}
