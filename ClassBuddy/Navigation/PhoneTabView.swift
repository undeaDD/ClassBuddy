import SwiftUI

/// Navigation für schmale Fenster (iPhone, kleines iPad-Fenster): Hauptseiten in der
/// Tab-Leiste plus eigener „Mehr“-Tab mit den Gruppen „Klasse“ und „Sonstige“.
///
/// Ersetzt den System-„Mehr“-Reiter, den iOS ab 6 Tabs einblendet: Der packt jede Seite
/// in einen zweiten Navigation-Controller (→ doppelte Navigationsleiste) und sieht veraltet aus.
struct PhoneTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(AppPreference.hidesTabLabels) private var hidesTabLabels = false
    @AppStorage(AppPreference.minimizesBarsOnScroll) private var minimizesBarsOnScroll = true
    /// „Mehr“ ist ausgewählt (Übersicht oder eine darin geöffnete Seite).
    @State private var isOnMore = false
    @State private var morePath: [AppTab] = []
    /// Wie `AppModel.stackID`, für den eigenen Stack der „Mehr“-Seite.
    @State private var moreStackID = 0

    private enum Slot: Hashable {
        case tab(AppTab)
        case more
    }

    private var selection: Binding<Slot> {
        Binding(
            get: { isOnMore ? .more : .tab(app.selectedTab) },
            set: { slot in
                switch slot {
                case .more:
                    guard !isOnMore else { return }
                    // Tab-Leiste verlassen → deren Stack beim Zurückkehren wieder an der Wurzel.
                    app.resetStack(of: app.selectedTab)
                    isOnMore = true
                case .tab(let tab):
                    if isOnMore { leaveMore() }
                    app.open(tab)
                }
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(AppTabSection.main.tabs) { tab in
                Tab(value: Slot.tab(tab)) {
                    NavigationStack {
                        AppTabDestination(tab: tab)
                    }
                    .id(app.stackID(for: tab))
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .environment(\.usesPhoneTabBar, true)
                } label: {
                    TabBarLabel(title: tab.title, image: tab.symbol.image, hidesTitle: hidesTabLabels)
                }
            }
            Tab(value: Slot.more) {
                MoreView(path: $morePath)
                    .id(moreStackID)
                    .environment(\.horizontalSizeClass, horizontalSizeClass)
                    .environment(\.usesPhoneTabBar, true)
            } label: {
                TabBarLabel(title: "Mehr", image: Image(icon: .moreHoriz), hidesTitle: hidesTabLabels)
            }
        }
        // iPad (App-Einstellung „iPhone-Tab-Leiste“): kompakt → echte Tab-Leiste unten statt oben.
        // Die Seiten selbst behalten die tatsächliche Größenklasse (s. o.).
        .environment(\.horizontalSizeClass, .compact)
        // Beim Runterscrollen auf den aktiven Tab schrumpfen, beim Hochscrollen wieder groß.
        .tabBarMinimizeBehavior(minimizesBarsOnScroll ? .onScrollDown : .never)
        // Seiten, die von außen geöffnet werden (z. B. Kachel auf der Übersicht),
        // aber nicht in der Tab-Leiste liegen, öffnen sich unter „Mehr“.
        .onChange(of: app.selectedTab, initial: true) { _, tab in
            if tab.isInTabBar {
                if isOnMore { leaveMore() }
            } else {
                isOnMore = true
                if morePath.last != tab { morePath = [tab] }
            }
        }
        .onChange(of: morePath) { _, path in
            if let tab = path.last { app.open(tab) }
        }
    }

    /// „Mehr“ verlassen: beim nächsten Öffnen wieder die Übersicht statt der zuletzt geöffneten Seite.
    private func leaveMore() {
        isOnMore = false
        morePath = []
        moreStackID += 1
    }
}

/// Eigene „Mehr“-Seite: alle Seiten außerhalb der Tab-Leiste, nach Gruppen einklappbar.
private struct MoreView: View {
    @Environment(\.openURL) private var openURL
    @Binding var path: [AppTab]
    @State private var collapsed: Set<AppTabSection> = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(AppTabSection.titled) { section in
                    Section {
                        if !collapsed.contains(section) {
                            ForEach(section.tabs) { row(for: $0) }
                        }
                    } header: {
                        sectionHeader(section)
                    }
                }
            }
            .navigationTitle("Mehr")
            .navigationSubtitle("Was möchten Sie als Nächstes tun?")
            .navigationDestination(for: AppTab.self) { tab in
                AppTabDestination(tab: tab)
            }
        }
    }

    private func sectionHeader(_ section: AppTabSection) -> some View {
        let isCollapsed = collapsed.contains(section)
        return Button {
            withAnimation {
                if isCollapsed { collapsed.remove(section) } else { collapsed.insert(section) }
            }
        } label: {
            HStack {
                Text(section.title)
                Spacer()
                Image(isCollapsed ? .navArrowRight : .navArrowDown)
                    .iconSize(14)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isCollapsed ? "Aufklappen" : "Zuklappen")
    }

    @ViewBuilder
    private func row(for tab: AppTab) -> some View {
        if tab.isAction {
            // Wie in den Einstellungen: öffnet außerhalb der App (Mail).
            Button {
                tab.performAction(openURL)
            } label: {
                HStack {
                    Label {
                        Text(tab.title).foregroundStyle(Color.primary)
                    } icon: {
                        tab.symbol.image
                    }
                    Spacer()
                    Image(icon: .arrowUpRight)
                        .iconSize(18)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
        } else {
            NavigationLink(value: tab) {
                Label(tab.title, symbol: tab.symbol)
            }
        }
    }
}

/// Tab-Symbol mit oder ohne Beschriftung (App-Einstellung); VoiceOver liest den Titel immer.
private struct TabBarLabel: View {
    let title: String
    let image: Image
    let hidesTitle: Bool

    var body: some View {
        if hidesTitle {
            image.accessibilityLabel(title)
        } else {
            Label { Text(title) } icon: { image }
        }
    }
}
