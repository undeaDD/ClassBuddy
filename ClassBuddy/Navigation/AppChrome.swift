import SwiftData
import SwiftUI
import TipKit

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

    /// Jeder Tab hat eigene Toolbar-Buttons: Tipps nur am Button des sichtbaren Tabs.
    private var isVisibleTab: Bool { app.selectedTab == tab }

    private var classTip: SetupTip? {
        guard isVisibleTab, classes.isEmpty else { return nil }
        return SetupTip(.createClass, image: Image(icon: SetupStep.createClass.icon))
    }

    private var privacyTip: PrivacyModeTip? {
        guard isVisibleTab, selectedClass?.students.isEmpty == false else { return nil }
        return PrivacyModeTip(image: Image(icon: .eyeClosed))
    }

    func body(content: Content) -> some View {
        content.toolbar {
            if tab.usesClassSelection {
                ToolbarItem(placement: .topBarLeading) {
                    ClassPickerButton(selectedClass: selectedClass, tab: tab)
                        // Eigene Ankerfläche: Der Button hat schon das Klassen-Popover.
                        .background { Color.clear.appPopoverTip(classTip) }
                }
                .appSharedBackgroundHidden()
            }

            if hasActions {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Aktionen der Seite in der Akzentfarbe.
                    ToolbarCapsuleGroup {
                        actions
                            .foregroundStyle(.tint)
                    }
                }
            }

            if tab.showsPrivacyMode {
                if hasActions {
                    AppToolbarSpacer(placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PrivacyModeButton()
                        .appPopoverTip(privacyTip)
                        .toolbarGroupBackground()
                }
            }
        }
        // Bewusst ohne `toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)` (iOS 27):
        // Beim Push/Zurückwischen lief UIKit damit in eine Endlosschleife (Safe Area → Scroll-Beobachter
        // → Höhe der Navigationsleiste → Safe Area …), die App fror ein – vor allem in den Einstellungen.
        // Nur die Tab-Leiste minimiert beim Scrollen (`PhoneTabView`).
    }
}

struct PrivacyModeButton: View {
    @Environment(AppSecurity.self) private var security

    var body: some View {
        let isOn = security.isPrivacyModeOn
        Button {
            Haptics.tap()
            PrivacyModeTip().invalidate(reason: .actionPerformed)
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
