import SwiftUI

/// Oberste View: Navigation + Privatsphäre-Modus + App-Sperre + Pencil-Aktionen.
struct RootView: View {
    @Environment(AppSecurity.self) private var security
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    var body: some View {
        AppTabView()
            // Weiche Kanten für alle Scroll-Container (ScrollView, List, Form …).
            // Sheets, Popover und Vollbild-Cover erben das nicht → dort jeweils `.softScrollEdges()`.
            .softScrollEdges()
            .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
            // Gesperrt / im Hintergrund: Inhalt stark unscharf, darüber Milchglas.
            .blur(radius: security.isLocked || scenePhase != .active ? 12 : 0)
            .pencilQuickActions()
            .environment(\.device, Device(horizontalSizeClass: horizontalSizeClass))
            .overlay {
                if security.isLocked {
                    LockScreenView()
                        .transition(.opacity)
                } else if scenePhase != .active {
                    PrivacyCoverView()
                }
            }
            .animation(.smooth(duration: 0.25), value: security.isLocked)
            // Toasts über allem, auch über der Sperre (z. B. Fehlermeldungen beim Entsperren).
            .overlay(alignment: .top) { ToastOverlay() }
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

extension View {
    /// Weiche Scroll-Kanten für alle Scroll-Container darunter. Einmal in `RootView` und
    /// zusätzlich in jedem Sheet/Popover/Vollbild-Cover (die erben es nicht).
    func softScrollEdges() -> some View {
        scrollEdgeEffectStyle(.soft, for: .all)
    }
}
