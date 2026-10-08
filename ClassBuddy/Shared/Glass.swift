import SwiftUI

/// Liquid-Glass-Beschreibung, die auch vor iOS 26 baut. Spiegelt `Glass` (Variante, Tönung, interaktiv):
/// ab iOS 26 wird daraus echtes Glas, darunter ein Material mit optionaler Tönung.
struct AppGlass: Equatable {
    enum Variant {
        case regular, clear, identity
    }

    var variant: Variant = .regular
    var tint: Color?
    var isInteractive = false

    static let regular = AppGlass()
    static let clear = AppGlass(variant: .clear)
    static let identity = AppGlass(variant: .identity)

    func tint(_ color: Color?) -> AppGlass {
        var glass = self
        glass.tint = color
        return glass
    }

    func interactive(_ isEnabled: Bool = true) -> AppGlass {
        var glass = self
        glass.isInteractive = isEnabled
        return glass
    }

    @available(iOS 26, *)
    var glass: Glass {
        let base: Glass = switch variant {
        case .regular: .regular
        case .clear: .clear
        case .identity: .identity
        }
        return base.tint(tint).interactive(isInteractive)
    }

    /// Ersatz vor iOS 26. `clear` ist dort etwas durchsichtiger als `regular`.
    fileprivate var fallbackMaterial: Material {
        variant == .clear ? .ultraThinMaterial : .thinMaterial
    }
}

extension View {
    /// `glassEffect(_:in:)` mit Fallback auf `.thinMaterial` vor iOS 26.
    /// Interaktivität (Aufleuchten beim Drücken) gibt es nur mit echtem Glas.
    /// `fallbackShadow`: leichter Schatten im Fallback (aus für Knöpfe in der Navigationsleiste).
    func appGlassEffect<S: Shape>(_ glass: AppGlass = .regular, in shape: S = Capsule(), fallbackShadow: Bool = true) -> some View {
        modifier(AppGlassModifier(glass: glass, shape: shape, hasShadow: fallbackShadow))
    }
}

private struct AppGlassModifier<S: Shape>: ViewModifier {
    let glass: AppGlass
    let shape: S
    let hasShadow: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(glass.glass, in: shape)
        } else if glass.variant == .identity {
            content
        } else {
            content.background {
                ZStack {
                    shape.fill(glass.fallbackMaterial)
                    // Kräftig genug, dass weiße Schrift auf getöntem Glas lesbar bleibt (Klassen-Badge, Kalender).
                    if let tint = glass.tint {
                        shape.fill(tint.opacity(0.75))
                    }
                    shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(hasShadow ? 0.08 : 0), radius: 8, y: 2)
            }
        }
    }
}

extension View {
    /// `.buttonStyle(.glass)` bzw. `.glassProminent` ab iOS 26, davor `.bordered` bzw. `.borderedProminent`.
    @ViewBuilder
    func appGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// `GlassEffectContainer` ab iOS 26 (Glasformen verschmelzen), davor nur der Inhalt.
struct AppGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
