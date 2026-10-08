import SwiftUI
import UIKit

// Ersatz für APIs ab iOS 26, damit die App auch mit älterem Deployment Target baut:
// ab iOS 26 jeweils die System-API, davor ein einfacher Ersatz (oder nichts).
// Glas: `Glass.swift`.

extension View {
    /// `navigationSubtitle` ab iOS 26, davor als `prompt` über dem Titel.
    func appNavigationSubtitle(_ subtitle: String) -> some View {
        modifier(NavigationSubtitleModifier(subtitle: subtitle))
    }

    /// Buchstabe der Section im Index am Rand (ab iOS 26, davor ohne Index).
    @ViewBuilder
    func appSectionIndexLabel(_ label: String) -> some View {
        if #available(iOS 26, *) {
            sectionIndexLabel(label)
        } else {
            self
        }
    }

    /// Index am Rand der Liste einblenden (ab iOS 26, davor ohne Index).
    @ViewBuilder
    func appSectionIndexVisible() -> some View {
        if #available(iOS 26, *) {
            listSectionIndexVisibility(.visible)
        } else {
            self
        }
    }

    /// Tab-Leiste beim Runterscrollen verkleinern (ab iOS 26, davor bleibt sie, wie sie ist).
    @ViewBuilder
    func appTabBarMinimizesOnScroll(_ isEnabled: Bool) -> some View {
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(isEnabled ? .onScrollDown : .never)
        } else {
            self
        }
    }
}

/// Sheet-Größe auf dem iPad (`presentationSizing`, ab iOS 18).
enum AppPresentationSizing {
    case form, fitted, page
}

extension View {
    /// `presentationSizing` ab iOS 18, davor die Standardgröße (iPad: Form-Sheet). Auf dem iPhone ohne Wirkung.
    @ViewBuilder
    func appPresentationSizing(_ sizing: AppPresentationSizing) -> some View {
        if #available(iOS 18, *) {
            switch sizing {
            case .form: presentationSizing(.form)
            case .fitted: presentationSizing(.fitted)
            case .page: presentationSizing(.page)
            }
        } else {
            self
        }
    }
}

extension ButtonRole {
    /// `.close` ab iOS 26 (runder Glas-Knopf mit X), davor `.cancel`; das X kommt dort aus dem Label.
    static var appClose: ButtonRole {
        if #available(iOS 26, *) { .close } else { .cancel }
    }
}

/// `ToolbarSpacer(.fixed)` ab iOS 26, davor ein schmaler `Spacer` als eigenes Toolbar-Element.
struct AppToolbarSpacer: ToolbarContent {
    let placement: ToolbarItemPlacement

    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarSpacer(.fixed, placement: placement)
        } else {
            ToolbarItem(placement: placement) {
                Spacer().frame(width: 8)
            }
        }
    }
}

extension ToolbarContent {
    /// Ohne gemeinsamen Glas-Hintergrund (ab iOS 26; davor gibt es keinen).
    @ToolbarContentBuilder
    func appSharedBackgroundHidden() -> some ToolbarContent {
        if #available(iOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

// MARK: - Toolbar-Gruppen vor iOS 26

extension View {
    /// Inhalt eines Toolbar-Elements (oder einer `ToolbarItemGroup`) auf einer gemeinsamen Kapsel aus
    /// `.thinMaterial`, ähnlich dem Glas ab iOS 26. `prominent`: Kapsel in der Akzentfarbe, Inhalt weiß
    /// (wie `.confirm`). Ab iOS 26 unverändert, dort zeichnet das System das Glas.
    func toolbarGroupBackground(prominent: Bool = false) -> some View {
        modifier(ToolbarGroupBackground(prominent: prominent))
    }
}

/// Mehrere Buttons einer `ToolbarItemGroup`, die sich vor iOS 26 eine Kapsel teilen.
/// (Ein Modifier an einer Gruppe wirkt auf jedes Kind einzeln.) Ab iOS 26 unverändert.
struct ToolbarCapsuleGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            content
        } else {
            HStack(spacing: 0) { content }
                .toolbarGroupBackground()
        }
    }
}

