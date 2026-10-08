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
    case room = "stat.room"
    case noiseMeter = "tool.noiseMeter"
    case groups = "tool.groups"
    case lastBoard = "stat.lastBoard"
    case secretariat = "tool.secretariat"
    case checklists = "tool.checklists"
    case holidays = "stat.holidays"
    case attendance = "stat.attendance"
    case quickNote = "tool.quickNote"

    var id: String { rawValue }

    var isHiddenByDefault: Bool {
        switch self {
        case .students, .nextLesson: false
        case .nextBirthday, .randomStudent, .timer, .currentLesson, .dateTime, .weather, .weeklyHours, .dailyBoost, .room,
             .noiseMeter, .groups, .lastBoard, .secretariat, .checklists, .holidays, .attendance, .quickNote: true
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
        case .timer: loc("Timer & Stoppuhr")
        case .currentLesson: loc("Aktuelle Stunde")
        case .dateTime: loc("Datum & Uhrzeit")
        case .weather: loc("Wetter")
        case .weeklyHours: loc("Wochenstunden")
        case .dailyBoost: loc("Tagesmotivation")
        case .room: loc("Aktueller Raum")
        case .noiseMeter: loc("Lautstärke")
        case .groups: loc("Gruppen")
        case .lastBoard: loc("Letztes Tafelbild")
        case .secretariat: loc("Sekretariat")
        case .checklists: loc("Checklisten")
        case .holidays: loc("Ferien")
        case .attendance: loc("Anwesenheit")
        case .quickNote: loc("Schnellnotiz")
        }
    }

    var summary: String {
        switch self {
        case .students: loc("Anzahl und Geschlechterverteilung der Klasse.")
        case .nextLesson: loc("Wann Sie die Klasse als Nächstes haben – öffnet den Kalender.")
        case .nextBirthday: loc("Wer als Nächstes Geburtstag hat und wie alt er oder sie wird.")
        case .randomStudent: loc("Antippen wählt zufällig eine Schülerin oder einen Schüler aus.")
        case .timer: loc("Countdown für Arbeitsphasen mit Ton und Mitteilung am Ende – oder Stoppuhr.")
        case .currentLesson: loc("Restzeit der laufenden Stunde in Stunden und Minuten.")
        case .dateTime: loc("Uhrzeit, Wochentag, Datum und Kalenderwoche.")
        case .weather: loc("Aktuelles Wetter am Schulort (Ort aus den Schuleinstellungen).")
        case .weeklyHours: loc("Wie viel Ihres Unterrichts diese Woche schon geschafft ist.")
        case .dailyBoost: loc("Ein Glückskeks-Spruch für den Tag, lokal mit Apple Intelligence – antippen für einen neuen.")
        case .room: loc("Raum der laufenden bzw. nächsten Stunde – öffnet den Sitzplan.")
        case .noiseMeter: loc("Lautstärke-Ampel über das Mikrofon – antippen zum Ein- und Ausschalten. Es wird nichts aufgenommen.")
        case .groups: loc("Teilt die Klasse zufällig in Gruppen ein – nach Gruppengröße oder Anzahl, mit PDF zum Drucken.")
        case .lastBoard: loc("Vorschau des neuesten Tafelbilds der Klasse – öffnet den Tab „Tafelbild“ mit dem Fach.")
        case .secretariat: loc("Sekretariat anrufen oder anschreiben – Nummer und Adresse aus den Schuleinstellungen.")
        case .checklists: loc("Fortschritt der zuletzt bearbeiteten Checkliste – öffnet sie direkt.")
        case .holidays: loc("Wie viele Schultage es noch bis zu den nächsten Ferien sind.")
        case .attendance: loc("Wer heute fehlt oder zu spät kam (aus dem Sitzplan) – öffnet den Sitzplan.")
        case .quickNote: loc("Eine kurze Notiz zur Klasse, z. B. „Hefte einsammeln“ – antippen zum Bearbeiten.")
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
        case .room: AppTab.rooms.symbol
        case .noiseMeter: .custom(.volume)
        case .groups: AppTab.students.symbol
        case .lastBoard: AppTab.board.symbol
        case .secretariat: .custom(.bank)
        case .checklists: AppTab.checklists.symbol
        case .holidays: .custom(.calendar)
        case .attendance: .custom(.userXmark)
        case .quickNote: .custom(.editPencil)
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
        case .dailyBoost: (loc("Der weise Lehrer hat einen Ersatzmarker. Der weisere hat zwei."), "")
        case .room: ("R 204", loc("Jetzt · 3. Stunde · 7b"))
        case .noiseMeter: (loc("58 dB"), loc("Angenehm ruhig"))
        case .groups: ("6 × 4", loc("Zuletzt heute um 09:12"))
        case .lastBoard: (loc("Mathematik"), loc("Heute um 09:35"))
        case .secretariat: (loc("Anrufen · E-Mail"), loc("Gymnasium am See"))
        case .checklists: ("18/24", loc("Name in die Bücher eingetragen"))
        case .holidays: (loc("12 Tage"), loc("Schultage bis Herbstferien"))
        case .attendance: ("22/24", loc("2 abwesend · 1 verspätet"))
        case .quickNote: (loc("Hefte einsammeln, Elternbrief zum Ausflug austeilen"), loc("Heute um 08:05"))
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

    var builtInCard: DashboardBuiltInCard? {
        if case .builtIn(let card) = self { card } else { nil }
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
                        .toolbarGroupBackground()
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
        case .builtIn(.secretariat):
            SecretariatCard(isPreview: true)
        case .builtIn(.checklists):
            ChecklistCardContent(title: loc("Name in die Bücher eingetragen"), done: 18, total: 24)
        case .builtIn(.lastBoard):
            BoardImageCard(subject: loc("Mathematik"), dateText: loc("Heute um 09:35")) {
                ImagePlaceholderBackground()
            }
        case .builtIn(.noiseMeter):
            NoiseMeterCardContent(value: loc("58 dB"), detail: NoiseLevel.Stage.calm.title, level: 58, stage: .calm)
        case .builtIn(.timer):
            TimerCardContent(remaining: "12:34", detail: loc("20 min · endet um 10:15"))
        case .builtIn(.quickNote):
            let card = DashboardBuiltInCard.quickNote
            QuickNoteCardContent(text: card.previewValue.value, detail: card.previewValue.detail)
        case .builtIn(.dateTime), .builtIn(.weather):
            // Ohne Aktion (wie die echten Kacheln): kein Pfeil.
            let card = template.builtInCard ?? .dateTime
            StatCard(title: card.title, value: card.previewValue.value, detail: card.previewValue.detail, symbol: card.symbol)
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

/// Bild-Kachel ohne echtes Bild (Galerie-Vorschau).
struct ImagePlaceholderCard: View {
    let title: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ImagePlaceholderBackground()
            Text(title)
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
                .padding(12)
        }
        .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
        .clipShape(cardShape)
    }
}

/// Platzhalter statt eines echten Bilds (Galerie-Vorschau): Verlauf in der Akzentfarbe mit Bild-Symbol.
struct ImagePlaceholderBackground: View {
    @Environment(\.appAccent) private var accent

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.55), accent.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(icon: .image)
                .iconSize(48)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
