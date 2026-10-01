import SwiftData
import SwiftUI

extension View {
    /// Gemeinsame Toolbar für jede Tab-Root-View:
    /// links „Klasse auswählen“ (nur bei `AppTab.usesClassSelection`), rechts ganz außen
    /// der Privatsphäre-Modus (nur bei `AppTab.showsPrivacyMode`).
    /// Unterseiten (Push) zeigen die Toolbar der Wurzel nicht.
    /// Seitenspezifische Buttons (`actions`) stehen links davon, optisch getrennt.
    /// Alles in einem Toolbar-Block, damit die Reihenfolge fest ist.
    func appChrome<Actions: View>(tab: AppTab, @ViewBuilder actions: () -> Actions) -> some View {
        modifier(AppChromeModifier(tab: tab, hasActions: true, actions: actions()))
    }

    func appChrome(tab: AppTab) -> some View {
        modifier(AppChromeModifier(tab: tab, hasActions: false, actions: EmptyView()))
    }

    /// Navigationsleiste beim Runterscrollen verkleinern, beim Hochscrollen wieder zeigen (ab iOS 27).
    /// Abschaltbar in den App-Einstellungen („Leisten beim Scrollen minimieren“).
    func navigationBarMinimizesOnScroll() -> some View {
        modifier(NavigationBarMinimization())
    }
}

private struct AppChromeModifier<Actions: View>: ViewModifier {
    @Environment(AppModel.self) private var app
    @Query private var classes: [SchoolClass]
    let tab: AppTab
    let hasActions: Bool
    let actions: Actions

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == app.selectedClassID }
    }

    func body(content: Content) -> some View {
        content.toolbar {
            if tab.usesClassSelection {
                ToolbarItem(placement: .topBarLeading) {
                    ClassPickerButton(selectedClass: selectedClass, tab: tab)
                }
                .sharedBackgroundVisibility(.hidden)
            }

            if hasActions {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Aktionen der Seite in der Akzentfarbe.
                    actions
                        .foregroundStyle(.tint)
                }
            }

            if tab.showsPrivacyMode {
                if hasActions {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PrivacyModeButton()
                }
            }
        }
        .navigationBarMinimizesOnScroll()
    }
}

private struct NavigationBarMinimization: ViewModifier {
    @AppStorage(AppPreference.minimizesBarsOnScroll) private var isEnabled = true

    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.toolbarMinimizationBehavior(isEnabled ? .onScrollDown : .never, for: .navigationBar)
        } else {
            content
        }
    }
}

struct PrivacyModeButton: View {
    @Environment(AppSecurity.self) private var security

    var body: some View {
        let isOn = security.isPrivacyModeOn
        Button {
            Haptics.tap()
            Task { await security.togglePrivacyMode() }
        } label: {
            Label(
                isOn ? "Privatsphäre-Modus aus" : "Privatsphäre-Modus an",
                image: isOn ? .eyeClosed : .eye
            )
        }
        // Akzentfarbe, bei aktivem Privatsphäre-Modus orange.
        .foregroundStyle(isOn ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
        .tint(isOn ? .orange : nil)
        .disabled(security.isAuthenticating)
        .help(isOn ? loc("Sensible Daten anzeigen (\(security.biometryName))") : "Sensible Daten ausblenden")
        .keyboardShortcut("p", modifiers: [.command, .shift])
    }
}
