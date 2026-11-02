import SwiftUI
import UIKit

/// Ausschnitt fürs Profilfoto wählen (z. B. ein Kind aus einem Gruppenfoto): Das ganze Foto bleibt sichtbar, außerhalb
/// des Kreises abgedunkelt. Zwei Finger zoomen um ihre Mitte, ein Finger verschiebt, Doppeltippen setzt zurück.
/// Ergebnis: quadratisches JPEG über `onCrop`.
///
/// Zoom und Verschiebung sind relativ zum Kreis gespeichert (Verschiebung in Kreisdurchmessern), damit Drehen oder
/// Größenänderungen des Fensters (iPad) den gewählten Ausschnitt nicht verändern.
struct PhotoCropView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onCrop: (Data) -> Void

    /// 1 = kurze Bildseite so groß wie der Kreis.
    @State private var scale: CGFloat = 1
    /// Bildmitte relativ zur Kreismitte, in Kreisdurchmessern.
    @State private var offset: CGSize = .zero
    /// Zustand zu Beginn der laufenden Geste.
    @State private var gestureStart: (scale: CGFloat, offset: CGSize)?

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
        .contentShape(.rect)
        .gesture(moveAndZoom(center: center, diameter: diameter))
        .onTapGesture(count: 2) {
            withAnimation(.smooth) {
                scale = 1
                offset = .zero
            }
        }
        .accessibilityLabel("Fotoausschnitt")
        .accessibilityHint("Mit zwei Fingern zoomen, mit einem Finger verschieben, doppelt tippen zum Zurücksetzen.")
    }

    // MARK: Gesten

    /// Verschieben und Zoomen in einer Geste: Zoom um den Punkt zwischen den Fingern (dieser Bildpunkt bleibt unter
    /// den Fingern), dazu die Verschiebung des Fingers.
    private func moveAndZoom(center: CGPoint, diameter: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .simultaneously(with: MagnifyGesture())
            .onChanged { value in
                let start = gestureStart ?? (scale, offset)
                gestureStart = start
                let magnification = value.second?.magnification ?? 1
                let newScale = min(max(start.scale * magnification, 1), Self.maxScale)
                let factor = newScale / start.scale
                let anchorPoint = value.second?.startLocation ?? value.first?.startLocation ?? center
                let anchor = CGSize(width: (anchorPoint.x - center.x) / diameter, height: (anchorPoint.y - center.y) / diameter)
                let translation = value.first?.translation ?? .zero
                scale = newScale
                offset = clamped(
                    CGSize(
                        width: anchor.width + (start.offset.width - anchor.width) * factor + translation.width / diameter,
                        height: anchor.height + (start.offset.height - anchor.height) * factor + translation.height / diameter
                    ),
                    scale: newScale
                )
            }
            .onEnded { _ in gestureStart = nil }
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
