import SwiftData
import SwiftUI

extension View {
    /// Gemeinsame Toolbar für jede Tab-Root-View:
    /// links „Klasse auswählen“, rechts ganz außen immer der Privatsphäre-Modus.
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

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ClassPickerButton(selectedClass: selectedClass, tab: tab)
            }
            .sharedBackgroundVisibility(.hidden)

            if hasActions {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Aktionen der Seite in der Akzentfarbe.
                    actions
                        .foregroundStyle(Color.accentColor)
                        .tint(Color.accentColor)
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            ToolbarItem(placement: .topBarTrailing) {
                PrivacyModeButton()
            }
        }
    }
}

struct PrivacyModeButton: View {
    @Environment(AppSecurity.self) private var security

    var body: some View {
        let isOn = security.isPrivacyModeOn
        Button {
            Task { await security.togglePrivacyMode() }
        } label: {
            Label(
                isOn ? "Privatsphäre-Modus aus" : "Privatsphäre-Modus an",
                image: isOn ? .eyeClosed : .eye
            )
        }
        // Akzentfarbe, bei aktivem Privatsphäre-Modus orange.
        .foregroundStyle(isOn ? Color.orange : Color.accentColor)
        .tint(isOn ? .orange : Color.accentColor)
        .disabled(security.isAuthenticating)
        .help(isOn ? "Sensible Daten anzeigen (\(security.biometryName))" : "Sensible Daten ausblenden")
        .keyboardShortcut("p", modifiers: [.command, .shift])
    }
}
