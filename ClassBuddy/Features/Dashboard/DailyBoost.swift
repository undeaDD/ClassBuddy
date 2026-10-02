import FoundationModels
import SwiftUI

/// Tagesmotivation: ein kurzer, fröhlicher Satz vom Sprachmodell auf dem Gerät (Apple Intelligence).
/// Ohne bereites Modell (Gerät nicht unterstützt, Apple Intelligence aus, Modell lädt noch) gibt es
/// die Kachel weder in der Übersicht noch in der Galerie.
enum DailyBoost {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// Anweisungen auf Englisch (zuverlässiger), Antwort in der App-Sprache.
    private static func instructions(german: Bool) -> String {
        """
        You write one short, cheerful, light-hearted sentence for a teacher's day. \
        Warm, playful and a little funny. Small everyday joys are perfect: coffee, sunshine, \
        a laughing class, a good idea, the weekend getting closer. \
        Never sad, never pressuring, no grand promises, no clichés about changing the world, \
        nothing unrealistic. At most 18 words. No quotation marks, no hashtags, no emojis. \
        Reply with the sentence only, \
        \(german ? "in German. If you address the reader, use the formal \"Sie\"." : "in English.")
        """
    }

    /// Wechselnde Themen, damit sich die Sätze nicht wiederholen.
    private static let topics = [
        "coffee or tea", "sunshine", "a small win", "laughter in class", "curiosity", "the weekend",
        "a fresh idea", "chalk and whiteboards", "a good book", "fresh air", "a kind word", "music",
        "a tidy desk", "a lunch break", "creativity", "a student's aha moment", "a smile", "the morning",
        "plants on the windowsill", "a well-earned break",
    ]

    /// Ein neuer Satz; bei Fehlern (z. B. Schutzfilter) ein eingebauter Satz.
    static func generate() async -> String {
        let german = AppLanguage.current.resolved == .german
        let session = LanguageModelSession(instructions: instructions(german: german))
        let topic = topics.randomElement() ?? "a smile"
        do {
            let response = try await session.respond(
                to: "Today's theme: \(topic). Weekday: \(Date.now.appFormatted(.dateTime.weekday(.wide))).",
                options: GenerationOptions(temperature: 1.0, maximumResponseTokens: 80)
            )
            let text = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"„“”'«»"))
            return text.isEmpty ? fallback(german: german) : text
        } catch {
            return fallback(german: german)
        }
    }

    private static func fallback(german: Bool) -> String {
        let lines = german
            ? [
                "Heute ist ein guter Tag für eine richtig gute Tasse Kaffee.",
                "Irgendwo in Ihrer Klasse wartet heute ein Aha-Moment.",
                "Ein Lächeln am Morgen macht jede Stunde ein bisschen leichter.",
                "Kleine Fortschritte sind auch Fortschritte – und die zählen heute doppelt.",
            ]
            : [
                "Today is a great day for a really good cup of coffee.",
                "Somewhere in your class, an aha moment is waiting today.",
                "A morning smile makes every lesson a little lighter.",
                "Small steps are still steps, and today they count double.",
            ]
        return lines.randomElement() ?? lines[0]
    }
}

/// Kachel „Tagesmotivation“: ein Satz pro Tag, antippen holt einen neuen.
struct DailyBoostCard: View {
    /// Fester Text für die Galerie-Vorschau (dann nicht interaktiv).
    var previewText: String?

    // Gilt für alle Klassen; neu je Tag und Sprache.
    @AppStorage("dailyBoost.text") private var text = ""
    @AppStorage("dailyBoost.key") private var storedKey = ""
    @State private var isGenerating = false

    /// Tag + Sprache: wechselt eins davon, gibt es einen neuen Satz.
    private var todayKey: String {
        "\(Date.now.formatted(.iso8601.year().month().day()))-\(AppLanguage.current.resolved.rawValue)"
    }

    var body: some View {
        if let previewText {
            content(previewText)
        } else {
            Button(action: Haptics.tapping { Task { await refresh() } }) {
                content(text)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .disabled(isGenerating)
            .task(id: todayKey) {
                if storedKey != todayKey || text.isEmpty { await refresh() }
            }
        }
    }

    private func content(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: DashboardBuiltInCard.dailyBoost.title, symbol: DashboardBuiltInCard.dailyBoost.symbol, showsChevron: false)
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(4)
                    .minimumScaleFactor(0.75)
                    .leadingAligned()
                    .opacity(isGenerating ? 0.3 : 1)
                    .contentTransition(.opacity)
                if isGenerating { ProgressView() }
            }
            .animation(.smooth, value: text)
        }
        .cardStyle()
    }

    private func refresh() async {
        guard !isGenerating else { return }
        isGenerating = true
        let key = todayKey
        let new = await DailyBoost.generate()
        text = new
        storedKey = key
        isGenerating = false
    }
}
