import SwiftUI
import UIKit
import WebKit

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(OnboardingView.storageKey) private var hasCompletedOnboarding = false
    @State private var isWhatsNewPresented = false

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
                    Label("Mein Profil", icon: .userCircle)
                }
                NavigationLink {
                    SchoolSettingsView()
                } label: {
                    Label("Schuleinstellungen", icon: .bank)
                }
                NavigationLink {
                    AppSettingsView()
                } label: {
                    Label("App-Einstellungen", icon: .app)
                }
            } header: {
                Text("Kategorien")
            }

            Section("Aktionen") {
                Button {
                    hasCompletedOnboarding = false
                } label: {
                    SettingsActionLabel(title: loc("Einführung erneut anzeigen"), icon: .helpCircle)
                }
                if WhatsNew.releases.first != nil {
                    Button {
                        isWhatsNewPresented = true
                    } label: {
                        SettingsActionLabel(title: loc("Neuigkeiten erneut anzeigen"), icon: .version)
                    }
                }
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    ExternalLinkRow(
                        title: loc("Systemeinstellungen öffnen"),
                        icon: .settings,
                        url: url,
                        hint: loc("Öffnet die Einstellungen-App")
                    )
                }
            }

            #if DEBUG
            // Nicht auf den README-Screenshots (`scripts/screenshots.sh`).
            if !ScreenshotMode.isActive {
                Section("Entwicklung") {
                    NavigationLink {
                        DebugMenuView()
                    } label: {
                        Label("Debug-Menü", icon: .bug)
                    }
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
                ExternalLinkRow(title: "GitHub", icon: .githubCircle, url: AppInfo.sourceCodeURL)
                ExternalLinkRow(title: loc("Kaffee spendieren"), icon: .donate, url: AppInfo.donationURL)
                // Einfacher mailto-Link.
                ExternalLinkRow(
                    title: loc("Feedback senden"),
                    icon: .sendMail,
                    url: AppInfo.feedbackMailURL,
                    hint: loc("Öffnet die Mail-App")
                )
                // Antippen kopiert Version, OS-Version und Gerät (z. B. für Fehlerberichte).
                Button {
                    UIPasteboard.general.string = versionText
                    toasts.success(loc("Version in die Zwischenablage kopiert"))
                } label: {
                    LabeledContent {
                        Text(versionText)
                            .monospacedDigit()
                    } label: {
                        Label {
                            Text("Info").foregroundStyle(Color.primary)
                        } icon: {
                            Image(icon: .version)
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
        // Am Form, nicht an der Section: Modifier einer Section gehen an jede ihrer Zeilen
        // (dreimal dasselbe Sheet → Hänger beim Schließen und Scrollen).
        .sheet(isPresented: $isWhatsNewPresented) {
            // Immer die neueste Version, auch wenn die installierte (noch) keinen Eintrag hat.
            if let release = WhatsNew.releases.first {
                WhatsNewView(release: release) { isWhatsNewPresented = false }
                    .presentationSizing(.form)
            }
        }
        .appChrome(tab: .settings) {
            ShareLink(item: AppInfo.shareURL, subject: Text("ClassBuddy"), message: Text(AppInfo.shareMessage)) {
                Label("App teilen", icon: .shareIos)
            }
        }
    }
}

/// Link, der außerhalb der App öffnet (Safari bzw. Mail); Pfeil nach rechts oben wie bei iOS üblich.
private struct ExternalLinkRow: View {
    @Environment(\.openURL) private var openURL
    let title: String
    let icon: AppIcon
    let url: URL
    var hint = loc("Öffnet in Safari")

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack {
                Label {
                    Text(title).foregroundStyle(Color.primary)
                } icon: {
                    Image(icon: icon)
                }
                Spacer()
                Image(icon: .arrowUpRight)
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
                .modifier(SlowPulse())
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
            HeroChip(text: loc("Installiert am \(installDate.appFormatted(date: .abbreviated, time: .omitted))"))
        }
        if let installMethod {
            HeroChip(text: loc("über \(installMethod.displayName)"))
        }
    }
}

/// Langsames, endloses „Atmen“ des App-Icons im Hero.
private struct SlowPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator([false, true]) { view, isExpanded in
                view.scaleEffect(isExpanded ? 1.04 : 1)
            } animation: { _ in
                .easeInOut(duration: 2.2)
            }
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
    let icon: AppIcon
    var isDestructive = false
    var showsChevron = true
    /// Statt des Pfeils ein Ladeindikator.
    var isLoading = false

    var body: some View {
        HStack {
            Label {
                Text(title).foregroundStyle(isEnabled ? (isDestructive ? Color.red : Color.primary) : Color.secondary)
            } icon: {
                Image(icon: icon).foregroundStyle(
                    isEnabled ? (isDestructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tint)) : AnyShapeStyle(Color.secondary)
                )
            }
            Spacer()
            if isLoading {
                ProgressView()
            } else if showsChevron {
                Image(icon: .navArrowRight)
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
        case .imprint: loc("Impressum")
        case .privacy: loc("Datenschutz")
        case .licenses: loc("Lizenzen")
        case .collaborators: loc("Mitwirkende")
        }
    }

    /// Englisch: `<name>.en.html`, sonst die deutsche Fassung.
    var url: URL? {
        if AppLanguage.current.resolved == .english,
           let english = Bundle.main.url(forResource: "\(rawValue).en", withExtension: "html") {
            return english
        }
        return Bundle.main.url(forResource: rawValue, withExtension: "html")
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
                guard let url = document.url, var html = try? String(contentsOf: url, encoding: .utf8) else { return }
                html = Self.applyingAccent(to: html)
                // Ladefehler einer lokalen Datei: Seite bleibt leer, kein weiterer Umgang nötig.
                do {
                    for try await _ in page.load(html: html, baseURL: url.deletingLastPathComponent()) {}
                } catch {}
            }
    }
}

extension LegalDocumentView {
    /// Die HTML-Seiten haben das ClassBuddy-Braun fest in der CSS – durch die gewählte Akzentfarbe ersetzen.
    static func applyingAccent(to html: String) -> String {
        let value = UserDefaults.standard.string(forKey: AppAccent.storageKey) ?? AppAccent.defaultValue
        guard value != AppAccent.defaultValue else { return html }
        let light = AppAccent.cssHex(for: value, dark: false)
        let dark = AppAccent.cssHex(for: value, dark: true)
        return html
            .replacingOccurrences(of: "--accent: #9c6830;", with: "--accent: \(light);")
            .replacingOccurrences(of: "--pill: rgba(156, 104, 48, 0.12);", with: "--pill: \(light)1f;")
            .replacingOccurrences(of: "--accent: #cd9c5e;", with: "--accent: \(dark);")
            .replacingOccurrences(of: "--pill: rgba(205, 156, 94, 0.16);", with: "--pill: \(dark)29;")
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
