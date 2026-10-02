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
    case dailyBoost = "tool.dailyBoost"

    var id: String { rawValue }

    var isHiddenByDefault: Bool {
        switch self {
        case .students, .nextLesson: false
        case .nextBirthday, .randomStudent, .timer, .currentLesson, .dateTime, .weather, .weeklyHours, .dailyBoost: true
        }
    }

    /// Auf diesem Gerät nutzbar (Tagesmotivation braucht Apple Intelligence); sonst nirgends angeboten.
    var isSupported: Bool {
        self == .dailyBoost ? DailyBoost.isAvailable : true
    }

    var title: String {
        switch self {
        case .students: loc("Schüler")
        case .nextLesson: loc("Nächste Stunde")
        case .nextBirthday: loc("Nächster Geburtstag")
        case .randomStudent: loc("Zufallsauswahl")
        case .timer: loc("Timer")
        case .currentLesson: loc("Aktuelle Stunde")
        case .dateTime: loc("Datum & Uhrzeit")
        case .weather: loc("Wetter")
        case .weeklyHours: loc("Wochenstunden")
        case .dailyBoost: loc("Tagesmotivation")
        }
    }

    var summary: String {
        switch self {
        case .students: loc("Anzahl und Geschlechterverteilung der Klasse.")
        case .nextLesson: loc("Wann Sie die Klasse als Nächstes haben – öffnet den Kalender.")
        case .nextBirthday: loc("Wer als Nächstes Geburtstag hat und wie alt er oder sie wird.")
        case .randomStudent: loc("Antippen wählt zufällig eine Schülerin oder einen Schüler aus.")
        case .timer: loc("Countdown für Arbeitsphasen, mit Ton und Mitteilung am Ende.")
        case .currentLesson: loc("Restzeit der laufenden Stunde in Stunden und Minuten.")
        case .dateTime: loc("Uhrzeit, Wochentag, Datum und Kalenderwoche.")
        case .weather: loc("Aktuelles Wetter am Schulort (Ort aus den Schuleinstellungen).")
        case .weeklyHours: loc("Wie viel Ihres Unterrichts diese Woche schon geschafft ist.")
        case .dailyBoost: loc("Ein fröhlicher Satz für den Tag, lokal mit Apple Intelligence – antippen für einen neuen.")
        }
    }

    var symbol: AppSymbol {
        switch self {
        case .students: AppTab.students.symbol
        case .nextLesson: AppTab.calendar.symbol
        case .nextBirthday: .custom(.gift)
        case .randomStudent: .custom(.dice)
        case .timer: .custom(.timer)
        case .currentLesson: .custom(.time)
        case .dateTime: .custom(.time)
        case .weather: .custom(.temperature)
        case .weeklyHours: .custom(.graphUp)
        case .dailyBoost: .custom(.quoteSolid)
        }
    }

    /// Beispielwerte für die Vorschau in der Galerie.
    var previewValue: (value: String, detail: String) {
        switch self {
        case .students: ("24", "♀ 50 % · ♂ 46 % · ⚧ 4 %")
        case .nextLesson: (loc("Morgen"), loc("3. Stunde, 09:50 · Mathematik"))
        case .nextBirthday: ("Emma S.", loc("in 5 Tagen · wird 13"))
        case .randomStudent: ("Leon F.", loc("Antippen für neue Auswahl"))
        case .timer: ("12:34", loc("20 min · endet um 10:15"))
        case .currentLesson: (loc("23 min"), loc("3. Stunde · 7b · Mathematik"))
        case .dateTime: ("08:15", loc("Dienstag, 29. September · KW 40"))
        case .weather: ("17°", loc("Teilweise bewölkt · ↑ 19° ↓ 9°"))
        case .weeklyHours: ("58 %", loc("14 h erledigt · 24 h gesamt"))
        case .dailyBoost: (loc("Irgendwo in Ihrer Klasse wartet heute ein Aha-Moment."), "")
        }
    }
}

/// Eintrag der Kachel-Galerie.
enum CardTemplate: Identifiable, Hashable {
    case builtIn(DashboardBuiltInCard)
    /// Galerie-Eintrag „Bild“: fragt per Menü nach der Quelle → `.photo` oder `.imageFile`.
    case image
    case photo
    case imageFile
    case document
    case website
    case shortcut
    case script
    /// Keine Kachel: öffnet eine Mail mit einem Kachel-Wunsch.
    case request

    var id: String {
        switch self {
        case .builtIn(let card): card.rawValue
        case .image: "image"
        case .photo: "photo"
        case .imageFile: "imageFile"
        case .document: "document"
        case .website: "website"
        case .shortcut: "shortcut"
        case .script: "script"
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
        case .image: loc("Bild")
        case .photo: loc("Bild aus „Fotos“")
        case .imageFile: loc("Bild aus „Dateien“")
        case .document: loc("Dokument")
        case .website: "Website"
        case .shortcut: loc("Kurzbefehl")
        case .script: loc("Programmierbar")
        case .request: loc("Kachel wünschen")
        }
    }

