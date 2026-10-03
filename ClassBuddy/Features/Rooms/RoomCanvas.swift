import SwiftUI
import UIKit

/// Zeichenfläche des Raum-Editors: unendliches Punktraster, Raumelemente, Vorschau der nächsten Strecke.
/// Gesten kommen aus `RoomCanvasGestures` (UIKit), weil SwiftUI Finger nicht zählen kann.
struct RoomCanvas: View {
    let model: RoomEditorModel

    var body: some View {
        // Zustand hier lesen (nicht erst im Canvas-Renderer), damit SwiftUI Änderungen beobachtet.
        let scene = Scene(model: model)
        Canvas { context, size in
            scene.draw(in: context, size: size)
        }
        .overlay {
            RoomCanvasGestures(model: model)
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { model.viewSize = $0 }
        .background(Color(.systemBackground))
        .accessibilityLabel("Zeichenfläche")
    }

    /// Momentaufnahme alles Sichtbaren.
    private struct Scene {
        let shapes: [RoomShape]
        let invalid: Set<UUID>
        let spacing: CGFloat
        let pan: CGSize
        let color: Color
        let splitDraft: [GridPoint]?
        let drag: (start: GridPoint, end: GridPoint)?
        let anchor: GridPoint?
        let hover: GridPoint?

        init(model: RoomEditorModel) {
            shapes = model.shapes
            invalid = model.invalidIDs
            spacing = model.spacing
            pan = model.pan
            color = model.drawingKind?.color ?? .secondary
            splitDraft = model.splitDraft?.points
            drag = model.dragStart.flatMap { start in model.dragEnd.map { (start, $0) } }
            anchor = model.anchor
            hover = model.hoverPoint
        }

        func screenPoint(_ point: GridPoint) -> CGPoint {
            CGPoint(x: CGFloat(point.x) * spacing + pan.width, y: CGFloat(point.y) * spacing + pan.height)
        }

        func draw(in context: GraphicsContext, size: CGSize) {
            drawGrid(in: context, size: size)
            let lineWidth = min(max(spacing * 0.1, 1.5), 4)
            RoomDrawing.draw(shapes, in: context, lineWidth: lineWidth, invalid: invalid, map: screenPoint)
            drawDrafts(in: context, lineWidth: lineWidth)
        }

        /// Nur sichtbare Punkte; bei kleinem Zoom jeder n-te, damit das Raster ruhig bleibt.
        private func drawGrid(in context: GraphicsContext, size: CGSize) {
            let step = spacing < 10 ? Int((10 / spacing).rounded(.up)) : 1
            let minX = Int(floor(-pan.width / spacing)), maxX = Int(ceil((size.width - pan.width) / spacing))
            let minY = Int(floor(-pan.height / spacing)), maxY = Int(ceil((size.height - pan.height) / spacing))
            let radius = min(max(spacing * 0.06, 1), 2)
            var dots = Path()
            for x in stride(from: minX - minX % step, through: maxX, by: step) {
                for y in stride(from: minY - minY % step, through: maxY, by: step) {
                    let center = screenPoint(GridPoint(x, y))
                    dots.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                }
            }
            context.fill(dots, with: .color(.secondary.opacity(0.6)))
        }

        private func drawDrafts(in context: GraphicsContext, lineWidth: CGFloat) {
            if let splitDraft {
                let path = RoomDrawing.path(for: RoomShape(kind: .table, points: splitDraft), map: screenPoint)
                context.stroke(path, with: .color(color), style: dashed(lineWidth))
            }
            if let drag, drag.start != drag.end {
                var path = Path()
                path.move(to: screenPoint(drag.start))
                path.addLine(to: screenPoint(drag.end))
                context.stroke(path, with: .color(color.opacity(0.7)), style: dashed(lineWidth))
                dot(at: drag.end, color: color, in: context)
            }
            if let anchor {
                dot(at: anchor, color: color, in: context)
            }
            if let hover {
                dot(at: hover, color: color.opacity(0.5), in: context)
            }
        }

        private func dashed(_ lineWidth: CGFloat) -> StrokeStyle {
            StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [lineWidth * 2, lineWidth * 1.5])
        }

        private func dot(at point: GridPoint, color: Color, in context: GraphicsContext) {
            let center = screenPoint(point)
            let radius = max(spacing * 0.18, 5)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
    }
}

/// Gesten-Ebene: ein Finger bzw. Pencil zeichnet (Ziehen = Strecke, Antippen = Punkt), zwei Finger
/// verschieben und zoomen. Pencil: Doppeltippen wechselt zum Radierer, Hover zeigt den nächsten Rasterpunkt.
private struct RoomCanvasGestures: UIViewRepresentable {
    let model: RoomEditorModel

