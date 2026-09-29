import SwiftUI

/// Oberste View: Navigation + Privatsphäre-Modus + App-Sperre + Pencil-Aktionen.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        AppTabView()
            .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
            // Einmal zentral statt in jeder Tab-Toolbar (vermeidet doppelte Präsentation).
            .sheet(isPresented: $app.isSettingsPresented) {
                SettingsView()
            }
            .pencilQuickActions()
            .overlay {
                if security.isLocked {
                    LockScreenView()
                        .transition(.opacity)
                } else if scenePhase != .active {
                    PrivacyCoverView()
                }
            }
            .animation(.smooth(duration: 0.25), value: security.isLocked)
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .background: security.lock()
                case .active: Task { await security.sceneDidBecomeActive() }
                default: break
                }
            }
    }
}
