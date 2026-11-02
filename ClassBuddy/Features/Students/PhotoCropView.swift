import SwiftUI
import UIKit

/// Ausschnitt fürs Profilfoto wählen (z. B. ein Kind aus einem Gruppenfoto): Das ganze Foto bleibt sichtbar, außerhalb
/// des Kreises abgedunkelt. Zwei Finger zoomen um ihre Mitte, ein Finger verschiebt, Doppeltippen setzt zurück.
/// Ergebnis: quadratisches JPEG über `onCrop`.
///
/// Zoom und Verschiebung sind relativ zum Kreis gespeichert (Verschiebung in Kreisdurchmessern), damit Drehen oder
/// Größenänderungen des Fensters (iPad) den gewählten Ausschnitt nicht verändern. Gesten über UIKit (`CropGestures`):
/// Sie melden schrittweise Änderungen, SwiftUI-Gesten blieben nach Tippen-und-Zoomen-Folgen teils hängen.
struct PhotoCropView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onCrop: (Data) -> Void

    /// 1 = kurze Bildseite so groß wie der Kreis.
    @State private var scale: CGFloat = 1
    /// Bildmitte relativ zur Kreismitte, in Kreisdurchmessern.
    @State private var offset: CGSize = .zero

    private static let maxScale: CGFloat = 8
    private static let margin: CGFloat = 24

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let size = proxy.size
                let diameter = max(min(size.width, size.height) - 2 * Self.margin, 1)
                cropArea(size: size, diameter: diameter)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Ausschnitt wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                        .toolbarGroupBackground()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: loc("Übernehmen"), action: confirm)
                        .toolbarGroupBackground(prominent: true)
                }
            }
        }
    }

    private func cropArea(size: CGSize, diameter: CGFloat) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let imageSize = displayedSize(diameter: diameter, scale: scale)
        let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: imageSize.width, height: imageSize.height)
                .position(x: center.x + offset.width * diameter, y: center.y + offset.height * diameter)
            // Außerhalb des Kreises nur abgedunkelt, damit der Rest des Gruppenfotos erkennbar bleibt.
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addEllipse(in: circle)
            }
            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
            Circle()
                .strokeBorder(.tint, lineWidth: 2)
                .frame(width: diameter, height: diameter)
                .position(center)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay {
            CropGestures(
                onPan: { translation in
                    offset = clamped(
                        CGSize(width: offset.width + translation.width / diameter, height: offset.height + translation.height / diameter),
                        scale: scale
                    )
                },
                onPinch: { factor, location in zoom(by: factor, at: location, center: center, diameter: diameter) },
                onDoubleTap: {
                    withAnimation(.smooth) {
                        scale = 1
                        offset = .zero
                    }
                }
            )
        }
        .accessibilityLabel("Fotoausschnitt")
        .accessibilityHint("Mit zwei Fingern zoomen, mit einem Finger verschieben, doppelt tippen zum Zurücksetzen.")
    }

    // MARK: Gesten

    /// Zoom um den Punkt zwischen den Fingern: Dieser Bildpunkt bleibt unter den Fingern.
    private func zoom(by factor: CGFloat, at location: CGPoint, center: CGPoint, diameter: CGFloat) {
        let newScale = min(max(scale * factor, 1), Self.maxScale)
        let applied = newScale / scale
        let anchor = CGSize(width: (location.x - center.x) / diameter, height: (location.y - center.y) / diameter)
        scale = newScale
        offset = clamped(
            CGSize(
                width: anchor.width + (offset.width - anchor.width) * applied,
                height: anchor.height + (offset.height - anchor.height) * applied
            ),
            scale: newScale
        )
    }

    // MARK: Geometrie

    /// Bildgröße auf dem Bildschirm: die kurze Seite füllt den Kreis, mal Zoom.
    private func displayedSize(diameter: CGFloat, scale: CGFloat) -> CGSize {
        let fill = diameter / min(image.size.width, image.size.height) * scale
        return CGSize(width: image.size.width * fill, height: image.size.height * fill)
    }

    /// Das Bild muss das Quadrat um den Kreis immer ganz bedecken (in Kreisdurchmessern, unabhängig von der Größe).
    private func clamped(_ value: CGSize, scale: CGFloat) -> CGSize {
        let size = displayedSize(diameter: 1, scale: scale)
        let maxX = max(0, (size.width - 1) / 2)
        let maxY = max(0, (size.height - 1) / 2)
        return CGSize(width: min(max(value.width, -maxX), maxX), height: min(max(value.height, -maxY), maxY))
    }

    /// Quadrat unter dem Kreis aus dem Originalbild ausschneiden und als 512-px-JPEG übergeben.
    private func confirm() {
        // Bildpunkte je Kreisdurchmesser
        let pixelsPerDiameter = min(image.size.width, image.size.height) / scale
        let origin = CGPoint(
            x: image.size.width / 2 - (0.5 + offset.width) * pixelsPerDiameter,
            y: image.size.height / 2 - (0.5 + offset.height) * pixelsPerDiameter
        )
        let output = StudentPhoto.maxPixelSize
        let factor = output / pixelsPerDiameter
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let cropped = UIGraphicsImageRenderer(size: CGSize(width: output, height: output), format: format).image { _ in
            image.draw(in: CGRect(
                x: -origin.x * factor, y: -origin.y * factor,
                width: image.size.width * factor, height: image.size.height * factor
            ))
        }
        if let data = cropped.jpegData(compressionQuality: 0.8) { onCrop(data) }
        dismiss()
    }
}

/// Gesten-Ebene des Zuschnitts: ein oder zwei Finger verschieben, zwei Finger zoomen (gleichzeitig), doppelt tippen.
/// Meldet nur die Änderung seit dem letzten Aufruf.
private struct CropGestures: UIViewRepresentable {
    let onPan: (CGSize) -> Void
    let onPinch: (CGFloat, CGPoint) -> Void
    let onDoubleTap: () -> Void

    func makeUIView(context: Context) -> GestureView {
        GestureView()
    }

    func updateUIView(_ view: GestureView, context: Context) {
        view.onPan = onPan
        view.onPinch = onPinch
        view.onDoubleTap = onDoubleTap
    }

    final class GestureView: UIView, UIGestureRecognizerDelegate {
        var onPan: (CGSize) -> Void = { _ in }
        var onPinch: (CGFloat, CGPoint) -> Void = { _, _ in }
        var onDoubleTap: () -> Void = {}

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = true
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            addGestureRecognizer(pan)
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
            pinch.delegate = self
            addGestureRecognizer(pinch)
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed else { return }
            let translation = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            onPan(CGSize(width: translation.x, height: translation.y))
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed, gesture.numberOfTouches >= 2 else { return }
            let factor = gesture.scale
            gesture.scale = 1
            onPinch(factor, gesture.location(in: self))
        }

        @objc private func handleDoubleTap() {
            onDoubleTap()
        }
    }
}
