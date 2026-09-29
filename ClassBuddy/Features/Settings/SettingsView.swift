import SwiftUI

struct SettingsView: View {
    @Environment(AppSecurity.self) private var security

    var body: some View {
        @Bindable var security = security
        Form {
            Section {
                Toggle(isOn: $security.isAppLockEnabled) {
                    Label("Mit \(security.biometryName) sperren", systemImage: security.biometrySymbol)
                }
            } header: {
                Text("Sicherheit")
            } footer: {
                Text("Die App wird beim Start und beim Wechsel in den Hintergrund gesperrt.")
            }

            Section {
                LabeledContent {
                    PrivacyModeButton()
                        .labelStyle(.iconOnly)
                } label: {
                    Label("Privatsphäre-Modus", systemImage: "eye.slash")
                }
            } footer: {
                Text("Blendet Namen, Noten und Notizen auf allen Seiten aus. Einschalten jederzeit, Ausschalten nur mit \(security.biometryName). Tipp: Doppeltippen auf den Apple Pencil schaltet ebenfalls um.")
            }

            Section {
                Label("Als JSON exportieren", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
                Label("Aus JSON importieren", systemImage: "square.and.arrow.down")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Daten")
            } footer: {
                Text("Alle Daten werden ausschließlich lokal gespeichert. Export folgt in einer späteren Version.")
            }

            Section("Apple Pencil") {
                LabeledContent("Squeeze", value: "Schnellmenü an der Stiftposition")
                LabeledContent("Doppeltippen", value: "Privatsphäre-Modus")
            }
        }
        .navigationTitle(AppTab.settings.title)
    }
}
