import SwiftUI

/// Hauptnavigation: oben Tab-Bar, links einklappbare Sidebar.
/// Neue Seiten: Case in `AppTab` ergänzen und hier in `destination(for:)` zuordnen.
struct AppTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    /// Versioniert: bei Strukturänderungen (neue Tabs, Gruppen) hochzählen,
    /// damit alles an der Standardposition landet. v4: Gruppen nur in der Sidebar.
    static let customizationKey = "navigation.tabCustomization.v4"
    @AppStorage(AppTabView.customizationKey) private var customization = TabViewCustomization()

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
            // Übersicht + Kalender: eigenständig, immer (und als einzige) in der Tab-Leiste.
            ForEach(AppTab.topLevel) { tab in
                tabItem(tab)
                    .customizationBehavior(.disabled, for: .sidebar, .tabBar)
            }

            // Gruppen: nur in der Sidebar (einklappbar), nie in der Tab-Leiste.
            ForEach(AppTabSection.allCases) { section in
                TabSection(section.title) {
                    ForEach(section.tabs) { tab in
                        tabItem(tab)
                            .customizationBehavior(.disabled, for: .tabBar)
                            .defaultVisibility(.hidden, for: .tabBar)
                    }
                }
                .customizationID(section.customizationID)
                .customizationBehavior(.disabled, for: .tabBar)
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Standard: Tab-Bar oben; Sidebar lässt sich über den Button oben links einblenden.
        .defaultAdaptableTabBarPlacement(.tabBar)
        .tabViewCustomization($customization)
    }

    private func tabItem(_ tab: AppTab) -> some TabContent<AppTab> {
        Tab(value: tab) {
            root(for: tab)
        } label: {
            Label(tab.title, symbol: tab.symbol)
        }
        .customizationID(tab.customizationID)
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
        case .rooms: RoomsView()
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
