import SwiftUI

/// Hauptnavigation: oben Tab-Bar, links einklappbare Sidebar.
/// Neue Seiten: Case in `AppTab` ergänzen und hier in `destination(for:)` zuordnen.
struct AppTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @AppStorage("navigation.tabCustomization") private var customization = TabViewCustomization()

    /// Aktions-Tabs (Feedback) lösen ihre Aktion aus, ohne die Auswahl zu ändern.
    private var selection: Binding<AppTab> {
        Binding(
            get: { app.selectedTab },
            set: { tab in
                if tab.isAction {
                    perform(tab)
                } else {
                    app.open(tab)
                }
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(value: tab) {
                    root(for: tab)
                } label: {
                    Label(tab.title, symbol: tab.symbol)
                }
                .customizationID(tab.customizationID)
                // Übersicht bleibt immer an erster Stelle.
                .customizationBehavior(tab == .dashboard ? .disabled : .automatic, for: .sidebar, .tabBar)
                .defaultVisibility(tab.isInTabBarByDefault ? .visible : .hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Standard: Tab-Bar oben; Sidebar lässt sich über den Button oben links einblenden.
        .defaultAdaptableTabBarPlacement(.tabBar)
        .tabViewCustomization($customization)
    }

    /// Jeder Tab hat seinen eigenen NavigationStack.
    /// Die gemeinsame Toolbar setzt jede Seite selbst per `.appChrome(tab:)`.
    private func root(for tab: AppTab) -> some View {
        NavigationStack {
            destination(for: tab)
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard: DashboardView()
        case .calendar: CalendarView()
        case .students: StudentsView()
        case .settings: SettingsView()
        case .feedback: EmptyView()
        }
    }

    private func perform(_ tab: AppTab) {
        switch tab {
        case .feedback: openURL(AppInfo.feedbackMailURL)
        default: break
        }
    }
}
