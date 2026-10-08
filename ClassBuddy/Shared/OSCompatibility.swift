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
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
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

// MARK: - Untertitel vor iOS 26

private struct NavigationSubtitleModifier: ViewModifier {
    let subtitle: String

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content.background {
                NavigationPromptSetter(prompt: subtitle.isEmpty ? nil : subtitle)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Setzt `navigationItem.prompt` der Seite, in der dieser View steckt.
private struct NavigationPromptSetter: UIViewControllerRepresentable {
    let prompt: String?

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.prompt = prompt
    }

    final class Controller: UIViewController {
        var prompt: String? {
            didSet { apply() }
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        /// Die Seite ist der Vorfahr, der direkt im `UINavigationController` liegt.
        private func apply() {
            var page = parent
            while let current = page, !(current.parent is UINavigationController) {
                page = current.parent
            }
            guard let page, page.navigationItem.prompt != prompt else { return }
            page.navigationItem.prompt = prompt
        }
    }
}
