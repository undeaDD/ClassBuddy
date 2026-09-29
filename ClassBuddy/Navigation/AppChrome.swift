import SwiftData
import SwiftUI

extension View {
    /// Gemeinsame Toolbar für jede Tab-Root-View:
    /// links „Klasse auswählen“, rechts Privatsphäre-Modus.
    func appChrome(tab: AppTab) -> some View {
        modifier(AppChromeModifier(tab: tab))
    }
}

private struct AppChromeModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @Query private var classes: [SchoolClass]
    let tab: AppTab

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == app.selectedClassID }
    }

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ClassPickerButton(selectedClass: selectedClass, tab: tab)
            }
            .sharedBackgroundVisibility(.hidden)

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
                systemImage: isOn ? "eye.slash.fill" : "eye"
            )
            .contentTransition(.symbolEffect(.replace))
        }
        .tint(isOn ? .orange : nil)
        .disabled(security.isAuthenticating)
        .help(isOn ? "Sensible Daten anzeigen (\(security.biometryName))" : "Sensible Daten ausblenden")
        .keyboardShortcut("p", modifiers: [.command, .shift])
    }
}
