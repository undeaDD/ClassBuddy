import SwiftUI

struct SettingsView: View {
    @Environment(AppSecurity.self) private var security

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { security.isAppLockEnabled },
            set: { newValue in Task { await security.setAppLockEnabled(newValue) } }
        )
    }

    var body: some View {
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
                LabeledContent("Version", value: Bundle.main.versionString)
            }
        }
        .navigationTitle(AppTab.settings.title)
        .appChrome(tab: .settings)
    }
}

private extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}
