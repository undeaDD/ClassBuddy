import SwiftData
import SwiftUI
import UIKit

extension DashboardLink {
    /// Neue Skript-Kachel, vorbelegt mit dem Beispiel (Zähler).
    static func newScript(in schoolClass: SchoolClass) -> DashboardLink {
        DashboardLink(title: loc("Zähler"), kind: .script, location: CardScript.example, schoolClass: schoolClass)
    }

    /// Was das Skript über die Klasse erfährt.
    var scriptClassInfo: CardScript.ClassInfo {
        CardScript.ClassInfo(
            name: schoolClass?.shortName ?? "",
            schoolYear: schoolClass?.schoolYear ?? "",
            studentCount: schoolClass?.students.count ?? 0
        )
    }
}

/// Programmierbare Kachel: Titel, Wert und Untertitel kommen aus `render(ctx)`,
/// Antippen führt `tap(ctx)` aus. Das Icon bleibt fest. Neu gezeichnet wird bei jeder
/// Änderung und einmal pro Minute (für Skripte mit `ctx.now`).
struct ScriptCard: View {
    let link: DashboardLink

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(ToastCenter.self) private var toasts
    @State private var output: CardScript.Output?
    @State private var isTapping = false
    @State private var isWaiting = false

    var body: some View {
        ScriptCardContent(output: output, fallbackTitle: link.title, isWaiting: isWaiting) {
            Task { await tap() }
        }
        .task(id: RenderKey(source: link.location, state: link.scriptState)) {
            while !Task.isCancelled {
                output = await CardScript.run(link.location, mode: .render, state: link.scriptState, schoolClass: link.scriptClassInfo)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private struct RenderKey: Equatable {
        let source: String
        let state: String
    }

    private func tap() async {
        guard !isTapping else { return }
        isTapping = true
        defer { isTapping = false }
        let result = await CardScript.showingDots($isWaiting) {
            await CardScript.run(link.location, mode: .tap, state: link.scriptState, schoolClass: link.scriptClassInfo)
        }
        output = result
        guard result.error == nil else { return }
        if result.state != link.scriptState {
            link.scriptState = result.state
            try? modelContext.save()
        }
        result.toasts.forEach { toasts.info($0) }
        if let url = result.urlToOpen { openURL(url) }
    }
}

extension CardScript {
    /// Wartepunkte erst nach kurzer Zeit zeigen – schnelle Skripte sollen nicht flackern.
    static func showingDots(_ isWaiting: Binding<Bool>, _ work: () async -> Output) async -> Output {
        let dots = Task {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { isWaiting.wrappedValue = true }
        }
        defer {
            dots.cancel()
            isWaiting.wrappedValue = false
        }
        return await work()
    }
}

/// Darstellung einer Skript-Kachel (auch Vorschau im Editor); Fehler statt Wert, falls das Skript scheitert.
/// Während `tap` noch läuft (z. B. `fetch`), pulsieren drei Punkte statt des Werts.
struct ScriptCardContent: View {
    let output: CardScript.Output?
    let fallbackTitle: String
    var isWaiting = false
    let action: () -> Void

    var body: some View {
        if isWaiting {
            TimelineView(.periodic(from: .now, by: 0.35)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
                StatCard(
                    title: output?.title ?? fallbackTitle,
                    value: String(repeating: "•", count: step + 1),
                    detail: output?.subtitle,
                    symbol: .custom(.code),
                    action: action
                )
            }
        } else if let error = output?.error {
            StatCard(title: fallbackTitle, value: loc("Fehler"), detail: error, symbol: .custom(.code), action: action)
        } else {
            StatCard(
                title: output?.title ?? fallbackTitle,
                value: output?.value ?? "–",
                detail: output?.subtitle,
                symbol: .custom(.code),
                action: action
            )
        }
    }
}

/// Sheet: Skript einer Kachel bearbeiten, mit Live-Vorschau (antippbar, um `tap` zu testen).
/// Änderungen am Zustand in der Vorschau werden erst mit „Sichern“ übernommen.
struct ScriptEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts

    let link: DashboardLink

    @State private var title: String
    @State private var source: String
    @State private var state: String
    @State private var output: CardScript.Output?
    @State private var isWaiting = false

    init(link: DashboardLink) {
        self.link = link
        _title = State(initialValue: link.title)
        _source = State(initialValue: link.location)
        _state = State(initialValue: link.scriptState)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScriptCardContent(output: output, fallbackTitle: displayTitle, isWaiting: isWaiting) {
                        Task { await previewTap() }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Vorschau")
                } footer: {
                    Text("Antippen führt tap(ctx) aus. Gespeichert wird erst mit „Sichern“.")
                }

                Section {
                    TextField("Name (wenn das Skript keinen Titel liefert)", text: $title)
                }

                Section("JavaScript") {
                    CodeEditor(text: $source)
                        .frame(minHeight: 360)
                }

                Section {
                    Button("Beispiel wiederherstellen", icon: .plus) {
                        source = CardScript.example
                        state = "{}"
                    }
                    Button("Gespeicherten Zustand zurücksetzen", icon: .trash, role: .destructive) {
                        state = "{}"
                    }
                    .disabled(state == "{}")
                } footer: {
                    Text("""
                        Internet nur per fetch in tap(ctx): eine https-Anfrage, höchstens 5 s, nur Text. \
                        Keine Dateien, kein Zugriff auf Schülerdaten.
                        """)
                }
            }
            .navigationTitle("Skript bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: loc("Sichern"), action: save)
                }
            }
            // Vorschau kurz nach dem Tippen neu berechnen.
            .task(id: "\(source)\u{0}\(state)") {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                output = await CardScript.run(source, mode: .render, state: state, schoolClass: link.scriptClassInfo)
            }
        }
    }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? LinkCard.kindTitle(.script) : trimmed
    }

    private func previewTap() async {
        let result = await CardScript.showingDots($isWaiting) {
            await CardScript.run(source, mode: .tap, state: state, schoolClass: link.scriptClassInfo)
        }
        output = result
        guard result.error == nil else { return }
        state = result.state
        result.toasts.forEach { toasts.info($0) }
        if let url = result.urlToOpen { toasts.info(loc("Würde öffnen: \(url.absoluteString)")) }
    }

    private func save() {
        link.title = title.trimmingCharacters(in: .whitespaces)
        link.location = source
        link.scriptState = state
        try? modelContext.save()
        dismiss()
    }
}

/// Code-Eingabe ohne Autokorrektur und ohne typografische Anführungszeichen,
/// die JavaScript-Strings sonst kaputt machen würden.
private struct CodeEditor: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.backgroundColor = .clear
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.inlinePredictionType = .no
        view.writingToolsBehavior = .none
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.text = text
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
