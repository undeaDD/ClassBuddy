import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Seite liegt in der eigenen schwebenden Tab-Leiste (`FloatingTabView`, vor iOS 26).
    @Entry var usesFloatingTabBar = false
    /// Mitte des minimierten Tab-Knopfs (global), `nil` = Leiste nicht minimiert. Für `floatingBottomBar`.
    @Entry var floatingTabBarMinimizedCenterY: CGFloat?
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
    @State private var isKeyboardVisible = false
    /// Untere Safe Area des Geräts (0 = Home-Button) für den Abstand der Leiste.
    @State private var bottomSafeArea: CGFloat = 0
    @State private var scroll = TabScrollController()

    private var selection: FloatingTabSlot {
        isOnMore ? .more : .tab(app.selectedTab)
    }

    var body: some View {
        content
            .environment(\.usesPhoneTabBar, true)
            .environment(\.usesFloatingTabBar, true)
            .environment(\.floatingTabBarMinimizedCenterY, isMinimized ? minimizedCenterY : nil)
            // Inhalt scrollt unter der Leiste durch, endet aber oberhalb (Safe Area).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isKeyboardVisible {
                    FloatingTabBar(
                        selection: selection,
                        isMinimized: isMinimized,
                        hidesTitles: hidesTabLabels,
                        addsBottomPadding: bottomSafeArea == 0,
                        select: select,
                        expand: { setMinimized(false) },
                        minimizedCenterY: $minimizedCenterY
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.bottom) { bottomSafeArea = $0 }
            .background {
                TabScrollReader(controller: scroll, isEnabled: minimizesBarsOnScroll) { setMinimized($0) }
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

    @Namespace private var namespace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private static let barHeight: CGFloat = 62
    private static let minimizedSize: CGFloat = 48

    var body: some View {
        HStack(spacing: 0) {
            if isMinimized {
                minimizedButton
                    .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                Spacer(minLength: 0)
            } else {
                tabs
                    .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        // Geräte mit Home-Button: etwas Abstand zur Unterkante.
        .padding(.bottom, addsBottomPadding ? 10 : 0)
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
    private var shortcuts: some View {
        ForEach(Array(FloatingTabSlot.all.enumerated()), id: \.offset) { index, slot in
            Button(slot.title) { select(slot) }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Scrollen (UIKit)

/// Verbindung zur gerade sichtbaren Seite in UIKit: Scrollrichtung beobachten, nach oben scrollen,
/// erkennen, ob eine Unterseite offen ist. SwiftUI meldet das vor iOS 18 nicht, daher für 17 und 18 gleich.
@MainActor
final class TabScrollController {
    fileprivate weak var host: TabScrollReader.ReaderController?

    /// Im sichtbaren Navigations-Stapel liegt mehr als die Wurzel.
    var isShowingSubpage: Bool {
        (host?.visibleNavigationController?.viewControllers.count ?? 0) > 1
    }

    func scrollToTop() {
        guard let scrollView = host?.primaryScrollView() else { return }
        let top = -scrollView.adjustedContentInset.top
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: top), animated: true)
    }
}

/// Prüft pro Frame (15–30 Hz) die größte senkrecht scrollbare Ansicht der sichtbaren Seite:
/// Runterscrollen minimiert die Leiste, Hochscrollen oder ganz oben vergrößert sie wieder.
/// Nur echte Gesten zählen (Ziehen, Ausrollen), kein Scrollen per Code.
private struct TabScrollReader: UIViewControllerRepresentable {
    let controller: TabScrollController
    let isEnabled: Bool
    let onMinimize: (Bool) -> Void

    func makeUIViewController(context: Context) -> ReaderController {
        let reader = ReaderController()
        controller.host = reader
        return reader
    }

    func updateUIViewController(_ reader: ReaderController, context: Context) {
        controller.host = reader
        reader.onMinimize = onMinimize
        reader.isEnabled = isEnabled
    }

    final class ReaderController: UIViewController {
        var onMinimize: (Bool) -> Void = { _ in }
        var isEnabled = false {
            didSet { if isEnabled != oldValue { updateDisplayLink() } }
        }

        private var displayLink: CADisplayLink?
        private weak var trackedScrollView: UIScrollView?
        private var tracker = TabBarScrollTracker()
        private var framesUntilRescan = 0

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateDisplayLink()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            displayLink?.invalidate()
            displayLink = nil
        }

        private func updateDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
            guard isEnabled, view.window != nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        /// Sichtbarster Navigations-Stapel im Inhalt (Tab oder „Mehr“); Sheets liegen nicht darin.
        var visibleNavigationController: UINavigationController? {
            guard let root = parent else { return nil }
            var stack = root.children
            var found: UINavigationController?
            while let candidate = stack.popLast() {
                if let navigation = candidate as? UINavigationController, navigation.viewIfLoaded?.window != nil {
                    found = navigation
                }
                stack.append(contentsOf: candidate.children)
            }
            return found
        }

        /// Größte sichtbare, senkrecht scrollbare Ansicht (Liste, ScrollView, Formular) – ohne Textfelder.
        func primaryScrollView() -> UIScrollView? {
            guard let root = parent?.view, let window = root.window else { return nil }
            var best: (view: UIScrollView, area: CGFloat)?
            var queue: [UIView] = [root]
            while let view = queue.popLast() {
                if view.isHidden || view.alpha < 0.01 { continue }
                if let scrollView = view as? UIScrollView, !(scrollView is UITextView), scrollView.isScrollEnabled,
                   Self.scrollableHeight(of: scrollView) > 40 {
                    let frame = scrollView.convert(scrollView.bounds, to: window).intersection(window.bounds)
                    let area = frame.isNull ? 0 : frame.width * frame.height
                    if area > (best?.area ?? 0) { best = (scrollView, area) }
                }
                queue.append(contentsOf: view.subviews)
            }
            return best?.view
        }

        private static func scrollableHeight(of scrollView: UIScrollView) -> CGFloat {
            let insets = scrollView.adjustedContentInset
            return scrollView.contentSize.height + insets.top + insets.bottom - scrollView.bounds.height
        }

        @objc private func tick() {
            // Die Seite kann wechseln (Tab, Unterseite): alle ~0,5 s neu suchen.
            if framesUntilRescan <= 0 || trackedScrollView?.window == nil {
                framesUntilRescan = 15
                let current = primaryScrollView()
                if current !== trackedScrollView {
                    trackedScrollView = current
                    if let current {
                        let (top, bottom) = Self.range(of: current)
                        tracker.reset(offset: current.contentOffset.y, top: top, bottom: bottom)
                    }
                    report(false)
                }
            }
            framesUntilRescan -= 1
            guard let scrollView = trackedScrollView else { return }
            let (top, bottom) = Self.range(of: scrollView)
            if let minimized = tracker.update(
                offset: scrollView.contentOffset.y, top: top, bottom: bottom,
                isUserScrolling: scrollView.isTracking || scrollView.isDecelerating
            ) {
                report(minimized)
            }
        }

        /// Kleinste und größte Scroll-Position (ohne Nachfedern).
        private static func range(of scrollView: UIScrollView) -> (top: CGFloat, bottom: CGFloat) {
            let top = -scrollView.adjustedContentInset.top
            return (top, top + max(0, scrollableHeight(of: scrollView)))
        }

        /// Jedes Mal melden: SwiftUI prüft selbst auf Änderung, und nach Antippen des
        /// minimierten Knopfs muss erneutes Runterscrollen wieder minimieren.
        private func report(_ minimized: Bool) {
            onMinimize(minimized)
        }
    }
}
