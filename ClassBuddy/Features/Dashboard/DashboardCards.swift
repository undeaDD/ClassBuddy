import ImageIO
import SwiftUI
import UIKit

// Kachel-Designs der Übersicht. Inhalte sind im Privatsphäre-Modus ausgeblendet.

let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
let cardMinHeight: CGFloat = 150

/// Kennzahl-Kachel; antippen öffnet die zugehörige Seite.
struct StatCard: View {
    let title: String
    let value: String
    var detail: String?
    let symbol: AppSymbol
    /// Wert/Detail im Privatsphäre-Modus ausblenden (nicht bei Uhrzeit, Wetter …).
    var isSensitive = true
    var action: (() -> Void)?

    var body: some View {
        // Ohne Aktion keine Schaltfläche: nicht ausgegraut, kein Hover, kein Pfeil.
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title, symbol: symbol, showsChevron: action != nil)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .cardPrivacy(isSensitive)
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
        Button(action: action) {
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
        case .shortcut: "Kurzbefehl"
        case .file, .image: "Dokument"
        }
    }

    static func kindSymbol(_ kind: DashboardLink.Kind) -> AppSymbol {
        switch kind {
        case .website: .custom(.www)
        case .shortcut: .custom(.shortcuts)
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
        Button(action: action) {
            // Feste Kartengröße; das Bild liegt als Overlay darüber (füllt, zentriert, beschnitten)
            // und beeinflusst die Höhe der Kachel damit nicht.
            Color(.secondarySystemGroupedBackground)
                .frame(maxWidth: .infinity)
                .frame(height: cardMinHeight)
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

/// Bild-Kachel ohne echtes Bild (Galerie-Vorschau).
struct ImagePlaceholderCard: View {
    let title: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.2)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(.image)
                .iconSize(48)
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(title)
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
                .padding(12)
        }
        .frame(maxWidth: .infinity, minHeight: cardMinHeight)
        .clipShape(cardShape)
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
            detail: students.isEmpty ? "Noch keine Schüler" : (picked == nil ? "Antippen zum Auswählen" : "Antippen für neue Auswahl"),
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
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
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
                    Text(result.fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .cardPrivacy()
                        .leadingAligned()
                    // Im Privatsphäre-Modus leerer Balken (verrät nichts über den Stundenplan).
                    CapsuleProgressBar(value: redactionReasons.contains(.privacy) ? 0 : result.fraction)
                        .padding(.vertical, 4)
                    HStack {
                        Text("\(WeeklyWorkload.hours(result.doneMinutes)) erledigt")
                        Spacer()
                        Text("\(WeeklyWorkload.hours(result.totalMinutes)) gesamt")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .cardPrivacy()
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
        Button(action: action) {
            VStack(spacing: 8) {
                Image(.plus).iconSize(36)
                Text("Kachel hinzufügen")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight)
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

    var body: some View {
        HStack {
            if let faviconURL {
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
                Image(.navArrowRight)
                    .iconSize(18)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Fortschrittsbalken: hoch, voll abgerundet, auch am Ende des aktuellen Werts.
private struct CapsuleProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                if value > 0 {
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        // Mindestens so breit wie hoch, damit das Ende immer rund bleibt.
                        .frame(width: max(proxy.size.height, proxy.size.width * min(value, 1)))
                }
            }
        }
        .frame(height: 16)
        .animation(.smooth, value: value)
        .accessibilityElement()
        .accessibilityLabel("Fortschritt")
        .accessibilityValue(value.formatted(.percent.precision(.fractionLength(0))))
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

    func cardStyle() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
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
