import SwiftData
import SwiftUI

/// Oberste View: Navigation + Privatsphäre-Modus + App-Sperre + Pencil-Aktionen.
struct RootView: View {
    @Environment(AppSecurity.self) private var security
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(OnboardingView.storageKey) private var hasCompletedOnboarding = false
    @AppStorage(AppPreference.keepsScreenAwake) private var keepsScreenAwake = false
    @Environment(\.openURL) private var openURL
    private let homeScreenActions = HomeScreenActionCenter.shared
    @Environment(AppModel.self) private var app
    #if DEBUG
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    #endif

    var body: some View {
        AppTabView()
            // Weiche Kanten für alle Scroll-Container (ScrollView, List, Form …).
            // Sheets, Popover und Vollbild-Cover erben das nicht → dort jeweils `.softScrollEdges()`.
            .softScrollEdges()
            .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
            // Gesperrt / im Hintergrund: Inhalt stark unscharf, darüber Milchglas.
            .blur(radius: security.isLocked || scenePhase != .active ? 12 : 0)
            .pencilQuickActions()
            // Gilt nur im Vordergrund – iOS setzt es im Hintergrund ohnehin außer Kraft.
            .onChange(of: keepsScreenAwake, initial: true) { _, isOn in
                UIApplication.shared.isIdleTimerDisabled = isOn
            }
            .environment(\.device, Device(horizontalSizeClass: horizontalSizeClass))
            // Einführung einmalig nach dem Entsperren (iPhone: Vollbild, iPad: Form-Sheet). Wird die App
            // dabei gesperrt, verschwindet sie und erscheint danach wieder – erledigt über „Los geht’s“ oder xmark.
            // Zwei getrennte Präsentationen statt if/else, damit die App beim Größenwechsel nicht neu aufgebaut wird.
            .fullScreenCover(isPresented: onboardingBinding(isPhone: true)) {
                OnboardingView { hasCompletedOnboarding = true }
            }
            .sheet(isPresented: onboardingBinding(isPhone: false)) {
                OnboardingView { hasCompletedOnboarding = true }
                    .presentationSizing(.form)
                    .interactiveDismissDisabled()
            }
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
            #if DEBUG
            .task { ScreenshotMode.prepare(app: app, context: modelContext, settings: settings) }
            #endif
            // Schnellaktion vom App-Icon: erst nach dem Entsperren ausführen.
            .onChange(of: homeScreenActions.pending == nil || security.isLocked, initial: true) { _, isWaiting in
                guard !isWaiting, let action = homeScreenActions.pending else { return }
                homeScreenActions.pending = nil
                perform(action)
            }
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

extension RootView {
    private func perform(_ action: HomeScreenAction) {
        switch action {
        case .calendar: app.open(.calendar)
        case .feedback: openURL(AppInfo.feedbackMailURL)
        }
    }

    private func onboardingBinding(isPhone: Bool) -> Binding<Bool> {
        Binding(
            get: {
                !hasCompletedOnboarding && !security.isLocked
                    && Device(horizontalSizeClass: horizontalSizeClass).isPhone == isPhone
            },
            set: { _ in }
        )
    }
}

extension View {
    /// Weiche Scroll-Kanten für alle Scroll-Container darunter. Einmal in `RootView` und
    /// zusätzlich in jedem Sheet/Popover/Vollbild-Cover (die erben es nicht).
    func softScrollEdges() -> some View {
        scrollEdgeEffectStyle(.soft, for: .all)
    }
}
