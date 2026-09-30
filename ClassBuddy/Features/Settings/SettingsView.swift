import SwiftUI
import UIKit
import WebKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(ToastCenter.self) private var toasts

    private var versionText: String {
        "\(AppInfo.version) · \(UIDevice.current.systemVersion) · \(InstallInfo.shortDeviceModel)"
    }

    var body: some View {
        Form {
            Section {
                SettingsHero()
            }
            .listRowBackground(Color.clear)

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

            #if DEBUG
            Section("Entwicklung") {
                NavigationLink {
                    DebugMenuView()
                } label: {
                    Label("Debug-Menü", image: .bug)
                }
            }
            #endif

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
                ExternalLinkRow(title: "GitHub", image: .githubCircle, url: AppInfo.sourceCodeURL)
                ExternalLinkRow(title: "Kaffee spendieren", image: .donate, url: AppInfo.donationURL)
                // Einfacher mailto-Link.
                ExternalLinkRow(
                    title: "Feedback senden",
                    image: .sendMail,
                    url: AppInfo.feedbackMailURL,
                    hint: "Öffnet die Mail-App"
                )
                // Antippen kopiert Version, OS-Version und Gerät (z. B. für Fehlerberichte).
                Button {
                    UIPasteboard.general.string = versionText
                    toasts.success("Version in die Zwischenablage kopiert")
                } label: {
                    LabeledContent {
                        Text(versionText)
                            .monospacedDigit()
                    } label: {
                        Label {
                            Text("Info").foregroundStyle(Color.primary)
                        } icon: {
                            Image(.version)
                        }
                    }
                }
                .accessibilityHint("Kopiert die Versionsangaben")
            } header: {
                Text("Sonstiges")
            } footer: {
                Text("Made with ❤️ by Devsforge.de")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .navigationTitle(AppTab.settings.title)
        .appChrome(tab: .settings) {
            ShareLink(item: AppInfo.shareURL, subject: Text("ClassBuddy"), message: Text(AppInfo.shareMessage)) {
                Label("App teilen", image: .shareIos)
            }
        }
    }
}

/// Link, der außerhalb der App öffnet (Safari bzw. Mail); Pfeil nach rechts oben wie bei iOS üblich.
private struct ExternalLinkRow: View {
    @Environment(\.openURL) private var openURL
    let title: String
    let image: ImageResource
    let url: URL
    var hint = "Öffnet in Safari"

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack {
                Label {
                    Text(title).foregroundStyle(Color.primary)
                } icon: {
                    Image(image)
                }
                Spacer()
                Image(.arrowUpRight)
                    .iconSize(18)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .accessibilityHint(hint)
    }
}

/// Kopfbereich der Einstellungen: App-Icon, Name, Beschreibung, Installation.
private struct SettingsHero: View {
    @State private var installMethod: InstallInfo.Method?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(.appIconPreview)
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .accessibilityHidden(true)

            // Titel, Beschreibung und darunter linksbündig die Infos zur Installation.
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ClassBuddy")
                        .font(.title2.bold())
                    Text("Klassen, Schüler und Stundenplan – lokal und mit Face ID geschützt.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Chips nie umbrechen: nebeneinander, wenn es passt, sonst untereinander.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { chips }
                    VStack(alignment: .leading, spacing: 6) { chips }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .task { installMethod = await InstallInfo.detectMethod() }
    }

    @ViewBuilder
    private var chips: some View {
        if let installDate = InstallInfo.installDate {
            HeroChip(text: "Installiert am \(installDate.formatted(date: .abbreviated, time: .omitted))")
        }
        if let installMethod {
            HeroChip(text: "über \(installMethod.rawValue)")
        }
    }
}

private struct HeroChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.fill.tertiary, in: .capsule)
            .lineLimit(1)
            .fixedSize()
    }
}

/// Aktionszeile in Formularen: Text in Textfarbe (rot, wenn destruktiv), Icon in der Akzentfarbe
/// (bzw. rot) und rechts ein Pfeil, wenn die Aktion einen Dialog oder eine Unterseite öffnet.
struct SettingsActionLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let image: ImageResource
    var isDestructive = false
    var showsChevron = true
    /// Statt des Pfeils ein Ladeindikator.
    var isLoading = false

    var body: some View {
        HStack {
            Label {
                Text(title).foregroundStyle(isEnabled ? (isDestructive ? Color.red : Color.primary) : Color.secondary)
            } icon: {
                Image(image).foregroundStyle(isEnabled ? (isDestructive ? Color.red : Color.accentColor) : Color.secondary)
            }
            Spacer()
            if isLoading {
                ProgressView()
            } else if showsChevron {
                Image(.navArrowRight)
                    .iconSize(16)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
    }
}

/// Lokale HTML-Dateien in `Resources/Legal`.
nonisolated enum LegalDocument: String, CaseIterable, Identifiable {
    case imprint
    case privacy
    case licenses
    case collaborators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .imprint: "Impressum"
        case .privacy: "Datenschutz"
        case .licenses: "Lizenzen"
        case .collaborators: "Mitwirkende"
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
            // Kein seitliches Scrollen/Zoomen auf den lokalen Textseiten.
            .webViewMagnificationGestures(.disabled)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
