import ImageIO
import SwiftUI
import UIKit

// Kachel-Designs der Übersicht. Inhalte sind im Privatsphäre-Modus ausgeblendet.

let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
/// Einheitliche Höhe aller Kacheln; Inhalte passen sich an, nie umgekehrt.
let cardHeight: CGFloat = 150

/// Kennzahl-Kachel; antippen öffnet die zugehörige Seite.
struct StatCard: View {
    let title: String
    let value: String
    var detail: String?
    let symbol: AppSymbol
    /// Wert/Detail im Privatsphäre-Modus ausblenden (nicht bei Uhrzeit, Wetter …).
    var isSensitive = true
    /// Logo statt Symbol und Titel im Kopf, z. B. Apple Wetter (Pflicht-Quellenangabe von WeatherKit).
    var brand: CardBrand?
    /// Kleiner Zusatz direkt hinter dem Wert (z. B. Temperatur-Tendenz) samt VoiceOver-Text.
    var valueSuffix: (text: String, accessibilityLabel: String)?
    var action: (() -> Void)?

    var body: some View {
        // Ohne Aktion keine Schaltfläche: nicht ausgegraut, kein Hover, kein Pfeil.
        if let action {
            Button(action: Haptics.tapping(action)) { content }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title, symbol: symbol, showsChevron: action != nil, brand: brand)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .cardPrivacy(isSensitive)
                    if let valueSuffix {
                        Text(verbatim: valueSuffix.text)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(valueSuffix.accessibilityLabel)
                    }
                }
                .leadingAligned()
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .cardPrivacy(isSensitive)
                        .leadingAligned()
                }
            }
        }
        .cardStyle()
    }
}

/// Eigene Kachel: Dokument oder Website.
struct LinkCard: View {
    let link: DashboardLink
    let action: () -> Void

    var body: some View {
        Button(action: Haptics.tapping(action)) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(
                    title: Self.kindTitle(link.kind),
                    symbol: Self.kindSymbol(link.kind),
                    showsChevron: true,
                    // Favicons nur über https laden (App-Links haben keins).
                    faviconURL: link.kind == .website && link.url?.scheme == "https" ? link.url : nil
                )
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title.isEmpty ? link.detail : link.title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .cardPrivacy()
                        .leadingAligned()
                    Text(link.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .cardPrivacy()
                        .leadingAligned()
                }
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }
}

extension LinkCard {
    static func kindTitle(_ kind: DashboardLink.Kind) -> String {
        switch kind {
        case .website: "Website"
        case .shortcut: loc("Kurzbefehl")
        case .script: loc("Skript")
        case .file, .image: loc("Dokument")
        }
    }

    static func kindSymbol(_ kind: DashboardLink.Kind) -> AppSymbol {
        switch kind {
        case .website: .custom(.www)
        case .shortcut: .custom(.shortcuts)
        case .script: .custom(.code)
        case .file, .image: .custom(.page)
        }
    }
}

/// Eigene Kachel: Bild, randlos; optionaler Titel unten auf Material.
struct ImageCard: View {
    let link: DashboardLink
    let action: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: Haptics.tapping(action)) {
            // Feste Kartengröße; das Bild liegt als Overlay darüber (füllt, zentriert, beschnitten)
            // und beeinflusst die Höhe der Kachel damit nicht.
            Color(.secondarySystemGroupedBackground)
                .frame(maxWidth: .infinity)
                .frame(height: cardHeight)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .sensitiveBlur(radius: 24)
                    } else {
                        ProgressView()
                    }
                }
                .clipped()
                .overlay(alignment: .bottomLeading) { titleCapsule }
                .clipShape(cardShape)
                .contentShape(.hoverEffect, cardShape)
                .contentShape(.dragPreview, cardShape)
                .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .task(id: link.location) {
            guard let url = link.url else { return }
            thumbnail = await Task.detached { Thumbnail.make(from: url, maxPixelSize: 900) }.value
        }
    }

    @ViewBuilder
    private var titleCapsule: some View {
        if !link.title.isEmpty {
            Text(link.title)
                .font(.headline)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
                .padding(12)
                .cardPrivacy()
        }
    }
}

