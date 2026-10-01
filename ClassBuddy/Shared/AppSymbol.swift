import SwiftUI
import UIKit

/// Icon als Wert (z. B. Symbol einer Kachel oder eines Tabs). Das Bild kommt aus dem aktiven
/// Icon-Theme (`IconManager`). Neue SVGs ins `Icons/`-Postfach legen und `scripts/sync-icons.sh` ausführen.
nonisolated enum AppSymbol: Hashable, Sendable {
    case custom(AppIcon)

    @MainActor
    var image: Image {
        switch self {
        case .custom(let icon): Image(icon: icon)
        }
    }

    /// UIKit-Bild des Symbols (z. B. um die Farbe fest vorzugeben).
    @MainActor
    var uiImage: UIImage? {
        switch self {
        case .custom(let icon): IconManager.shared.uiImage(icon)
        }
    }

    /// Bild in fester Farbe (nicht mehr vom System einfärbbar); dynamische Farben
    /// wie `.label` passen sich weiterhin an Hell/Dunkel an.
    @MainActor
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
