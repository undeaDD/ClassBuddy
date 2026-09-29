import SwiftUI
import UIKit

/// Einheitliche Icon-Quelle für die ganze App.
///
/// - `system`: öffentliche SF Symbols.
/// - `private`: interne SF Symbols (zu finden mit der App „PrivateSymbols“,
///   github.com/quentinfasquel/PrivateSymbols). Nutzt `Image(_internalSystemName:)`
///   – nur für private Distribution geeignet, nicht App-Store-sicher.
/// - `custom`: eigene Icons aus `Assets.xcassets/Icons` (SVG, Template-Rendering,
///   übernimmt also Tint/Vordergrundfarbe). Neue SVGs dort als Image Set ablegen.
nonisolated enum AppSymbol: Hashable, Sendable {
    case system(String)
    case `private`(String, fallback: String)
    case custom(ImageResource)

    var image: Image {
        switch self {
        case .system(let name):
            Image(systemName: name)
        case .private(let name, let fallback):
            if Self.privateSymbolExists(name) {
                Image(_internalSystemName: name)
            } else {
                Image(systemName: fallback)
            }
        case .custom(let resource):
            Image(resource)
        }
    }

    /// Prüft, ob ein internes Symbol auf diesem OS existiert, damit bei
    /// OS-Updates nie ein leeres Icon angezeigt wird.
    private static func privateSymbolExists(_ name: String) -> Bool {
        let selector = NSSelectorFromString("_systemImageNamed:")
        guard UIImage.responds(to: selector) else { return false }
        return UIImage.perform(selector, with: name)?.takeUnretainedValue() != nil
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
