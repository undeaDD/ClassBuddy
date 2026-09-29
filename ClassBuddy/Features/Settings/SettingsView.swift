import SwiftUI
import UIKit
import WebKit

struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    TeacherProfileView()
                } label: {
                    Label("Mein Profil", image: .userCircle)
                }
                NavigationLink {
                    SchoolSettingsView()
                } label: {
                    Label("Schuleinstellungen", image: .bank)
                }
                NavigationLink {
                    AppSettingsView()
                } label: {
                    Label("App-Einstellungen", image: .app)
                }
            } header: {
                Text("Kategorien")
            }

            Section("Rechtliches") {
                ForEach(LegalDocument.allCases) { document in
                    NavigationLink {
                        LegalDocumentView(document: document)
                    } label: {
                        Label(document.title, symbol: document.symbol)
                    }
                }
            }

            Section {
                // Echte NavigationLinks → das System zeichnet den Chevron selbst.
                NavigationLink {
                    WebPageView(title: "Quellcode", url: AppInfo.sourceCodeURL)
                } label: {
                    Label("Quellcode auf GitHub", image: .githubCircle)
                }
                NavigationLink {
                    WebPageView(title: "Spenden", url: AppInfo.donationURL)
                } label: {
                    Label("Spenden (PayPal)", image: .donate)
                }
                NavigationLink {
                    FeedbackView()
                } label: {
                    Label("Feedback senden", image: .sendMail)
                }
                LabeledContent {
                    Text(AppInfo.version)
                } label: {
                    Label("App-Version", image: .version)
                }
            } footer: {
                Text("Made with ❤️ by Devsforge.de")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .navigationTitle(AppTab.settings.title)
        .appChrome(tab: .settings)
    }
}

/// Lokale HTML-Dateien in `Resources/Legal`.
nonisolated enum LegalDocument: String, CaseIterable, Identifiable {
    case imprint
    case privacy
    case licenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .imprint: "Impressum"
        case .privacy: "Datenschutz"
        case .licenses: "Lizenzen"
        }
    }

    var url: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: "html")
    }
}

@MainActor
extension LegalDocument {
    var symbol: AppSymbol { .custom(.link) }
}

/// Lokale HTML-Seite; Links nach außen öffnen in Safari statt in der App.
struct LegalDocumentView: View {
    let document: LegalDocument

    @State private var page = WebPage(navigationDecider: ExternalLinksInSafari())

    var body: some View {
        WebView(page)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard let url = document.url, let html = try? String(contentsOf: url, encoding: .utf8) else { return }
                // Ladefehler einer lokalen Datei: Seite bleibt leer, kein weiterer Umgang nötig.
                do {
                    for try await _ in page.load(html: html, baseURL: url.deletingLastPathComponent()) {}
                } catch {}
            }
    }
}

/// Erlaubt nur die lokale Seite; http(s)-Links gehen an Safari.
private struct ExternalLinksInSafari: WebPage.NavigationDeciding {
    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased()) else { return .allow }
        await UIApplication.shared.open(url)
        return .cancel
    }
}
