import SwiftUI
import UIKit

/// Ausschnitt fürs Profilfoto wählen: Zwei-Finger-Zoom, Verschieben, Kreis-Vorschau
/// (z. B. ein Kind aus einem Gruppenfoto). Ergebnis: quadratisches JPEG über `onCrop`.
struct PhotoCropView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onCrop: (Data) -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero

    private static let maxScale: CGFloat = 8

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height) - 32
                ZStack {
                    Color.black.ignoresSafeArea()
                    cropArea(side: side)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

    private func cropArea(side: CGFloat) -> some View {
        let currentScale = clampedScale(scale * gestureScale)
        let currentOffset = clampedOffset(
            CGSize(width: offset.width + gestureOffset.width, height: offset.height + gestureOffset.height),
            scale: currentScale, side: side
        )
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .scaleEffect(currentScale)
            .offset(currentOffset)
            .frame(width: side, height: side)
            .clipped()
            // Außerhalb des Kreises abgedunkelt, Kreis in der Akzentfarbe umrandet.
            .overlay {
                Rectangle()
                    .fill(.black.opacity(0.55))
                    .mask {
                        Rectangle()
                            .overlay { Circle().blendMode(.destinationOut) }
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)
            }
            .overlay {
                Circle().strokeBorder(.tint, lineWidth: 2).allowsHitTesting(false)
            }
            .contentShape(.rect)
            .gesture(
                MagnifyGesture()
                    .updating($gestureScale) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = clampedScale(scale * value.magnification)
                        offset = clampedOffset(offset, scale: scale, side: side)
                    }
                    .simultaneously(with:
                        DragGesture()
                            .updating($gestureOffset) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                offset = clampedOffset(
                                    CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height),
                                    scale: scale, side: side
                                )
                            }
                    )
            )
            .onAppear { cropSide = side }
            .onChange(of: side) { _, newSide in cropSide = newSide }
            .accessibilityLabel("Fotoausschnitt")
            .accessibilityHint("Mit zwei Fingern zoomen, mit einem Finger verschieben.")
    }

    @State private var cropSide: CGFloat = 1

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), Self.maxScale)
    }

    /// Das Bild muss das Quadrat immer ganz bedecken.
    private func clampedOffset(_ value: CGSize, scale: CGFloat, side: CGFloat) -> CGSize {
        let fill = side / min(image.size.width, image.size.height)
        let maxX = max(0, (image.size.width * fill * scale - side) / 2)
        let maxY = max(0, (image.size.height * fill * scale - side) / 2)
        return CGSize(width: min(max(value.width, -maxX), maxX), height: min(max(value.height, -maxY), maxY))
    }

    /// Sichtbares Quadrat aus dem Originalbild ausschneiden und als 512-px-JPEG übergeben.
    private func confirm() {
        let side = cropSide
        let pointsPerPixel = side / min(image.size.width, image.size.height) * scale
        let cropSize = side / pointsPerPixel
        let origin = CGPoint(
            x: image.size.width / 2 - (side / 2 + offset.width) / pointsPerPixel,
            y: image.size.height / 2 - (side / 2 + offset.height) / pointsPerPixel
        )
        let output = StudentPhoto.maxPixelSize
        let factor = output / cropSize
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
