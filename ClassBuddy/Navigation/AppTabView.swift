import SwiftUI

/// Hauptnavigation: oben Tab-Bar, links einklappbare Sidebar.
/// Neue Seiten: Case in `AppTab` ergänzen und hier in `destination(for:)` zuordnen.
struct AppTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    /// Versioniert: bei Strukturänderungen (neue Tabs, Gruppen) hochzählen,
    /// damit alles an der Standardposition landet. v5: Allgemein-Gruppe mit Übersicht/Kalender.
    static let customizationKey = "navigation.tabCustomization.v5"
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
            ForEach(AppTabSection.allCases) { section in
                TabSection(section.title) {
                    ForEach(section.tabs) { tab in
                        tabItem(tab)
                            // Oben nur Übersicht + Kalender; alle anderen nur in der Sidebar.
                            .defaultVisibility(tab.isInTabBar ? .visible : .hidden, for: .tabBar)
                            // Übersicht bleibt immer an erster Stelle.
                            .customizationBehavior(tab == .dashboard ? .disabled : .automatic, for: .sidebar, .tabBar)
                    }
                }
                .customizationID(section.customizationID)
                // Gruppentitel nur in der Sidebar, nie als eigener Eintrag in der Tab-Leiste.
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
            // iPadOS färbt Sidebar-Symbole mit der Akzentfarbe und zeichnet sie beim Wechsel
            // nicht zuverlässig neu. Daher: nur der ausgewählte Tab bekommt ein Template-Symbol
            // (Akzentfarbe), alle anderen ein fest in Textfarbe gezeichnetes.
            Label {
                Text(tab.title)
            } icon: {
                tab == app.selectedTab ? tab.symbol.image : tab.symbol.fixedColorImage(.label)
            }
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
