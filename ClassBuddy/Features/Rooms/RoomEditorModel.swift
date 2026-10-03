import SwiftUI

/// Werkzeug in der Toolbox.
enum RoomTool: Hashable {
    /// Standard: ein Finger verschiebt den Raum, damit nicht versehentlich gezeichnet wird.
    case move
    case pen(RoomElementKind)
    case eraser

    var title: String {
        switch self {
        case .move: loc("Verschieben")
        case .pen(let kind): kind.displayTitle
        case .eraser: loc("Radierer")
        }
    }

    /// Kurzer Name unter dem Icon in der Toolbox.
    var shortTitle: String {
        switch self {
        case .move: loc("Maus")
        case .pen(let kind): kind.shortTitle
        case .eraser: loc("Radierer")
        }
    }

    /// Werkzeug-Icon (PNG-Vorlage aus `Assets.xcassets/RoomTools`, in jedem Icon-Paket gleich).
    var image: Image {
        let name = switch self {
        case .move: "tool-move"
        case .pen(let kind): "tool-\(kind.rawValue)"
        case .eraser: "tool-eraser"
        }
        return Image(ImageResource(name: name, bundle: .main))
    }
}

extension RoomElementKind {
    var shortTitle: String {
        switch self {
        case .outline: loc("Raum")
        case .table: loc("Tisch")
        case .desk: loc("Pult")
        case .board: loc("Tafel")
        case .door: loc("Tür")
        case .window: loc("Fenster")
        }
    }
}

/// Zustand und Logik des Raum-Editors: Zeichnen auf dem Raster, Tische teilen, Radieren,
/// Rückgängig/Wiederholen und Ausschnitt (Verschieben/Zoomen).
@Observable
final class RoomEditorModel {
    /// Abstand der Rasterpunkte bei Zoom 1 (in Punkten).
    static let gridSpacing: CGFloat = 28
    static let zoomRange: ClosedRange<CGFloat> = 0.25...4

    private(set) var shapes: [RoomShape] {
        didSet { issues = RoomValidation.issues(shapes) }
    }
    private(set) var issues: [RoomIssue]
    /// Linienzug, der gerade weitergezeichnet wird (läuft an seinem letzten Punkt weiter).
    private(set) var activeID: UUID?
    /// Trennlinie innerhalb eines Tisches, die noch nicht den Rand erreicht hat.
    private(set) var splitDraft: SplitDraft?
    /// Startpunkt nach einem Antippen ohne laufenden Linienzug (Bedienung ohne Ziehen).
    private(set) var pendingStart: GridPoint?

    var tool: RoomTool = .move {
        didSet {
            if case .pen = oldValue { lastPen = oldValue }
            finishLine()
        }
    }
    private var lastPen: RoomTool = .pen(.outline)

    /// Laufende Ziehbewegung: Vorschau der nächsten Strecke.
    var dragStart: GridPoint?
    var dragEnd: GridPoint?
    /// Pencil-Hover: Vorschau des nächsten Rasterpunkts.
    var hoverPoint: GridPoint?

    // Ausschnitt
    var zoom: CGFloat = 1
    var pan: CGSize = .zero
    var viewSize: CGSize = .zero {
        // Erstes Layout: gespeicherten Raum mit Rand zeigen.
        didSet { if oldValue == .zero, viewSize != .zero { fit(animated: false) } }
    }
    /// Unten von der Toolbox verdeckter Bereich (beim Einpassen frei lassen).
    var bottomInset: CGFloat = 90 {
        didSet { if oldValue != bottomInset, viewSize != .zero { fit(animated: false) } }
    }

    let undoManager = UndoManager()
    /// Zählt Änderungen, damit die Buttons `canUndo`/`canRedo` neu abfragen.
    private(set) var undoRevision = 0

    private let initialShapes: [RoomShape]

    struct SplitDraft: Equatable {
        let tableID: UUID
        var points: [GridPoint]
    }

    private struct Snapshot {
        let shapes: [RoomShape]
        let activeID: UUID?
        let splitDraft: SplitDraft?
        let pendingStart: GridPoint?
    }

    init(shapes: [RoomShape]) {
        self.shapes = shapes
        self.initialShapes = shapes
        self.issues = RoomValidation.issues(shapes)
        undoManager.levelsOfUndo = 200
        // Jede Änderung ist ein eigener Schritt (auch mehrere im selben Run-Loop-Durchlauf).
        undoManager.groupsByEvent = false
    }

