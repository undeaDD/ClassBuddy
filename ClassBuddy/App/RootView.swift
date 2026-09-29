import SwiftData
import SwiftUI

/// Oberste View: Navigation + Privatsphäre-Modus + App-Sperre + Pencil-Aktionen.
struct RootView: View {
    @Environment(AppSecurity.self) private var security
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AppTabView()
            .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
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
            // TEMPORÄR (PoC): Geschlecht der Dummy-Schüler einmalig ergänzen – im nächsten Build entfernen.
            .task {
                DummyStudentsSeed.applyIfNeeded(context: modelContext)
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
