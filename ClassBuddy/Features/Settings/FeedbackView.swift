import SwiftUI

/// Feedback-Formular: Art + Nachricht, versendet über die Mail-App.
struct FeedbackView: View {
    @Environment(\.openURL) private var openURL

    enum Kind: String, CaseIterable, Identifiable {
        case bug = "Fehler"
        case idea = "Idee"
        case card = "Kachel-Wunsch"
        case praise = "Lob"
        case other = "Sonstiges"

        var id: String { rawValue }
    }

    @State private var kind: Kind = .idea
    @State private var message = ""

    var body: some View {
        Form {
            Section {
                Picker("Art", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextField("Deine Nachricht", text: $message, axis: .vertical)
                    .lineLimit(6...16)
            } footer: {
                Text("Bitte keine Schülerdaten schicken. Angehängt wird nur: \(AppInfo.deviceInfo)")
            }

            Section {
                Button("In Mail öffnen", image: .sendMail) {
                    openURL(AppInfo.mailURL(subject: "ClassBuddy: \(kind.rawValue)", body: message))
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("Öffnet deine Mail-App mit dem fertigen Entwurf an \(AppInfo.feedbackEmail). Gesendet wird erst, wenn du dort auf „Senden“ tippst.")
            }
        }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }
}
