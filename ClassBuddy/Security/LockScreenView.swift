import SwiftUI

/// Vollflächige Sperre, solange die App nicht entsperrt ist: Milchglas über dem zuletzt
/// sichtbaren Bildschirm (der zusätzlich in `RootView` unscharf gezeichnet wird).
struct LockScreenView: View {
    @Environment(AppSecurity.self) private var security
    /// Nur für das Debug-Menü: Fehlermeldung ohne echten Fehlversuch anzeigen.
    var previewError: String?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()
            Rectangle()
                .fill(.tint.opacity(0.08))
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(icon: .fingerprintLockCircle)
                    .iconSize(120)
                    .foregroundStyle(.tint)

                VStack(spacing: 6) {
                    Text("ClassBuddy ist gesperrt")
                        .font(.title2.bold())
                    Text("Schülerdaten sind geschützt.")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await security.unlock() }
                } label: {
                    Text("Mit \(security.biometryName) entsperren")
                        .padding(.horizontal, 8)
                }
                .appGlassButtonStyle(prominent: true)
                .controlSize(.large)
                .disabled(security.isAuthenticating)
                .hoverEffect(.lift)

                if let error = previewError ?? security.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(40)
        }
    }
}

/// Deckt Inhalte ab, sobald die App nicht aktiv ist (App-Umschalter-Snapshot).
struct PrivacyCoverView: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .ignoresSafeArea()
            .overlay {
                Image(icon: .lock)
                    .iconSize(80)
                    .foregroundStyle(.tint)
            }
    }
}
