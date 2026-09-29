import SwiftUI
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
                    Label("App-Einstellungen", systemImage: "ipad")
                }
            } header: {
                Text("Weitere Einstellungen")
            } footer: {
                Text("Profil · Schule, Stundenraster, Ferien · Darstellung, App-Sperre, Daten.")
            }

            Section("Rechtliches") {
                ForEach(LegalDocument.allCases) { document in
                    NavigationLink(document.title) {
                        LegalDocumentView(document: document)
                    }
                }
            }

            Section {
                LabeledContent("Version", value: AppInfo.version)
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
enum LegalDocument: String, CaseIterable, Identifiable {
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

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        WebView(url: document.url)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
