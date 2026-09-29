import SwiftUI

/// Fest eingebaute Kacheln der Übersicht (je Klasse einmal vorhanden).
/// Neue Kacheln mit `isHiddenByDefault` starten im Bereich „Ausgeblendet“ und werden
/// über die Kachel-Galerie hinzugefügt (= eingeblendet).
enum DashboardBuiltInCard: String, CaseIterable, Identifiable {
    case students = "stat.students"
    case nextLesson = "stat.nextLesson"
    case nextBirthday = "stat.nextBirthday"
    case randomStudent = "tool.randomStudent"
    case timer = "tool.timer"
    case currentLesson = "stat.currentLesson"
    case dateTime = "tool.dateTime"
    case weather = "tool.weather"

    var id: String { rawValue }

    var isHiddenByDefault: Bool {
        switch self {
        case .students, .nextLesson: false
        case .nextBirthday, .randomStudent, .timer, .currentLesson, .dateTime, .weather: true
        }
    }

    var title: String {
        switch self {
        case .students: "Schüler"
        case .nextLesson: "Nächste Stunde"
        case .nextBirthday: "Nächster Geburtstag"
        case .randomStudent: "Zufallsauswahl"
        case .timer: "Timer"
        case .currentLesson: "Aktuelle Stunde"
        case .dateTime: "Datum & Uhrzeit"
        case .weather: "Wetter"
        }
    }

    var summary: String {
        switch self {
        case .students: "Anzahl und Geschlechterverteilung der Klasse."
        case .nextLesson: "Wann du die Klasse als Nächstes hast – öffnet den Kalender."
        case .nextBirthday: "Wer als Nächstes Geburtstag hat und wie alt er oder sie wird."
        case .randomStudent: "Antippen wählt zufällig eine Schülerin oder einen Schüler aus."
        case .timer: "Öffnet den Timer der Uhr-App."
        case .currentLesson: "Restzeit der laufenden Stunde in Stunden und Minuten."
        case .dateTime: "Uhrzeit, Wochentag, Datum und Kalenderwoche."
        case .weather: "Aktuelles Wetter am Schulort (Ort aus den Schuleinstellungen)."
        }
    }

    var symbol: AppSymbol {
        switch self {
        case .students: AppTab.students.symbol
        case .nextLesson: AppTab.calendar.symbol
        case .nextBirthday: .system("gift")
        case .randomStudent: .system("dice")
        case .timer: .system("timer")
        case .currentLesson: .system("hourglass")
        case .dateTime: .system("clock")
        case .weather: .system("cloud.sun")
        }
    }

    /// Beispielwerte für die Vorschau in der Galerie.
    var previewValue: (value: String, detail: String) {
        switch self {
        case .students: ("24", "♀ 50 % · ♂ 46 % · ⚧ 4 %")
        case .nextLesson: ("Morgen", "3. Stunde, 09:50 · Mathematik")
        case .nextBirthday: ("Emma S.", "in 5 Tagen · wird 13")
        case .randomStudent: ("Leon F.", "Antippen für neue Auswahl")
        case .timer: ("Starten", "Öffnet die Uhr-App")
        case .currentLesson: ("23 min", "3. Stunde · 7b · Mathematik")
        case .dateTime: ("08:15", "Dienstag, 29. September · KW 40")
        case .weather: ("17°", "Teilweise bewölkt · ↑ 19° ↓ 9° · Köln")
        }
    }
}

/// Eintrag der Kachel-Galerie.
enum CardTemplate: Identifiable, Hashable {
    case builtIn(DashboardBuiltInCard)
    case photo
    case imageFile
    case document
    case website
    case shortcut

    var id: String {
        switch self {
        case .builtIn(let card): card.rawValue
        case .photo: "photo"
        case .imageFile: "imageFile"
        case .document: "document"
        case .website: "website"
        case .shortcut: "shortcut"
        }
    }

    /// Mehrfach hinzufügbar (eigene Inhalte).
    var isReusable: Bool {
        if case .builtIn = self { false } else { true }
    }

    var title: String {
        switch self {
        case .builtIn(let card): card.title
        case .photo: "Bild aus „Fotos“"
        case .imageFile: "Bild aus „Dateien“"
        case .document: "Dokument"
        case .website: "Website"
        case .shortcut: "Kurzbefehl"
        }
    }

    var summary: String {
        switch self {
        case .builtIn(let card): card.summary
        case .photo: "Ein Foto aus deiner Mediathek, z. B. ein Tafelbild."
        case .imageFile: "Ein Bild aus der Dateien-App."
        case .document: "PDF, Arbeitsblatt oder jede andere Datei – öffnet sich in der Vorschau."
        case .website: "Link mit Website-Icon, z. B. Schulwebsite oder Vertretungsplan."
        case .shortcut: "Startet einen Kurzbefehl der Kurzbefehle-App, z. B. „Unterricht beginnt“."
        }
    }

    static let reusable: [CardTemplate] = [.photo, .imageFile, .document, .website, .shortcut]
}

/// Vollbild-Galerie „Kachel hinzufügen“ mit Beispielvorschauen.
struct CardGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    /// Bereits sichtbare eingebaute Kacheln (können nicht erneut hinzugefügt werden).
    let visibleBuiltIns: Set<DashboardBuiltInCard>
    let onSelect: (CardTemplate) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 20)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    section(
                        "Für diese Klasse",
                        footer: "Jede dieser Kacheln gibt es einmal pro Klasse.",
                        templates: DashboardBuiltInCard.allCases.map(CardTemplate.builtIn)
                    )
                    section(
                        "Eigene Kacheln",
                        footer: "Beliebig oft hinzufügbar.",
                        templates: CardTemplate.reusable
                    )
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kachel hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, footer: String, templates: [CardTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                Text(footer).font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(templates) { template in
                    tile(template)
                }
            }
        }
    }

    private func tile(_ template: CardTemplate) -> some View {
        let isAlreadyVisible: Bool = if case .builtIn(let card) = template { visibleBuiltIns.contains(card) } else { false }
        return VStack(alignment: .leading, spacing: 10) {
            TemplatePreview(template: template)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                Text(template.title).font(.headline)
                if template.isReusable {
                    Text("Mehrfach")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: .capsule)
                        .foregroundStyle(.tint)
                }
                Spacer()
            }
            Text(template.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onSelect(template)
                dismiss()
            } label: {
                Label(isAlreadyVisible ? "Bereits sichtbar" : "Hinzufügen", image: isAlreadyVisible ? .check : .plus)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isAlreadyVisible)
        }
    }
}

/// Nicht interaktive Beispielkachel mit Dummy-Daten.
private struct TemplatePreview: View {
    let template: CardTemplate

    var body: some View {
        switch template {
        case .builtIn(let card):
            StatCard(title: card.title, value: card.previewValue.value, detail: card.previewValue.detail, symbol: card.symbol) {}
        case .photo, .imageFile:
            ImagePlaceholderCard(title: "Tafelbild Montag")
        case .document:
            ContentCard(title: "Dokument", symbol: .custom(.page), heading: "Arbeitsblatt Brüche", detail: "Arbeitsblatt-Brueche.pdf")
        case .website:
            ContentCard(title: "Website", symbol: .custom(.www), heading: "Vertretungsplan", detail: "schule.de")
        case .shortcut:
            ContentCard(
                title: "Kurzbefehl", symbol: LinkCard.kindSymbol(.shortcut),
                heading: "Unterricht beginnt", detail: "Fokus an, Timer 45 min"
            )
        }
    }
}
