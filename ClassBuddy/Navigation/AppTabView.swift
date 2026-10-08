import SwiftUI

/// Hauptnavigation. Ab iOS 26 die System-Tab-Leiste (`NativeTabView`), davor auf iPhone und iPad
/// die eigene schwebende Leiste unten (`FloatingTabView`).
/// Aufbau fest (nicht anpassbar): Hauptseiten ohne Titel, dann „Klasse“ und „Sonstige“.
/// Neue Seiten: Case in `AppTab` ergänzen und in `AppTabDestination` zuordnen.
struct AppTabView: View {
    /// Nur nötig, damit `defaultVisibility` greift; Anpassen selbst ist überall gesperrt.
    /// Versioniert: bei Strukturänderungen hochzählen. v6: feste Gruppen, kein Anordnen.
    static let customizationKey = "navigation.tabCustomization.v6"

    var body: some View {
        if #available(iOS 26, *) {
            NativeTabView()
        } else {
            FloatingTabView()
        }
    }
}

/// Ab iOS 26: oben Tab-Bar, links einklappbare Sidebar (iPad).
/// Schmale Fenster (iPhone, kleines iPad-Fenster): `PhoneTabView` mit eigenem „Mehr“-Tab.
@available(iOS 26, *)
private struct NativeTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Environment(\.device) private var device
    @AppStorage(AppTabView.customizationKey) private var customization = TabViewCustomization()
    /// iPad: auf Wunsch die Tab-Leiste des iPhones (App-Einstellungen → Darstellung).
    @AppStorage(AppPreference.padUsesPhoneTabBar) private var padUsesPhoneTabBar = false

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
        if device.isPhone || (padUsesPhoneTabBar && UIDevice.current.userInterfaceIdiom == .pad) {
            PhoneTabView()
        } else {
            padTabView
        }
    }

    private var padTabView: some View {
        TabView(selection: selection) {
            // Hauptseiten ohne Gruppentitel, auch oben in der Tab-Leiste.
            ForEach(AppTabSection.main.tabs) { tab in
                padTabItem(tab)
            }
            ForEach(AppTabSection.titled) { section in
                TabSection(section.title) {
                    ForEach(section.tabs) { tab in
                        padTabItem(tab)
                    }
                }
                .customizationID(section.customizationID)
                // Gruppentitel nur in der Sidebar, nie als eigener Eintrag in der Tab-Leiste.
                .defaultVisibility(.hidden, for: .tabBar)
                .customizationBehavior(.disabled, for: .sidebar, .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // Standard: Tab-Bar oben; Sidebar lässt sich über den Button oben links einblenden.
        .defaultAdaptableTabBarPlacement(.tabBar)
        .tabViewCustomization($customization)
    }

    /// Oben nur Übersicht + Kalender (plus der aktive Tab); nichts ist verschieb- oder ausblendbar.
    private func padTabItem(_ tab: AppTab) -> some TabContent<AppTab> {
        tabItem(tab)
            .defaultVisibility(tab.isInPadTabBar ? .visible : .hidden, for: .tabBar)
            .customizationBehavior(.disabled, for: .sidebar, .tabBar)
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
            AppTabDestination(tab: tab)
        }
        // Neu aufbauen, nachdem der Tab verlassen wurde → wieder an der Wurzel.
        .id(app.stackID(for: tab))
    }

    private func perform(_ tab: AppTab) {
        tab.performAction(openURL)
    }
}

/// Inhalt eines Tabs (ohne eigenen NavigationStack).
struct AppTabDestination: View {
    let tab: AppTab

    var body: some View {
        switch tab {
        case .dashboard: DashboardView()
        case .calendar: CalendarView()
        case .students: StudentsView()
        case .rooms: RoomsView()
        case .board: BoardView()
        case .checklists: ChecklistsView()
        case .notes: NotesView()
        case .settings: SettingsView()
        case .feedback: EmptyView()
        }
    }
}

extension AppTab {
    /// Aktion eines Aktions-Tabs (`isAction`) auslösen.
    func performAction(_ openURL: OpenURLAction) {
        switch self {
        case .feedback: openURL(AppInfo.feedbackMailURL)
        default: break
        }
    }
}
