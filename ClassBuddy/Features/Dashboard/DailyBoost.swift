import FoundationModels
import SwiftUI

/// Tagesmotivation: ein kurzer Glückskeks-Spruch (Vorhersage, Weisheit oder Witz) vom Sprachmodell auf dem Gerät (Apple Intelligence).
/// Ohne bereites Modell (Gerät nicht unterstützt, Apple Intelligence aus, Modell lädt noch) gibt es
/// die Kachel weder in der Übersicht noch in der Galerie – vor iOS 26 also nie.
enum DailyBoost {
    static var isAvailable: Bool {
        if #available(iOS 26, *) { SystemLanguageModel.default.isAvailable } else { false }
    }

    /// Anweisungen auf Englisch (zuverlässiger), Antwort in der App-Sprache.
    private static func instructions(german: Bool, style: String) -> String {
        """
        You write the slip of paper inside a fortune cookie for a teacher. \
        Style for this one: \(style) \
        It should make a teacher smile or smirk: witty, surprising, a little mysterious, \
        with a playful twist at the end. Speak to the reader, never about yourself. \
        Never write gratitude statements or plain affirmations like "I am grateful for this wonderful day". \
        Never sad, mean or pressuring, no clichés about changing the world. \
        Between 8 and 15 words, never more. One or two short sentences. \
        No quotation marks, no hashtags, no emojis. \
        Reply with the text only, \
        \(german ? "in German. Address the reader with the formal \"Sie\"." : "in English.")
        """
    }

    /// Glückskeks-Arten: Vorhersage, Weisheit, Witz oder Omen (mit Beispiel als Richtschnur).
    private static let styles = [
        "a prophecy about something small and oddly specific that will happen today, e.g. "
            + "\"Before noon, a lost pencil will return to its rightful owner.\"",
        "a playful piece of fortune-cookie wisdom with a twist, e.g. "
            + "\"Who grades in silence hears the coffee calling.\"",
        "a short teacher joke that sounds like an ancient proverb, e.g. "
            + "\"The wise teacher keeps a spare marker. The wiser one keeps two.\"",
        "a lucky omen with an unexpected ending, e.g. "
            + "\"A great discovery awaits you in the staff room fridge.\"",
    ]

    /// Wechselnde Themen, damit sich die Sprüche nicht wiederholen.
    private static let topics = [
        "coffee", "the staff room", "a whiteboard marker", "the school bell", "homework", "the photocopier",
        "a forgotten lunch box", "the projector", "chalk", "a field trip", "the weekend", "a pop quiz",
        "recess", "a student's question", "the class plant", "report cards", "a rainy day", "the timetable",
        "a lost pencil case", "the last lesson of the day",
    ]

    /// Ein neuer Spruch (bis zu drei Versuche, falls das Modell zu lang wird);
    /// bei Fehlern (z. B. Schutzfilter) ein eingebauter Spruch.
    static func generate() async -> String {
        let german = AppLanguage.current.resolved == .german
        if #available(iOS 26, *) {
            for _ in 0..<3 {
                if let text = await attempt(german: german) { return text }
            }
        }
        return fallback(german: german)
    }

    @available(iOS 26, *)
    private static func attempt(german: Bool) async -> String? {
        let session = LanguageModelSession(instructions: instructions(german: german, style: styles.randomElement() ?? styles[0]))
        let topic = topics.randomElement() ?? "coffee"
        guard let response = try? await session.respond(
            to: "Today's theme: \(topic). Weekday: \(Date.now.appFormatted(.dateTime.weekday(.wide))).",
            options: GenerationOptions(temperature: 1.0, maximumResponseTokens: 60)
        ) else { return nil }
        let text = response.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"„“”'«»"))
        return isAcceptable(text) ? text : nil
    }

    /// Längster Satz, der noch in die Kachel passt; längere Antworten werden verworfen.
    static let maximumWords = 20

    /// Nicht leer und höchstens `maximumWords` Wörter.
    static func isAcceptable(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).count
        return words > 0 && words <= maximumWords
    }

    private static func fallback(german: Bool) -> String {
        let lines = german
            ? [
                "Noch vor der großen Pause kehrt ein verlorener Stift zu Ihnen zurück.",
                "Wer in Ruhe korrigiert, hört den Kaffee rufen.",
                "Der weise Lehrer hat einen Ersatzmarker. Der weisere hat zwei.",
                "Im Kühlschrank des Lehrerzimmers wartet heute eine große Entdeckung auf Sie.",
            ]
            : [
                "Before the big break, a lost pencil will return to you.",
                "Who grades in silence hears the coffee calling.",
                "The wise teacher keeps a spare marker. The wiser one keeps two.",
                "A great discovery awaits you in the staff room fridge today.",
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
