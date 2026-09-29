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
    case weeklyHours = "stat.weeklyHours"

    var id: String { rawValue }

    var isHiddenByDefault: Bool {
        switch self {
        case .students, .nextLesson: false
        case .nextBirthday, .randomStudent, .timer, .currentLesson, .dateTime, .weather, .weeklyHours: true
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
        case .weeklyHours: "Wochenstunden"
        }
    }

    var summary: String {
        switch self {
        case .students: "Anzahl und Geschlechterverteilung der Klasse."
        case .nextLesson: "Wann du die Klasse als Nächstes hast – öffnet den Kalender."
        case .nextBirthday: "Wer als Nächstes Geburtstag hat und wie alt er oder sie wird."
        case .randomStudent: "Antippen wählt zufällig eine Schülerin oder einen Schüler aus."
        case .timer: "Countdown für Arbeitsphasen, mit Ton und Mitteilung am Ende."
        case .currentLesson: "Restzeit der laufenden Stunde in Stunden und Minuten."
        case .dateTime: "Uhrzeit, Wochentag, Datum und Kalenderwoche."
        case .weather: "Aktuelles Wetter am Schulort (Ort aus den Schuleinstellungen)."
        case .weeklyHours: "Wie viel deines Unterrichts diese Woche schon geschafft ist."
        }
    }

    var symbol: AppSymbol {
        switch self {
        case .students: AppTab.students.symbol
        case .nextLesson: AppTab.calendar.symbol
        case .nextBirthday: .custom(.gift)
        case .randomStudent: .custom(.dice)
        case .timer: .custom(.timer)
        case .currentLesson: .system("hourglass")
        case .dateTime: .custom(.time)
        case .weather: .custom(.temperature)
        case .weeklyHours: .system("chart.bar.fill")
        }
    }

    /// Beispielwerte für die Vorschau in der Galerie.
    var previewValue: (value: String, detail: String) {
        switch self {
        case .students: ("24", "♀ 50 % · ♂ 46 % · ⚧ 4 %")
        case .nextLesson: ("Morgen", "3. Stunde, 09:50 · Mathematik")
        case .nextBirthday: ("Emma S.", "in 5 Tagen · wird 13")
        case .randomStudent: ("Leon F.", "Antippen für neue Auswahl")
        case .timer: ("12:34", "20 min · endet um 10:15")
        case .currentLesson: ("23 min", "3. Stunde · 7b · Mathematik")
        case .dateTime: ("08:15", "Dienstag, 29. September · KW 40")
        case .weather: ("17°", "Teilweise bewölkt · ↑ 19° ↓ 9°")
        case .weeklyHours: ("58 %", "14 h erledigt · 24 h gesamt")
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
    /// Keine Kachel: öffnet eine Mail mit einem Kachel-Wunsch.
    case request

    var id: String {
        switch self {
        case .builtIn(let card): card.rawValue
        case .photo: "photo"
        case .imageFile: "imageFile"
        case .document: "document"
        case .website: "website"
        case .shortcut: "shortcut"
        case .request: "request"
        }
    }

    /// Mehrfach hinzufügbar (eigene Inhalte).
    var isReusable: Bool {
        switch self {
        case .builtIn, .request: false
        default: true
        }
    }

    var title: String {
        switch self {
        case .builtIn(let card): card.title
        case .photo: "Bild aus „Fotos“"
        case .imageFile: "Bild aus „Dateien“"
        case .document: "Dokument"
        case .website: "Website"
        case .shortcut: "Kurzbefehl"
        case .request: "Kachel wünschen"
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
        case .request: "Dir fehlt eine Kachel? Schreib kurz, was sie zeigen soll."
        }
    }

    static let reusable: [CardTemplate] = [.photo, .imageFile, .document, .website, .shortcut]
}

/// Vollbild-Galerie „Kachel hinzufügen“ mit Beispielvorschauen.
struct CardGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    /// Bereits sichtbare eingebaute Kacheln – werden in der Galerie nicht angeboten.
    let visibleBuiltIns: Set<DashboardBuiltInCard>
    let onSelect: (CardTemplate) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 20)]

    private var availableBuiltIns: [CardTemplate] {
        DashboardBuiltInCard.allCases.filter { !visibleBuiltIns.contains($0) }.map(CardTemplate.builtIn)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    if !availableBuiltIns.isEmpty {
                        section(
                            "Für diese Klasse",
                            footer: "Jede dieser Kacheln gibt es einmal pro Klasse.",
                            templates: availableBuiltIns
                        )
                        Divider()
                    }
                    section("Eigene Kacheln", footer: "Beliebig oft hinzufügbar.", templates: CardTemplate.reusable)
                    Divider()
                    section("Fehlt etwas?", footer: "Wünsche gehen per Mail an den Entwickler.", templates: [.request])
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

    /// Ganze Kachel antippen = hinzufügen.
    private func tile(_ template: CardTemplate) -> some View {
        Button {
            onSelect(template)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                TemplatePreview(template: template)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.headline)
                        .lineLimit(1)
                    // Immer zwei Zeilen, damit alle Kacheln gleich hoch sind.
                    Text(template.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
                .padding(.horizontal, 10)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel("\(template.title) hinzufügen")
        .accessibilityHint(template.summary)
    }
}

/// Nicht interaktive Beispielkachel mit Dummy-Daten.
private struct TemplatePreview: View {
    let template: CardTemplate

    var body: some View {
        switch template {
        case .builtIn(.weeklyHours):
            WeeklyHoursCard(result: WeeklyWorkload.Result(doneMinutes: 14 * 60, totalMinutes: 24 * 60)) {}
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
        case .request:
            ContentCard(title: "Wunsch", symbol: .custom(.sendMail), heading: "Neue Kachel", detail: "Per Mail vorschlagen")
        }
    }
}
