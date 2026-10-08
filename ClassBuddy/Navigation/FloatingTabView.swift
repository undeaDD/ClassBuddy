import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Seite liegt in der eigenen schwebenden Tab-Leiste (`FloatingTabView`, vor iOS 26).
    @Entry var usesFloatingTabBar = false
    /// Mitte des minimierten Tab-Knopfs (global), `nil` = Leiste nicht minimiert. Für `floatingBottomBar`.
    @Entry var floatingTabBarMinimizedCenterY: CGFloat?
    /// Oberkante der großen Tab-Leiste (global). `floatingBottomBar` bleibt darüber.
    @Entry var floatingTabBarTopY: CGFloat?
}

/// Navigation vor iOS 26 auf iPhone und iPad: Inhalt des aktiven Tabs plus eigene schwebende Tab-Leiste unten
/// (Hauptseiten + „Mehr“, wie `PhoneTabView`). Ohne Sidebar und obere Tab-Leiste auf dem iPad.
///
/// Speicher: Geladen ist nur der aktive Tab. Wer ihn verlässt, verwirft ihn samt Unterseiten;
/// beim Zurückkehren beginnt er wieder an der Wurzel.
struct FloatingTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppPreference.hidesTabLabels) private var hidesTabLabels = false
    @AppStorage(AppPreference.minimizesBarsOnScroll) private var minimizesBarsOnScroll = true
    /// „Mehr“ ist ausgewählt (Übersicht oder eine darin geöffnete Seite).
    @State private var isOnMore = false
    @State private var morePath: [AppTab] = []
    @State private var isMinimized = false
    @State private var minimizedCenterY: CGFloat?
    @State private var barTopY: CGFloat?
    @State private var isKeyboardVisible = false
    /// Untere Safe Area des Geräts (0 = Home-Button) für den Abstand der Leiste.
    @State private var bottomSafeArea: CGFloat = 0
    @State private var scroll = TabScrollController()
    @State private var visibility = FloatingTabBarVisibility()

    /// Ausgeblendet bei offener Tastatur und auf Seiten mit `hidesTabBar()`.
    private var isBarVisible: Bool { !isKeyboardVisible && !visibility.isHidden }

    private var selection: FloatingTabSlot {
        isOnMore ? .more : .tab(app.selectedTab)
    }

    var body: some View {
        content
            .environment(\.usesPhoneTabBar, true)
            .environment(\.usesFloatingTabBar, true)
            .environment(\.floatingTabBarMinimizedCenterY, isMinimized ? minimizedCenterY : nil)
            // Ohne Leiste (Tastatur offen) gibt es nichts, worüber die schwebende Leiste bleiben müsste.
            .environment(\.floatingTabBarTopY, isBarVisible ? barTopY : nil)
            .environment(visibility)
            // Die Leiste liegt über dem Inhalt. Platz dafür bekommen die Navigations-Stapel in UIKit
            // (`additionalSafeAreaInsets`, siehe `TabScrollReader`): SwiftUIs `safeAreaInset` erreicht
            // Listen und Web-Ansichten in einem NavigationStack vor iOS 26 nicht.
            .overlay(alignment: isMinimized ? .bottomLeading : .bottom) {
                ZStack {
                    if isBarVisible {
                        FloatingTabBar(
                            selection: selection,
                            isMinimized: isMinimized,
                            hidesTitles: hidesTabLabels,
                            addsBottomPadding: bottomSafeArea == 0,
                            select: select,
                            expand: { setMinimized(false) },
                            minimizedCenterY: $minimizedCenterY,
                            topY: $barTopY
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: visibility.isHidden)
            }
            .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) { bottomSafeArea = $0 }
            .background {
                TabScrollReader(
                    controller: scroll,
                    isEnabled: minimizesBarsOnScroll,
                    // Minimiert kein Platz: SwiftUI-Listen ignorieren Tipps auf Zeilen, die ganz im unteren
                    // Safe-Area-Bereich liegen, auch wenn dort nur noch der kleine Knopf links sitzt.
                    bottomInset: isBarVisible && !isMinimized
                        ? FloatingTabBar.reservedHeight(addsBottomPadding: bottomSafeArea == 0) : 0
                ) { setMinimized($0) }
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                // Nur die Bildschirmtastatur; die schmale Leiste einer Hardware-Tastatur zählt nicht.
                let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                if (frame?.height ?? 0) > 120 { setKeyboardVisible(true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                setKeyboardVisible(false)
            }
            .onChange(of: minimizesBarsOnScroll) { _, isOn in
                if !isOn { setMinimized(false) }
            }
            // Seiten, die von außen geöffnet werden (Kachel, Schnellaktion, Widget) und nicht
            // in der Leiste liegen, öffnen sich unter „Mehr“.
            .onChange(of: app.selectedTab, initial: true) { _, tab in
                if tab.isInTabBar {
                    if isOnMore { leaveMore() }
                } else {
                    isOnMore = true
                    if morePath.last != tab { morePath = [tab] }
                }
                setMinimized(false)
            }
            .onChange(of: morePath) { _, path in
                if let tab = path.last { app.open(tab) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if isOnMore {
            MoreView(path: $morePath)
        } else {
            NavigationStack {
                AppTabDestination(tab: app.selectedTab)
            }
            .id(TabStackKey(tab: app.selectedTab, generation: app.stackID(for: app.selectedTab)))
        }
    }

    private func select(_ slot: FloatingTabSlot) {
        guard slot != selection else {
            reselect()
            return
        }
        Haptics.selection()
        switch slot {
        case .more:
            // Tab-Leiste verlassen → deren Stack beim Zurückkehren wieder an der Wurzel.
            app.resetStack(of: app.selectedTab)
            isOnMore = true
        case .tab(let tab):
            if isOnMore { leaveMore() }
            app.open(tab)
        }
    }

    /// Aktiven Tab erneut antippen: aus einer Unterseite zurück zur Wurzel, sonst nach oben scrollen.
    private func reselect() {
        guard scroll.isShowingSubpage else {
            scroll.scrollToTop()
            return
        }
        if isOnMore {
            morePath = []
        } else {
            app.resetStack(of: app.selectedTab)
        }
    }

    /// „Mehr“ verlassen: beim nächsten Öffnen wieder die Übersicht statt der zuletzt geöffneten Seite.
    private func leaveMore() {
        isOnMore = false
        morePath = []
    }

    private func setKeyboardVisible(_ visible: Bool) {
        guard visible != isKeyboardVisible else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { isKeyboardVisible = visible }
    }

    private func setMinimized(_ minimized: Bool) {
        guard minimized != isMinimized else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { isMinimized = minimized }
    }
}

// MARK: - Leiste ausblenden

/// Seiten, die die eigene Tab-Leiste gerade ausblenden (z. B. Unterseiten der Einstellungen).
@MainActor @Observable
final class FloatingTabBarVisibility {
    private var hidingPages: Set<UUID> = []

    var isHidden: Bool { !hidingPages.isEmpty }

    func hide(for page: UUID) { hidingPages.insert(page) }
    func show(for page: UUID) { hidingPages.remove(page) }
}

extension View {
    /// Blendet die Tab-Leiste aus, solange diese Seite sichtbar ist (für Unterseiten): ab iOS 26 die
    /// System-Tab-Leiste, davor die eigene (`FloatingTabView`); der Inhalt reicht dann bis zum unteren Rand.
    func hidesTabBar() -> some View {
        modifier(HidesTabBar())
    }
}

private struct HidesTabBar: ViewModifier {
    /// Nur in `FloatingTabView` gesetzt (vor iOS 26).
    @Environment(FloatingTabBarVisibility.self) private var visibility: FloatingTabBarVisibility?
    @State private var page = UUID()

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.toolbar(.hidden, for: .tabBar)
        } else {
            content
                .onAppear { visibility?.hide(for: page) }
                .onDisappear { visibility?.show(for: page) }
        }
    }
}

/// Identität des Stacks: anderer Tab oder zurückgesetzt → neu aufbauen.
private struct TabStackKey: Hashable {
    let tab: AppTab
    let generation: Int
}

/// Eintrag der Leiste: Hauptseite oder „Mehr“.
enum FloatingTabSlot: Hashable {
    case tab(AppTab)
    case more

    static let all: [FloatingTabSlot] = AppTabSection.main.tabs.map(FloatingTabSlot.tab) + [.more]

    var title: String {
        switch self {
        case .tab(let tab): tab.title
        case .more: loc("Mehr")
        }
    }

    @MainActor
    var image: Image {
        switch self {
        case .tab(let tab): tab.symbol.image
        case .more: Image(icon: .moreHoriz)
        }
    }
}

// MARK: - Leiste

/// Schwebende Kapsel mit den Tabs. Minimiert nur noch ein runder Knopf mit dem aktiven Tab (links);
/// Antippen vergrößert wieder. Die Höhe bleibt gleich, damit der Inhalt beim Minimieren nicht springt.
private struct FloatingTabBar: View {
    let selection: FloatingTabSlot
    let isMinimized: Bool
    let hidesTitles: Bool
    let addsBottomPadding: Bool
    let select: (FloatingTabSlot) -> Void
    let expand: () -> Void
    @Binding var minimizedCenterY: CGFloat?
    @Binding var topY: CGFloat?

    @Namespace private var namespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    fileprivate static let barHeight: CGFloat = 62
    private static let topPadding: CGFloat = 6
    private static let homeButtonPadding: CGFloat = 10

    /// Platz, den die Leiste über der unteren Safe Area des Geräts belegt.
    static func reservedHeight(addsBottomPadding: Bool) -> CGFloat {
        topPadding + barHeight + (addsBottomPadding ? homeButtonPadding : 0)
    }
    private static let minimizedSize: CGFloat = 48

    /// Nur so groß wie das Sichtbare (kein Rahmen über die ganze Breite): Sonst nimmt die Leiste vor iOS 26
    /// auch neben dem minimierten Knopf Berührungen weg. Ausgerichtet wird in `FloatingTabView`.
    var body: some View {
        Group {
            if isMinimized {
                minimizedButton
                    .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
            } else {
                tabs
                    .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
            }
        }
        .frame(height: Self.barHeight)
        // Oberkante der Kapsel (bleibt beim Minimieren gleich, die Höhe ändert sich nicht).
        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }, action: { topY = $0 })
        .padding(.horizontal, 20)
        .padding(.top, Self.topPadding)
        // Geräte mit Home-Button: etwas Abstand zur Unterkante.
        .padding(.bottom, addsBottomPadding ? Self.homeButtonPadding : 0)
        .background { shortcuts }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(FloatingTabSlot.all, id: \.self) { slot in
                tabButton(slot)
            }
        }
        .padding(4)
        .frame(maxWidth: 520)
        .background { barBackground(Capsule()) }
    }

    private func tabButton(_ slot: FloatingTabSlot) -> some View {
        let isSelected = slot == selection
        return Button { select(slot) } label: {
            VStack(spacing: 2) {
                slot.image
                    .iconSize(hidesTitles ? 26 : 24)
                if !hidesTitles {
                    Text(slot.title)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slot.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // Große Schrift: langes Drücken zeigt Symbol und Titel groß (wie die System-Tab-Leiste).
        .accessibilityShowsLargeContentViewer {
            slot.image
            Text(slot.title)
        }
    }

    private var minimizedButton: some View {
        Button(action: expand) {
            selection.image
                .iconSize(24)
                .foregroundStyle(.tint)
                .frame(width: Self.minimizedSize, height: Self.minimizedSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .background { barBackground(Circle()) }
        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).midY }, action: { minimizedCenterY = $0 })
        .accessibilityLabel(selection.title)
        .accessibilityHint("Tab-Leiste einblenden")
        .accessibilityShowsLargeContentViewer {
            selection.image
            Text(selection.title)
        }
    }

    /// Material wie das Glas ab iOS 26; „Transparenz reduzieren“ → deckend, „Kontrast erhöhen“ → deutlicher Rand.
    private func barBackground(_ shape: some Shape) -> some View {
        let isHighContrast = contrast == .increased
        return shape
            .fill(reduceTransparency ? AnyShapeStyle(Color(.secondarySystemBackground)) : AnyShapeStyle(.regularMaterial))
            .overlay {
                shape.stroke(Color.primary.opacity(isHighContrast ? 0.35 : 0.08), lineWidth: isHighContrast ? 1 : 0.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    /// ⌘1 … ⌘4 (Hardware-Tastatur), auch bei minimierter Leiste.
    /// Unsichtbar und für VoiceOver verborgen (sonst gäbe es jeden Tab doppelt), nur für die Tastatur.
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(FloatingTabSlot.all.enumerated()), id: \.offset) { index, slot in
                Button(slot.title) { select(slot) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .accessibilityHidden(true)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }
}