private struct ToolbarGroupBackground: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            // Ein HStack, damit mehrere Buttons einer Gruppe eine Kapsel teilen.
            HStack(spacing: 0) { content }
                .buttonStyle(ToolbarCapsuleButtonStyle())
                .menuStyle(.button)
                .labelStyle(.iconOnly)
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                .padding(.horizontal, 2)
                .background {
                    ZStack {
                        Capsule().fill(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.thinMaterial))
                        Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                }
        }
    }
}

/// Button in einer Toolbar-Kapsel: 36 pt Trefferfläche, gedrückt und deaktiviert blasser.
private struct ToolbarCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(minWidth: 36, minHeight: 36)
            .contentShape(.capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.35)
    }
}

// MARK: - Zurück-Knopf vor iOS 26

/// Vor iOS 26: Zurück-Knopf überall als runde Fläche mit Pfeil (wie der Glas-Knopf ab iOS 26),
/// ohne den Titel der vorigen Seite. Über das Erscheinungsbild von `UINavigationBar`, damit Wischen
/// zum Zurückgehen und das Verlaufsmenü (lange drücken) erhalten bleiben. Ab iOS 26 ohne Wirkung.
@MainActor
enum LegacyBackButton {
    private static let side: CGFloat = 36
    /// UIKit setzt das Bild 8 pt vom Rand; die Kreise links (Klassen-Knopf) und rechts stehen 16 pt vom Rand.
    private static let leadingShift: CGFloat = 8
    /// Mittig zur Höhe der übrigen Toolbar-Knöpfe.
    private static let downShift: CGFloat = 7.2

    /// Beim Start und nach jedem Wechsel der Akzentfarbe (`AppAccent.apply`).
    static func apply(accent: UIColor) {
        guard #unavailable(iOS 26) else { return }
        let image = indicatorImage(accent: accent)
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        for appearance in [standard, scrollEdge] {
            appearance.setBackIndicatorImage(image, transitionMaskImage: image)
            // Titel unsichtbar und ohne Breite: nur die runde Fläche bleibt.
            let back = UIBarButtonItemAppearance(style: .plain)
            for state in [back.normal, back.highlighted, back.disabled, back.focused] {
                state.titleTextAttributes = [.foregroundColor: UIColor.clear, .font: UIFont.systemFont(ofSize: 0.1)]
            }
            appearance.backButtonAppearance = back
        }
        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = standard
        proxy.compactAppearance = standard
        proxy.scrollEdgeAppearance = scrollEdge
        proxy.compactScrollEdgeAppearance = scrollEdge

        // Schon sichtbare Leisten übernehmen die (neue) Akzentfarbe sofort.
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                for bar in navigationBars(in: window) {
                    bar.standardAppearance = standard
                    bar.compactAppearance = standard
                    bar.scrollEdgeAppearance = scrollEdge
                    bar.compactScrollEdgeAppearance = scrollEdge
                }
            }
        }
    }

    private static func navigationBars(in view: UIView) -> [UINavigationBar] {
        if let bar = view as? UINavigationBar { return [bar] }
        return view.subviews.flatMap(navigationBars)
    }

    /// Kreis in Material-Optik (wie die Toolbar-Kapseln) mit Pfeil in der Akzentfarbe, hell und dunkel.
    private static func indicatorImage(accent: UIColor) -> UIImage {
        // Je Darstellung und Bildschirm-Skalierung eine Variante; ohne Skalierung in den Traits liefert
        // das Asset das Bild in Pixel- statt Punktgröße (dreimal zu groß, UIKit verkleinert es dann).
        let asset = UIImageAsset()
        for scale in [2.0, 3.0] {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection { $0.userInterfaceStyle = style; $0.displayScale = scale }
                asset.register(render(accent: accent.resolvedColor(with: traits), traits: traits), with: traits)
            }
        }
        return asset.image(with: UITraitCollection { $0.userInterfaceStyle = .light; $0.displayScale = 3 })
    }

    /// Wie `.thinMaterial` der Toolbar-Kapseln (ohne Unschärfe): aus Bildschirmfotos auf iOS 18 über weißem
    /// und schwarzem Grund ermittelt, als halbdurchsichtige Farbe.
    private static func materialFill(_ traits: UITraitCollection) -> UIColor {
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 48 / 255, green: 49 / 255, blue: 49 / 255, alpha: 0.63)
            : UIColor(red: 237 / 255, green: 238 / 255, blue: 238 / 255, alpha: 0.6)
    }

    private static func render(accent: UIColor, traits: UITraitCollection) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = traits.displayScale
        // Ohne Schatten-Rand: UIKit begrenzt das Bild auf die Höhe des Knopfs (gut 36 pt) und würde es sonst verkleinern.
        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let circle = CGRect(origin: .zero, size: size)
            materialFill(traits).setFill()
            UIBezierPath(ovalIn: circle).fill()
            let stroke = UIBezierPath(ovalIn: circle.insetBy(dx: 0.25, dy: 0.25))
            stroke.lineWidth = 0.5
            UIColor.label.resolvedColor(with: traits).withAlphaComponent(0.08).setStroke()
            stroke.stroke()
            let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            if let chevron = UIImage(systemName: "chevron.backward", withConfiguration: configuration)?
                .withTintColor(accent, renderingMode: .alwaysOriginal) {
                // Optisch mittig: der Pfeil wirkt ohne kleinen Versatz nach rechts verschoben.
                let chevronSize = chevron.size
                chevron.draw(in: CGRect(
                    x: circle.midX - chevronSize.width / 2 - 1, y: circle.midY - chevronSize.height / 2,
                    width: chevronSize.width, height: chevronSize.height
                ))
            }
        }
        // Verschoben über die Ausrichtung: gleiche Größe, aber an den Rand der übrigen Toolbar-Knöpfe.
        return image
            .withRenderingMode(.alwaysOriginal)
            .withAlignmentRectInsets(UIEdgeInsets(top: -downShift, left: -leadingShift, bottom: downShift, right: leadingShift))
    }
}

