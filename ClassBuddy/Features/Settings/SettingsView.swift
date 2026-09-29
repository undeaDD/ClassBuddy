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
                ActionRow("Quellcode auf GitHub", symbol: .custom(.githubCircle)) { openURL(AppInfo.sourceCodeURL) }
                ActionRow("Spenden (PayPal)", symbol: .custom(.donate)) { openURL(AppInfo.donationURL) }
                ActionRow("Feedback senden", symbol: .custom(.sendMail)) { openURL(AppInfo.feedbackMailURL) }
                LabeledContent {
                    Text(AppInfo.version)
                } label: {
                    Label("Version", image: .version)
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

/// Zeile, die eine Aktion auslöst (Link, Mail), optisch wie eine NavigationLink-Zeile:
/// farbiges Icon, normale Textfarbe, Chevron rechts.
private struct ActionRow: View {
    let title: String
    let symbol: AppSymbol
    let action: () -> Void

    init(_ title: String, symbol: AppSymbol, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(title).foregroundStyle(.primary)
                } icon: {
                    symbol.image
                }
                Spacer()
                Image(.navArrowRight)
                    .iconSize(14)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
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
        case .imprint, .privacy, .licenses: .custom(.link)
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
