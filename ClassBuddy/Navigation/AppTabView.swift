import SwiftUI

/// Hauptnavigation: oben Tab-Bar, links einklappbare Sidebar.
/// Neue Seiten: Case in `AppTab` ergänzen und hier in `destination(for:)` zuordnen.
struct AppTabView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("navigation.tabCustomization") private var customization = TabViewCustomization()

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(value: tab) {
                    root(for: tab)
                } label: {
                    Label(tab.title, symbol: tab.symbol)
                }
                .customizationID(tab.customizationID)
                // Übersicht bleibt immer an erster Stelle.
                .customizationBehavior(tab == .dashboard ? .disabled : .automatic, for: .sidebar, .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Standard: Tab-Bar oben; Sidebar lässt sich über den Button oben links einblenden.
        .defaultAdaptableTabBarPlacement(.tabBar)
        .tabViewCustomization($customization)
    }

    /// Jeder Tab hat seinen eigenen NavigationStack + gemeinsame Toolbar.
    private func root(for tab: AppTab) -> some View {
        NavigationStack {
            destination(for: tab)
                .appChrome(tab: tab)
        }
    }

    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard: DashboardView()
        case .seating: SeatingView()
        }
    }
}