    var summary: String {
        switch self {
        case .builtIn(let card): card.summary
        case .image: loc("Ein Foto aus Ihrer Mediathek oder ein Bild aus der Dateien-App, z. B. ein Tafelbild.")
        case .photo: loc("Ein Foto aus Ihrer Mediathek, z. B. ein Tafelbild.")
        case .imageFile: loc("Ein Bild aus der Dateien-App.")
        case .document: loc("PDF, Arbeitsblatt oder jede andere Datei – öffnet sich in der Vorschau.")
        case .website: loc("Link mit Website-Icon, z. B. Schulwebsite oder Vertretungsplan.")
        case .shortcut: loc("Startet einen Kurzbefehl der Kurzbefehle-App, z. B. „Unterricht beginnt“.")
        case .script: loc("Titel, Wert und Antippen selbst in JavaScript schreiben – startet als Zähler.")
        case .request: loc("Ihnen fehlt eine Kachel? Schreiben Sie kurz, was sie zeigen soll.")
        }
    }

    static let reusable: [CardTemplate] = [.image, .document, .website, .shortcut, .script]
}

/// Vollbild-Galerie „Kachel hinzufügen“ mit Beispielvorschauen.
struct CardGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    /// Bereits sichtbare eingebaute Kacheln – werden in der Galerie nicht angeboten.
    let visibleBuiltIns: Set<DashboardBuiltInCard>
    let onSelect: (CardTemplate) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 20)]

    private var availableBuiltIns: [CardTemplate] {
        DashboardBuiltInCard.allCases.filter { $0.isSupported && !visibleBuiltIns.contains($0) }.map(CardTemplate.builtIn)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    if !availableBuiltIns.isEmpty {
                        section(
                            loc("Für diese Klasse"),
                            footer: loc("Jede dieser Kacheln gibt es einmal pro Klasse."),
                            templates: availableBuiltIns
                        )
                        Divider()
                    }
                    section(loc("Eigene Kacheln"), footer: loc("Beliebig oft hinzufügbar."), templates: CardTemplate.reusable)
                    Divider()
                    section(loc("Fehlt etwas?"), footer: loc("Wünsche gehen per Mail an den Entwickler."), templates: [.request])
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kachel hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
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

    /// Ganze Kachel antippen = hinzufügen; „Bild“ fragt vorher per Menü nach der Quelle.
    @ViewBuilder
    private func tile(_ template: CardTemplate) -> some View {
        if template == .image {
            Menu {
                Button("Aus „Fotos“", icon: .image) { select(.photo) }
                Button("Aus „Dateien“", icon: .page) { select(.imageFile) }
            } label: {
                tileLabel(template)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityLabel("\(template.title) hinzufügen")
            .accessibilityHint(template.summary)
        } else {
            Button {
                select(template)
            } label: {
                tileLabel(template)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityLabel("\(template.title) hinzufügen")
            .accessibilityHint(template.summary)
        }
    }

    private func select(_ template: CardTemplate) {
        onSelect(template)
        dismiss()
    }

    private func tileLabel(_ template: CardTemplate) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                TemplatePreview(template: template)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    // Immer zwei Zeilen, damit alle Kacheln gleich hoch sind.
                    Text(template.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
                .padding(.horizontal, 10)
            }
            .contentShape(.rect)
    }
}

/// Nicht interaktive Beispielkachel mit Dummy-Daten.
private struct TemplatePreview: View {
    let template: CardTemplate

    var body: some View {
        switch template {
        case .builtIn(.weeklyHours):
            WeeklyHoursCard(result: WeeklyWorkload.Result(doneMinutes: 14 * 60, totalMinutes: 24 * 60)) {}
        case .builtIn(.dailyBoost):
            DailyBoostCard(previewText: DashboardBuiltInCard.dailyBoost.previewValue.value)
        case .builtIn(let card):
            StatCard(title: card.title, value: card.previewValue.value, detail: card.previewValue.detail, symbol: card.symbol) {}
        case .image, .photo, .imageFile:
            ImagePlaceholderCard(title: loc("Gruppenfoto"))
        case .document:
            ContentCard(
                title: loc("Dokument"), symbol: .custom(.page),
                heading: loc("Arbeitsblatt Brüche"), detail: loc("Arbeitsblatt-Brueche.pdf")
            )
        case .website:
            ContentCard(title: loc("Website"), symbol: .custom(.www), heading: loc("Vertretungsplan"), detail: "schule.de")
        case .shortcut:
            ContentCard(
                title: loc("Kurzbefehl"), symbol: LinkCard.kindSymbol(.shortcut),
                heading: loc("Unterricht beginnt"), detail: loc("Fokus an, Timer 45 min")
            )
        case .script:
            StatCard(title: loc("Zähler"), value: "7", detail: loc("Klasse 7b · Antippen zählt hoch"), symbol: .custom(.code)) {}
        case .request:
            ContentCard(title: loc("Wunsch"), symbol: .custom(.sendMail), heading: loc("Neue Kachel"), detail: loc("Per Mail vorschlagen"))
        }
    }
}