    var hasChanges: Bool { shapes != initialShapes }

    var isEmpty: Bool { shapes.isEmpty }

    /// Rot markierte Elemente; der Linienzug, an dem gerade gezeichnet wird, bleibt unmarkiert.
    var invalidIDs: Set<UUID> {
        Set(issues.flatMap(\.elementIDs)).subtracting([activeID].compactMap { $0 })
    }

    /// Punkt, an dem die nächste Strecke beginnt (Ende des Linienzugs bzw. angetippter Startpunkt).
    var anchor: GridPoint? {
        splitDraft?.points.last ?? activeShape?.points.last ?? pendingStart
    }

    private var activeShape: RoomShape? {
        activeID.flatMap { id in shapes.first { $0.id == id } }
    }

    var drawingKind: RoomElementKind? {
        if case .pen(let kind) = tool { kind } else { nil }
    }

    // MARK: Zeichnen

    /// Strecke von `start` nach `end` mit dem aktuellen Stift.
    func addSegment(from start: GridPoint, to end: GridPoint) {
        guard let kind = drawingKind, start != end else { return }
        let before = snapshot
        defer { pendingStart = nil; recordUndo(before) }

        if var draft = splitDraft, draft.points.last == start {
            draft.points.append(end)
            continueSplit(draft)
            return
        }
        splitDraft = nil

        if let index = activeIndex, shapes[index].kind == kind, shapes[index].points.last == start {
            shapes[index].points.append(end)
            // Fläche geschlossen (Startpunkt erreicht) → fertig.
            if kind.isArea, end == shapes[index].points.first { activeID = nil }
            return
        }

        if kind == .table, let table = tableToSplit(from: start, to: end) {
            activeID = nil
            continueSplit(SplitDraft(tableID: table.id, points: [start, end]))
            return
        }

        let shape = RoomShape(kind: kind, points: [start, end])
        shapes.append(shape)
        activeID = shape.id
    }

    /// Antippen eines Rasterpunkts: verbindet mit dem letzten Punkt, setzt einen Startpunkt
    /// oder beendet den Linienzug (erneutes Antippen des letzten Punkts).
    func tap(at point: GridPoint) {
        guard drawingKind != nil else { return }
        if let anchor {
            if anchor == point { finishLine() } else { addSegment(from: anchor, to: point) }
        } else {
            pendingStart = point
        }
    }

    /// Linienzug beenden; eine angefangene Trennlinie verfällt.
    func finishLine() {
        activeID = nil
        splitDraft = nil
        pendingStart = nil
    }

    /// Pencil-Doppeltippen: zwischen aktuellem Stift und Radierer wechseln.
    func toggleEraser() {
        tool = tool == .eraser ? lastPen : .eraser
    }

    private var activeIndex: Int? {
        activeID.flatMap { id in shapes.firstIndex { $0.id == id } }
    }

    /// Tisch, in den eine am Rand beginnende Strecke hineinführt.
    private func tableToSplit(from start: GridPoint, to end: GridPoint) -> RoomShape? {
        shapes.first { shape in
            shape.kind == .table && shape.isClosed
                && RoomGeometry.locate(start, in: shape.points) == .boundary
                && RoomGeometry.pieceLocations(of: [start, end], relativeTo: shape.points).allSatisfy { $0 == .inside }
        }
    }

    private func continueSplit(_ draft: SplitDraft) {
        guard let index = shapes.firstIndex(where: { $0.id == draft.tableID }), let end = draft.points.last else {
            splitDraft = nil
            return
        }
        let table = shapes[index].points
        let isInside = RoomGeometry.pieceLocations(of: Array(draft.points.suffix(2)), relativeTo: table).allSatisfy { $0 == .inside }
        guard isInside, RoomGeometry.isSimplePath(draft.points) else {
            splitDraft = nil
            Haptics.notify(.error)
            return
        }
        guard RoomGeometry.locate(end, in: table) == .boundary else {
            splitDraft = draft
            return
        }
        splitDraft = nil
        guard let parts = RoomGeometry.split(table, along: draft.points) else {
            Haptics.notify(.error)
            return
        }
        shapes.replaceSubrange(index...index, with: [
            RoomShape(kind: .table, points: parts.first),
            RoomShape(kind: .table, points: parts.second),
        ])
        Haptics.tap()
    }

    // MARK: Radieren

