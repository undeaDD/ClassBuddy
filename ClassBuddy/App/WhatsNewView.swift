import SwiftUI

/// „Neuigkeiten“ je Version (im Stil von WhatsNewKit, ohne Abhängigkeit).
/// Erscheint einmal nach jedem Update mit Eintrag in `releases`; jederzeit über Einstellungen → Aktionen.
enum WhatsNew {
    static let storageKey = "whatsNew.lastSeenVersion"

    struct Feature: Identifiable {
        let icon: AppIcon
        let title: String
        let text: String
        var id: String { title }
    }

    struct Release {
        let version: String
        let features: [Feature]
    }

    /// Neueste Version zuerst. Für ein Update einfach einen Eintrag mit der neuen Versionsnummer ergänzen.
    static var releases: [Release] {
        [
            Release(version: "1.0.0", features: [
                Feature(
                    icon: .community,
                    title: loc("Klassen und Schüler"),
                    text: loc("Klassen mit Fächern und Farben, Schülerlisten, Stundenplan und Termine an einem Ort.")
                ),
                Feature(
                    icon: .palette,
                    title: loc("Ganz nach Ihrem Geschmack"),
                    text: loc("Kacheln, Akzentfarbe, Icons und Start-Tab: Richten Sie die App so ein, wie Sie arbeiten.")
                ),
                Feature(
                    icon: .lock,
                    title: loc("Privat, offline, DSGVO-konform"),
                    text: loc("Kein Konto, keine Cloud: Alle Daten bleiben auf diesem Gerät, biometrisch geschützt.")
                ),
                Feature(
                    icon: .sendMail,
                    title: loc("Ihre Meinung zählt"),
                    text: loc("Fehlt etwas oder hakt es irgendwo? Schreiben Sie mir über „Feedback senden“.")
                ),
                Feature(
                    icon: .moreHoriz,
                    title: loc("Bald noch viel mehr"),
                    text: loc("Räume, Sitzpläne und vieles mehr sind schon in Arbeit.")
                ),
            ]),
        ]
    }

    /// Eintrag der installierten Version, falls vorhanden.
    static var current: Release? {
        releases.first { $0.version == AppInfo.shortVersion }
    }
}

/// Blatt mit den Neuerungen einer Version: Titel, Liste mit Icons, „Weiter“ unten.
struct WhatsNewView: View {
    let release: WhatsNew.Release
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Schließen", icon: .xmark, action: onFinish)
                            .toolbarGroupBackground()
                    }
                }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Neu in ClassBuddy")
                            .font(.largeTitle.bold())
                        Text("Version \(release.version)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(release.features) { feature in
                            row(feature)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            Button(action: onFinish) {
                Text("Weiter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .appGlassButtonStyle(prominent: true)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
        }
        .background(Color(.systemBackground))
        .softScrollEdges()
    }

    private func row(_ feature: WhatsNew.Feature) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(icon: feature.icon)
                .iconSize(30)
                .foregroundStyle(.tint)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    if let release = WhatsNew.releases.first {
        WhatsNewView(release: release) {}
    }
}
