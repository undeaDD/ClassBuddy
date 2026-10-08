import SwiftUI
import UIKit
import WebKit

/// `WKWebView` für lokale HTML-Seiten vor iOS 26: ohne JavaScript, Cookies und Zoom, durchsichtig
/// (Hintergrund kommt aus SwiftUI). http(s)-, Mail- und Telefon-Links öffnen außerhalb der App.
struct LegacyHTMLView: UIViewRepresentable {
    let html: String
    let baseURL: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.dataDetectorTypes = []
        // Erst zeigen, wenn die Seite fertig ist (kein Aufblitzen).
        configuration.suppressesIncrementalRendering = true

        let webView = PageWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Kein seitliches Scrollen/Zoomen auf den Textseiten.
        webView.scrollView.delegate = context.coordinator
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate {
        var loadedHTML: String?

        private static let externalSchemes: Set<String> = ["http", "https", "mailto", "tel"]

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased(),
                  Self.externalSchemes.contains(scheme)
            else { return .allow }
            await UIApplication.shared.open(url)
            return .cancel
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            nil
        }
    }

    /// Meldet ihre Scroll-Ansicht der Seite, damit die Navigationsleiste beim Scrollen
    /// (wie bei Listen) von durchsichtig zu Milchglas wechselt.
    final class PageWebView: WKWebView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var responder: UIResponder? = self
            while let current = responder {
                if let page = current as? UIViewController, page.parent is UINavigationController {
                    page.setContentScrollView(scrollView, for: .top)
                    return
                }
                responder = current.next
            }
        }
    }
}
