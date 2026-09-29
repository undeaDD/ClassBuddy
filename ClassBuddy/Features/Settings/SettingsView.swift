import SwiftUI
import WebKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL

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
                linkRow("Quellcode auf GitHub", symbol: .system("chevron.left.forwardslash.chevron.right"), url: AppInfo.sourceCodeURL)
                linkRow("Spenden (PayPal)", symbol: .custom(.coinsSwap), url: AppInfo.donationURL)
                Button {
                    openURL(AppInfo.feedbackMailURL)
                } label: {
                    Label("Feedback senden", image: .sendMail)
                }
                LabeledContent {
                    Text(AppInfo.version)
                } label: {
                    Label("Version", systemImage: "number")
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

    /// Externer Link; ohne URL deaktiviert mit Hinweis „folgt“.
    @ViewBuilder
    private func linkRow(_ title: String, symbol: AppSymbol, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            LabeledContent {
                if url == nil { Text("folgt") }
            } label: {
                Label(title, symbol: symbol)
            }
        }
        .disabled(url == nil)
    }
}

/// Lokale HTML-Dateien in `Resources/Legal`.
enum LegalDocument: String, CaseIterable, Identifiable {
    case imprint
    case privacy
    case licenses

    var id: String { rawValue }

    var symbol: AppSymbol {
        switch self {
        case .imprint: .system("info.circle")
        case .privacy: .system("hand.raised")
        case .licenses: .system("doc.text")
        }
    }

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

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        WebView(url: document.url)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
