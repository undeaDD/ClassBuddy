import SwiftUI

/// Hauptnavigation: oben Tab-Bar, links einklappbare Sidebar mit Sektionen.
/// Nutzer können Tabs in der Sidebar umsortieren und per Drag & Drop
/// in die Tab-Bar ziehen („Bearbeiten“ in der Sidebar) – wird persistiert.
struct AppTabView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("navigation.tabCustomization") private var customization = TabViewCustomization()

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            ForEach(AppTab.tabBarTabs) { tab in
                Tab(value: tab) {
                    root(for: tab)
                } label: {
                    Label(tab.title, symbol: tab.symbol)
                }
                .customizationID(tab.customizationID)
                // Übersicht bleibt immer an erster Stelle.
                .customizationBehavior(tab == .dashboard ? .disabled : .automatic, for: .sidebar, .tabBar)
            }

            ForEach(AppTabSection.allCases) { section in
                TabSection {
                    ForEach(section.tabs) { tab in
                        Tab(value: tab) {
                            root(for: tab)
                        } label: {
                            Label(tab.title, symbol: tab.symbol)
                        }
                        .customizationID(tab.customizationID)
                    }
                } header: {
                    Text(section.title)
                }
                .customizationID(section.customizationID)
                .defaultVisibility(.hidden, for: .tabBar)
            }

            Tab(value: AppTab.settings) {
                root(for: .settings)
            } label: {
                Label(AppTab.settings.title, symbol: AppTab.settings.symbol)
            }
            .customizationID(AppTab.settings.customizationID)
            .defaultVisibility(.hidden, for: .tabBar)

            Tab(value: AppTab.search, role: .search) {
                root(for: .search)
            }
            .customizationID(AppTab.search.customizationID)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
    }

    /// Jeder Tab hat seinen eigenen NavigationStack + gemeinsame Toolbar.
    private func root(for tab: AppTab) -> some View {
        NavigationStack {
            destination(for: tab)
                .appChrome()
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard: DashboardView()
        case .seating: SeatingView()
        case .settings: SettingsView()
        case .search:
            EmptyStateView(
                title: "Suche",
                message: "Suche nach Schülern, Notizen und Terminen – folgt, sobald es Daten gibt.",
                symbol: .system("magnifyingglass"),
                badge: "In Arbeit"
            )
            .navigationTitle(AppTab.search.title)
        default: PlaceholderView(tab: tab)
        }
    }
}