/// Einfache Inhalts-Kachel (Überschrift + Detail), z. B. für Vorschauen in der Galerie.
struct ContentCard: View {
    let title: String
    let symbol: AppSymbol
    let heading: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title, symbol: symbol, showsChevron: true)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading).font(.title2.weight(.bold)).lineLimit(2)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .cardStyle()
    }
}

/// Zufallsauswahl: antippen wählt eine Schülerin / einen Schüler der Klasse.
struct RandomStudentCard: View {
    @Environment(\.redactionReasons) private var redactionReasons
    let students: [Student]

    @State private var picked: Student?

    var body: some View {
        StatCard(
            title: DashboardBuiltInCard.randomStudent.title,
            value: picked.map(Self.shortName) ?? "?",
            detail: students.isEmpty
                ? loc("Noch keine Schüler")
                : (picked == nil ? loc("Antippen zum Auswählen") : loc("Antippen für neue Auswahl")),
            symbol: DashboardBuiltInCard.randomStudent.symbol
        ) {
            pick()
        }
        .id(picked?.id)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func pick() {
        // Im Privatsphäre-Modus nicht neu auslosen (Name bleibt ohnehin verborgen).
        guard !redactionReasons.contains(.privacy) else { return }
        // Nicht zweimal hintereinander dieselbe Person.
        let candidates = students.count > 1 ? students.filter { $0.id != picked?.id } : students
        withAnimation(.bouncy) { picked = candidates.randomElement() }
        FunStat.randomPicks.increment()
    }

    static func shortName(_ student: Student) -> String {
        [student.firstName, student.lastName.first.map { "\($0)." }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Aktuelle Stunde: Restzeit (Stunden + Minuten) der laufenden Stunde, sonst Hinweis.
struct CurrentLessonCard: View {
    let schedule: LessonSchedule
    let visibleWeekdays: [Int]
    let action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let state = currentState(at: context.date)
            StatCard(
                title: DashboardBuiltInCard.currentLesson.title,
                value: state.value,
                detail: state.detail,
                symbol: DashboardBuiltInCard.currentLesson.symbol,
                action: action
            )
        }
    }

    private func currentState(at now: Date) -> (value: String, detail: String) {
        LessonProgress.state(schedule: schedule, visibleWeekdays: visibleWeekdays, now: now)
    }
}

/// Wochenstunden: Fortschrittsbalken (Primärfarbe) mit erledigten und gesamten Stunden.
struct WeeklyHoursCard: View {
    @Environment(\.redactionReasons) private var redactionReasons
    let result: WeeklyWorkload.Result
    var action: (() -> Void)?

    var body: some View {
        Button(action: Haptics.tapping { action?() }) {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(
                    title: DashboardBuiltInCard.weeklyHours.title,
                    symbol: DashboardBuiltInCard.weeklyHours.symbol,
                    showsChevron: action != nil
                )
                Spacer(minLength: 0)
                if result.totalMinutes == 0 {
                    Text("Keine Stunden im Kalender")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    // Prozentwert, darunter der Balken mit den Stunden mittig darin: gleiche Höhe wie alle Kacheln.
                    Text(result.fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .cardPrivacy()
                        .leadingAligned()
                    // Im Privatsphäre-Modus leerer Balken ohne Text (verrät nichts über den Stundenplan).
                    let isPrivate = redactionReasons.contains(.privacy)
                    CapsuleProgressBar(
                        value: isPrivate ? 0 : result.fraction,
                        label: isPrivate ? "" : loc("\(WeeklyWorkload.hours(result.doneMinutes)) von \(WeeklyWorkload.hours(result.totalMinutes))")
                    )
                }
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .disabled(action == nil)
    }
}

/// „+“-Kachel am Ende des Grids.
struct AddCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: Haptics.tapping(action)) {
            VStack(spacing: 8) {
                Image(icon: .plus).iconSize(36)
                Text("Kachel hinzufügen")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .overlay(cardShape.strokeBorder(.tint.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .contentShape(.hoverEffect, cardShape)
            .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }
}

struct CardHeader: View {
    let title: String
    let symbol: AppSymbol
    let showsChevron: Bool
    /// Bei Websites: Favicon statt Symbol.
    var faviconURL: URL?
    /// Ersetzt Symbol und Titel (siehe `StatCard.brand`).
    var brand: CardBrand?

    var body: some View {
        HStack {
            if let brand {
                CardBrandMark(brand: brand)
            } else if let faviconURL {
                Label {
                    Text(title)
                } icon: {
                    // Favicon verrät die Website → im Privatsphäre-Modus unscharf.
                    FaviconView(url: faviconURL, size: 24, placeholder: symbol)
                        .sensitiveBlur(radius: 5)
                }
                .font(.headline)
                .foregroundStyle(.secondary)
            } else {
                Label(title, symbol: symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsChevron {
                Image(icon: .navArrowRight)
                    .iconSize(18)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Fremdes Logo im Kachelkopf (hell/dunkel), zugleich Link (z. B. zu den Datenquellen); bis es geladen ist, Text.
struct CardBrand: Equatable {
    var lightImageURL: URL?
    var darkImageURL: URL?
    let text: String
    let link: URL
}

private struct CardBrandMark: View {
    @Environment(\.colorScheme) private var colorScheme
    let brand: CardBrand

    var body: some View {
        Link(destination: brand.link) {
            AsyncImage(url: colorScheme == .dark ? brand.darkImageURL : brand.lightImageURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(verbatim: brand.text)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            // Schrifthöhe wie die übrigen Kachel-Titel (`.headline`).
            .frame(height: 15)
        }
        .accessibilityLabel(brand.text)
    }
}

/// Fortschrittsbalken: hoch, voll abgerundet, auch am Ende des aktuellen Werts.
/// Einheitlich für Kacheln mit Fortschritt (Wochenstunden, Checklisten).
struct CapsuleProgressBar: View {
    @Environment(\.appAccent) private var accent
    let value: Double
    /// Text mittig im Balken: über dem gefüllten Teil weiß, sonst in der Textfarbe.
    var label = ""

    var body: some View {
        GeometryReader { proxy in
            // Mindestens so breit wie hoch, damit das Ende immer rund bleibt.
            let fillWidth = value > 0 ? max(proxy.size.height, proxy.size.width * min(value, 1)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                if value > 0 {
                    Capsule()
                        .fill(accent.gradient)
                        .frame(width: fillWidth)
                }
                if !label.isEmpty {
                    labelText.foregroundStyle(.primary)
                    labelText.foregroundStyle(.white)
                        .mask(alignment: .leading) { Rectangle().frame(width: fillWidth) }
                }
            }
        }
        .frame(height: label.isEmpty ? 16 : 24)
        .animation(.smooth, value: value)
        .accessibilityElement()
        .accessibilityLabel("Fortschritt")
        .accessibilityValue(value.formatted(.percent.precision(.fractionLength(0))))
    }

    private var labelText: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
    }
}

/// Eigener Platzhalter im Privatsphäre-Modus: beginnt exakt am linken Textrand (der System-
/// Platzhalter von `privacySensitive` ist je nach Schriftgröße unterschiedlich eingerückt).
private struct CardPrivacyPlaceholder: ViewModifier {
    @Environment(\.redactionReasons) private var redactionReasons
    let isSensitive: Bool

    func body(content: Content) -> some View {
        if isSensitive, redactionReasons.contains(.privacy) {
            content
                .unredacted()
                .hidden()
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: min(8, proxy.size.height / 4), style: .continuous)
                            .fill(.fill.secondary)
                            .frame(width: proxy.size.width, height: proxy.size.height * 0.7)
                            .frame(maxHeight: .infinity)
                    }
                }
                .accessibilityHidden(true)
        } else {
            content
        }
    }
}

extension View {
    func cardPrivacy(_ isSensitive: Bool = true) -> some View {
        modifier(CardPrivacyPlaceholder(isSensitive: isSensitive))
    }

    /// Volle Breite, linksbündig: auch die Platzhalter im Privatsphäre-Modus beginnen links.
    func leadingAligned() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `padding`: Abstand zum Kartenrand.
    func cardStyle(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: cardHeight, alignment: .topLeading)
            // Weiß (hell) bzw. Dunkelgrau (dunkel) auf dem gruppierten Hintergrund.
            .background(Color(.secondarySystemGroupedBackground), in: cardShape)
            .contentShape(.hoverEffect, cardShape)
            .contentShape(.dragPreview, cardShape)
    }
}

/// Speicherschonende Vorschaubilder (große Fotos nicht komplett dekodieren).
nonisolated enum Thumbnail {
    static func make(from url: URL, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
