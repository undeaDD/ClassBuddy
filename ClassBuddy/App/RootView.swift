import SwiftData
import SwiftUI

/// Oberste View: Navigation + Privatsphäre-Modus + App-Sperre + Pencil-Aktionen.
struct RootView: View {
    @Environment(AppModel.self) private var app
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
            // TEMPORÄR (PoC): Dummy-Schüler einmalig anlegen – im nächsten Build entfernen.
            .task(id: app.selectedClassID) {
                DummyStudentsSeed.seedIfNeeded(selectedClassID: app.selectedClassID, context: modelContext)
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
