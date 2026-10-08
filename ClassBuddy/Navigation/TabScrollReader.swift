import SwiftUI
import UIKit

// MARK: - Scrollen (UIKit)

/// Verbindung zur gerade sichtbaren Seite in UIKit: Scrollrichtung beobachten, nach oben scrollen,
/// erkennen, ob eine Unterseite offen ist. SwiftUI meldet das vor iOS 18 nicht, daher für 17 und 18 gleich.
@MainActor
final class TabScrollController {
    weak var host: TabScrollReader.ReaderController?

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
/// Außerdem bekommt jeder Navigations-Stapel unten Platz für die Leiste (`additionalSafeAreaInsets`):
/// Listen, Formulare und Web-Ansichten scrollen dann unter ihr durch und enden darüber.
struct TabScrollReader: UIViewControllerRepresentable {
    let controller: TabScrollController
    let isEnabled: Bool
    let bottomInset: CGFloat
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
        reader.bottomInset = bottomInset
        // Nach einem Tab-Wechsel entsteht der neue Stapel erst etwas später.
        reader.scheduleInsets()
    }

    final class ReaderController: UIViewController {
        var onMinimize: (Bool) -> Void = { _ in }
        var isEnabled = false {
            didSet { if isEnabled != oldValue { updateDisplayLink() } }
        }

        var bottomInset: CGFloat = 0 {
            didSet { if bottomInset != oldValue { applyInsets() } }
        }

        private var displayLink: CADisplayLink?
        private weak var trackedScrollView: UIScrollView?
        private var tracker = TabBarScrollTracker()
        private var framesUntilRescan = 0

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateDisplayLink()
            applyInsets()
        }

        func scheduleInsets() {
            for delay in [0.0, 0.15, 0.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.applyInsets() }
            }
        }

        /// Oberste Navigations-Stapel im Inhalt (Tab, „Mehr“); verschachtelte erben den Platz von ihnen.
        func applyInsets() {
            guard let root = parent else { return }
            var stack = root.children
            while let candidate = stack.popLast() {
                if let navigation = candidate as? UINavigationController {
                    if navigation.additionalSafeAreaInsets.bottom != bottomInset {
                        navigation.additionalSafeAreaInsets.bottom = bottomInset
                    }
                } else {
                    stack.append(contentsOf: candidate.children)
                }
            }
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
                applyInsets()
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