// MARK: - Navigationsleiste vor iOS 26 (UIKit)

extension View {
    /// Vor iOS 26: Unterseiten zeigen beim Zurück-Knopf nur den Pfeil, ohne den Titel dieser Seite.
    /// Ab iOS 26 unverändert.
    @ViewBuilder
    func legacyMinimalBackButton() -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            background {
                NavigationItemSetter(backButtonDisplayMode: .minimal)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct NavigationSubtitleModifier: ViewModifier {
    let subtitle: String

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content.background {
                NavigationItemSetter(prompt: subtitle.isEmpty ? nil : subtitle)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Setzt Eigenschaften des `navigationItem` der Seite, in der dieser View steckt
/// (`nil` = nicht anfassen).
private struct NavigationItemSetter: UIViewControllerRepresentable {
    var prompt: String??
    var backButtonDisplayMode: UINavigationItem.BackButtonDisplayMode?

    init(prompt: String?) {
        self.prompt = .some(prompt)
    }

    init(backButtonDisplayMode: UINavigationItem.BackButtonDisplayMode) {
        self.backButtonDisplayMode = backButtonDisplayMode
    }

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.prompt = prompt
        controller.backButtonDisplayMode = backButtonDisplayMode
        controller.apply()
    }

    final class Controller: UIViewController {
        var prompt: String??
        var backButtonDisplayMode: UINavigationItem.BackButtonDisplayMode?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        /// Die Seite ist der Vorfahr, der direkt im `UINavigationController` liegt.
        func apply() {
            var page = parent
            while let current = page, !(current.parent is UINavigationController) {
                page = current.parent
            }
            guard let item = page?.navigationItem else { return }
            if let prompt, item.prompt != prompt {
                item.prompt = prompt
            }
            if let backButtonDisplayMode, item.backButtonDisplayMode != backButtonDisplayMode {
                item.backButtonDisplayMode = backButtonDisplayMode
            }
        }
    }
}
