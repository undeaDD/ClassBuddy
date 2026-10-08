import SwiftUI
import UIKit

extension View {
    /// Schwebende Leiste unten über dem Inhalt (z. B. Blättern im Kalender, später Räume …).
    /// Mit iPhone-Tab-Leiste (iPhone, schmales iPad-Fenster, iPad mit Einstellung „iPhone-Tab-Leiste“)
    /// rutscht sie beim Minimieren der Tab-Leiste animiert in deren Zeile, neben den kleinen Knopf,
    /// und beim Vergrößern wieder hoch. iPad-Leiste oben mit Sidebar: bleibt fest 10 pt über der Unterkante.
    func floatingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(FloatingBottomBar(bar: bar()))
    }
}

extension EnvironmentValues {
    /// Seite liegt in der `PhoneTabView` (Tab-Leiste unten) – auch auf dem iPad, siehe `AppTabView`.
    @Entry var usesPhoneTabBar = false
}

private struct FloatingBottomBar<Bar: View>: ViewModifier {
    @Environment(\.usesPhoneTabBar) private var usesPhoneTabBar
    /// Eigene Tab-Leiste vor iOS 26: Sie meldet die Mitte ihres minimierten Knopfs selbst.
    @Environment(\.usesFloatingTabBar) private var usesFloatingTabBar
    @Environment(\.floatingTabBarMinimizedCenterY) private var floatingMinimizedCenterY
    let bar: Bar

    /// Abstand der Mitte des kleinen Tab-Knopfs unter der Unterkante der Seite; `nil` = nicht minimiert.
    @State private var minimizedButtonDepth: CGFloat?
    @State private var barHeight: CGFloat = 0
    /// Unterkante der Seite (global), nur für die eigene Tab-Leiste.
    @State private var contentMaxY: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                bar
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { barHeight = $0 }
                    .padding(.bottom, 10)
                    .offset(y: offset)
                    .animation(.smooth, value: depth)
            }
            .background {
                if usesPhoneTabBar && !usesFloatingTabBar {
                    TabBarMinimizationReader { minimizedButtonDepth = $0 }
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).maxY }, action: { contentMaxY = $0 })
            .onChange(of: usesPhoneTabBar) { minimizedButtonDepth = nil }
    }

    /// Minimiert: mittig auf Höhe des kleinen Knopfs (gemessen, da hochkant und quer verschieden).
    private var offset: CGFloat {
        guard usesPhoneTabBar, let depth else { return 0 }
        return 10 + depth + barHeight / 2
    }

    private var depth: CGFloat? {
        guard usesFloatingTabBar else { return minimizedButtonDepth }
        return floatingMinimizedCenterY.map { $0 - contentMaxY }
    }
}

/// Liest, ob die Tab-Leiste gerade minimiert ist – SwiftUI und UIKit melden das nicht.
/// Die `UITabBar` enthält eine Kapsel mit allen Tabs (breiteste Subview), die beim Minimieren
/// ausgeblendet wird, und einen kleinen runden Knopf, der dann übrig bleibt. Erkannt an der Form,
/// nicht an privaten Klassennamen (hochkant: 351 × 62 und 48 × 48, quer: 284 × 44 und 44 × 44).
/// Gemeldet wird, wie weit die Mitte des Knopfs unter der Unterkante der Seite liegt (`nil` = nicht minimiert).
/// Geprüft pro Frame, solange die Seite sichtbar ist; ohne passende Subviews gilt „nicht minimiert“.
private struct TabBarMinimizationReader: UIViewControllerRepresentable {
    let onChange: (CGFloat?) -> Void

    func makeUIViewController(context: Context) -> ReaderController { ReaderController() }

    func updateUIViewController(_ controller: ReaderController, context: Context) {
        controller.onChange = onChange
    }

    final class ReaderController: UIViewController {
        var onChange: (CGFloat?) -> Void = { _ in }
        private var displayLink: CADisplayLink?
        /// Zuletzt gemeldeter Wert; `.none` bis zur ersten Prüfung – dann wird in jedem Fall gemeldet.
        private var reported: CGFloat??

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            reported = .none
            displayLink?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(check))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func check() {
            guard let tabBar = tabBarController?.tabBar else { return }
            let depth = minimizedButtonDepth(in: tabBar).map { ($0 * 2).rounded() / 2 }
            guard reported != .some(depth) else { return }
            reported = .some(depth)
            onChange(depth)
        }

        private func minimizedButtonDepth(in tabBar: UITabBar) -> CGFloat? {
            let visible = tabBar.subviews.filter { $0.bounds.width > 0 && $0.bounds.height > 0 }
            guard let tabsCapsule = visible.max(by: { $0.bounds.width < $1.bounds.width }), tabsCapsule.isHidden,
                  let button = visible.first(where: { candidate in
                      candidate !== tabsCapsule && !candidate.isHidden
                          && abs(candidate.bounds.width - candidate.bounds.height) < 1 && candidate.bounds.width <= 60
                  })
            else { return nil }
            let center = tabBar.convert(CGPoint(x: button.frame.midX, y: button.frame.midY), to: view)
            return center.y - view.bounds.maxY
        }
    }
}

/// Segmentierte Auswahl als schwebende Leiste unten (mit `floatingBottomBar`), mit dem Daumen gut erreichbar.
struct FloatingSegmentedPicker<Value: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Value
    @ViewBuilder let content: Content

    var body: some View {
        Picker(title, selection: $selection) { content }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Nur so breit wie die Segmente – sonst reicht die Leiste über den minimierten Tab-Knopf.
            .fixedSize()
            .padding(6)
            .appGlassEffect(.regular.interactive(), in: .capsule)
    }
}
