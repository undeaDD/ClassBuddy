import SwiftUI

struct SettingsView: View {
    @Environment(AppSecurity.self) private var security
    @Environment(\.dismiss) private var dismiss

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { security.isAppLockEnabled },
            set: { newValue in Task { await security.setAppLockEnabled(newValue) } }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: appLockBinding) {
                        Label("Mit \(security.biometryName) sperren", systemImage: security.biometrySymbol)
                    }
                    .disabled(security.isAuthenticating)
                } header: {
                    Text("App-Sperre")
                } footer: {
                    Text("Sperrt die App beim Start und beim Wechsel in den Hintergrund. Ausschalten erfordert \(security.biometryName).")
                }

                Section {
                    LabeledContent {
                        PrivacyModeButton()
                            .labelStyle(.iconOnly)
                    } label: {
                        Label("Privatsphäre-Modus", systemImage: "eye.slash")
                    }
                } footer: {
                    Text("Blendet sensible Daten auf allen Seiten aus. Ausschalten erfordert \(security.biometryName).")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionString)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

private extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

/// Zahnrad oben rechts, öffnet die Einstellungen.
struct SettingsButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button("Einstellungen", systemImage: "gearshape") {
            app.isSettingsPresented = true
        }
    }
}
