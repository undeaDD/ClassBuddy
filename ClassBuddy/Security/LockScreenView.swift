import SwiftUI

/// Vollflächige Sperre, solange die App nicht entsperrt ist.
struct LockScreenView: View {
    @Environment(AppSecurity.self) private var security

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
            Rectangle()
                .fill(Color.accentColor.opacity(0.08).gradient)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 96, height: 96)
                    .glassEffect(.regular, in: .circle)

                VStack(spacing: 6) {
                    Text("ClassBuddy ist gesperrt")
                        .font(.title2.bold())
                    Text("Schülerdaten sind geschützt.")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await security.unlock() }
                } label: {
                    Label("Mit \(security.biometryName) entsperren", systemImage: security.biometrySymbol)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(security.isAuthenticating)
                .hoverEffect(.lift)

                if let error = security.lastError {
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
                Image(systemName: "lock.shield")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
            }
    }
}
