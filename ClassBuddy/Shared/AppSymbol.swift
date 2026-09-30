import SwiftUI
import UIKit

/// Einheitliche Icon-Quelle für die ganze App: nur eigene Icons aus
/// `Assets.xcassets/Icons` (SVG, Template-Rendering, übernimmt also Tint/Vordergrundfarbe).
/// Neue SVGs ins `Icons/`-Postfach legen und `scripts/sync-icons.sh` ausführen.
nonisolated enum AppSymbol: Hashable, Sendable {
    case custom(ImageResource)

    var image: Image {
        switch self {
        case .custom(let resource): Image(resource)
        }
    }

    /// UIKit-Bild des Symbols (z. B. um die Farbe fest vorzugeben).
    var uiImage: UIImage? {
        switch self {
        case .custom(let resource): UIImage(resource: resource)
        }
    }

    /// Bild in fester Farbe (nicht mehr vom System einfärbbar); dynamische Farben
    /// wie `.label` passen sich weiterhin an Hell/Dunkel an.
    func fixedColorImage(_ color: UIColor) -> Image {
        guard let uiImage else { return image }
        return Image(uiImage: uiImage.withTintColor(color, renderingMode: .alwaysOriginal))
    }
}

extension Image {
    /// Feste Icon-Größe – eigene SVG-Icons skalieren nicht mit `.font()`.
    func iconSize(_ size: CGFloat) -> some View {
        resizable().scaledToFit().frame(width: size, height: size)
    }
}

extension Label where Title == Text, Icon == Image {
    init(_ title: LocalizedStringKey, symbol: AppSymbol) {
        self.init { Text(title) } icon: { symbol.image }
    }

    init(_ title: String, symbol: AppSymbol) {
        self.init { Text(title) } icon: { symbol.image }
    }
}