    /// Entfernt das oberste Element, dessen Linie die Position trifft (in Rasterkoordinaten).
    /// Antippen im Inneren einer Fläche entfernt nichts.
    func erase(at location: RoomGeometry.Vector, tolerance: Double) {
        let ordered = shapes.sorted { $0.kind.layer > $1.kind.layer }
        let hit = ordered.first { RoomGeometry.distance(from: location, to: $0.points) <= tolerance }
        guard let hit else { return }
        let before = snapshot
        shapes.removeAll { $0.id == hit.id }
        if activeID == hit.id { activeID = nil }
        if splitDraft?.tableID == hit.id { splitDraft = nil }
        recordUndo(before)
        Haptics.tap()
    }

    // MARK: Rückgängig

    private var snapshot: Snapshot {
        Snapshot(shapes: shapes, activeID: activeID, splitDraft: splitDraft, pendingStart: pendingStart)
    }

    private func restore(_ snapshot: Snapshot) {
        shapes = snapshot.shapes
        activeID = snapshot.activeID
        splitDraft = snapshot.splitDraft
        pendingStart = snapshot.pendingStart
    }

    /// Registriert den Zustand vor einer Änderung; beim Rückgängigmachen wird der Gegenzustand
    /// als Wiederholen registriert.
    private func recordUndo(_ before: Snapshot) {
        guard before.shapes != shapes || before.splitDraft != splitDraft || before.activeID != activeID else { return }
        // Beim Rückgängigmachen/Wiederholen öffnet der UndoManager die Gruppe selbst.
        let needsGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if needsGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { model in
            let current = model.snapshot
            model.restore(before)
            model.recordUndo(current)
        }
        if needsGroup { undoManager.endUndoGrouping() }
        undoRevision += 1
    }

    /// Lesen `undoRevision` mit, damit SwiftUI nach jeder Änderung neu fragt (`UndoManager` ist nicht beobachtbar).
    var canUndo: Bool { undoRevision >= 0 && undoManager.canUndo }
    var canRedo: Bool { undoRevision >= 0 && undoManager.canRedo }

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        undoRevision += 1
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        undoRevision += 1
    }

    // MARK: Ausschnitt

    var spacing: CGFloat { Self.gridSpacing * zoom }

    func screenPoint(_ point: GridPoint) -> CGPoint {
        CGPoint(x: CGFloat(point.x) * spacing + pan.width, y: CGFloat(point.y) * spacing + pan.height)
    }

    /// Bildschirmposition → Rasterkoordinaten (ungerundet).
    func gridLocation(_ point: CGPoint) -> RoomGeometry.Vector {
        RoomGeometry.Vector(Double((point.x - pan.width) / spacing), Double((point.y - pan.height) / spacing))
    }

    func snap(_ point: CGPoint) -> GridPoint {
        RoomGeometry.snap(CGPoint(x: point.x - pan.width, y: point.y - pan.height), spacing: spacing)
    }

    /// Zoomen um einen festen Punkt (Mitte der Finger).
    func zoom(by factor: CGFloat, around focus: CGPoint) {
        let newZoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let applied = newZoom / zoom
        pan = CGSize(width: focus.x - (focus.x - pan.width) * applied, height: focus.y - (focus.y - pan.height) * applied)
        zoom = newZoom
    }

    /// Raum (bzw. leere Fläche) mittig mit Rand einpassen.
    func fit(animated: Bool = true) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let bounds = RoomGeometry.bounds(of: shapes.flatMap(\.points)) ?? (GridPoint(0, 0), GridPoint(18, 14))
        let width = CGFloat(max(bounds.max.x - bounds.min.x, 4))
        let height = CGFloat(max(bounds.max.y - bounds.min.y, 4))
        let available = CGSize(width: viewSize.width - 64, height: viewSize.height - 64 - bottomInset)
        let newZoom = min(max(min(available.width / width, available.height / height) / Self.gridSpacing, Self.zoomRange.lowerBound), 2)
        let spacing = Self.gridSpacing * newZoom
        let center = CGPoint(x: CGFloat(bounds.min.x) + width / 2, y: CGFloat(bounds.min.y) + height / 2)
        let update = {
            self.zoom = newZoom
            self.pan = CGSize(
                width: self.viewSize.width / 2 - center.x * spacing,
                height: (self.viewSize.height - self.bottomInset) / 2 - center.y * spacing
            )
        }
        if animated { withAnimation(.smooth, update) } else { update() }
    }
}
