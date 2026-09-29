import SwiftUI

/// Oberste View: Navigation + Privatsphäre-Modus + App-Sperre + Pencil-Aktionen.
struct RootView: View {
    @Environment(AppSecurity.self) private var security
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    var body: some View {
        AppTabView()
            .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
            // Gesperrt / im Hintergrund: Inhalt stark unscharf, darüber Milchglas.
            .blur(radius: security.isLocked || scenePhase != .active ? 28 : 0)
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
            .onChange(of: appearance, initial: true) { _, appearance in
                appearance.apply()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .background: security.lock()
                case .active: Task { await security.sceneDidBecomeActive() }
                default: break
                }
            }
    }
}