    func makeUIView(context: Context) -> GestureView {
        GestureView(model: model)
    }

    func updateUIView(_ view: GestureView, context: Context) {
        view.model = model
    }

    final class GestureView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
        var model: RoomEditorModel
        private var lastPinchScale: CGFloat = 1
        private var lastPanTranslation: CGPoint = .zero
        private var drawGesture: UIPanGestureRecognizer?

        init(model: RoomEditorModel) {
            self.model = model
            super.init(frame: .zero)
            backgroundColor = .clear
            isMultipleTouchEnabled = true

            let draw = UIPanGestureRecognizer(target: self, action: #selector(handleDraw))
            draw.maximumNumberOfTouches = 1
            draw.delegate = self
            addGestureRecognizer(draw)
            drawGesture = draw

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            addGestureRecognizer(tap)

            let move = UIPanGestureRecognizer(target: self, action: #selector(handleMove))
            move.minimumNumberOfTouches = 2
            move.delegate = self
            addGestureRecognizer(move)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
            pinch.delegate = self
            addGestureRecognizer(pinch)

            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(handleHover)))

            let pencil = UIPencilInteraction(delegate: self)
            addInteraction(pencil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        // Zwei-Finger-Verschieben und Zoomen gleichzeitig.
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            gesture is UIPinchGestureRecognizer || other is UIPinchGestureRecognizer
                || (gesture as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2
                    && (other as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2
        }

        @objc private func handleDraw(_ gesture: UIPanGestureRecognizer) {
            switch model.tool {
            case .move: panWithOneFinger(gesture)
            case .eraser: eraseAlong(gesture)
            case .pen: drawSegment(gesture)
            }
        }

        /// Verschieben-Werkzeug: ein Finger verschiebt den Ausschnitt, nichts wird gezeichnet.
        private func panWithOneFinger(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: self)
            if gesture.state == .began { lastPanTranslation = .zero }
            model.pan.width += translation.x - lastPanTranslation.x
            model.pan.height += translation.y - lastPanTranslation.y
            lastPanTranslation = translation
        }

        private func eraseAlong(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began: erase(at: startLocation(of: gesture))
            case .changed: erase(at: gesture.location(in: self))
            default: break
            }
        }

        private func drawSegment(_ gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: self)
            switch gesture.state {
            case .began:
                model.dragStart = model.snap(startLocation(of: gesture))
                model.dragEnd = model.snap(location)
            case .changed:
                model.dragEnd = model.snap(location)
            case .ended:
                if let start = model.dragStart {
                    model.addSegment(from: start, to: model.snap(location))
                }
                model.dragStart = nil
                model.dragEnd = nil
            default:
                model.dragStart = nil
                model.dragEnd = nil
            }
        }

        /// Beginn der Bewegung, nicht der Punkt nach Überschreiten der Ziehschwelle.
        private func startLocation(of gesture: UIPanGestureRecognizer) -> CGPoint {
            let location = gesture.location(in: self), translation = gesture.translation(in: self)
            return CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: self)
            switch model.tool {
            case .move: break
            case .eraser: erase(at: location)
            case .pen: model.tap(at: model.snap(location))
            }
        }

        private func erase(at location: CGPoint) {
            // Trefferbereich ~14 pt, unabhängig vom Zoom.
            model.erase(at: model.gridLocation(location), tolerance: Double(14 / model.spacing))
        }

        /// Zweiter Finger kommt dazu → angefangene Strecke verwerfen (Aus-/Einschalten bricht die Geste ab).
        private func cancelDrawing() {
            model.dragStart = nil
            model.dragEnd = nil
            drawGesture?.isEnabled = false
            drawGesture?.isEnabled = true
        }

        @objc private func handleMove(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: self)
            if gesture.state == .began {
                lastPanTranslation = .zero
                cancelDrawing()
            }
            model.pan.width += translation.x - lastPanTranslation.x
            model.pan.height += translation.y - lastPanTranslation.y
            lastPanTranslation = translation
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began {
                lastPinchScale = 1
                cancelDrawing()
            }
            guard gesture.numberOfTouches >= 2 else { return }
            model.zoom(by: gesture.scale / lastPinchScale, around: gesture.location(in: self))
            lastPinchScale = gesture.scale
        }

        @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
            switch gesture.state {
            case .began, .changed: model.hoverPoint = model.drawingKind == nil ? nil : model.snap(gesture.location(in: self))
            default: model.hoverPoint = nil
            }
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            model.toggleEraser()
            Haptics.selection()
        }
    }
}
