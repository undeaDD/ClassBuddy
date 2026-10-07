import SwiftUI

/// Kachel „Schnellnotiz“: kurze Notiz zur Klasse; antippen öffnet den Editor.
struct QuickNoteCard: View {
    @Environment(AppSecurity.self) private var security
    let schoolClass: SchoolClass

    @State private var isEditorPresented = false

    var body: some View {
        Button(action: Haptics.tapping { isEditorPresented = true }) {
            QuickNoteCardContent(
                text: schoolClass.quickNote,
                detail: schoolClass.quickNoteEditedAt.map(Self.editedText) ?? loc("Antippen zum Schreiben")
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .sheet(isPresented: $isEditorPresented) {
            QuickNoteEditor(schoolClass: schoolClass)
                .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
                .presentationSizing(.form)
        }
    }

    static func editedText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? loc("Heute um \(date.appTime)") : loc("Am \(date.appDate) um \(date.appTime)")
    }
}

/// Inhalt der Schnellnotiz-Kachel (auch Galerie-Vorschau); ohne Text ein Hinweis.
struct QuickNoteCardContent: View {
    let text: String
    let detail: String

    var body: some View {
        let card = DashboardBuiltInCard.quickNote
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: card.title, symbol: card.symbol, showsChevron: true)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                if text.isEmpty {
                    Text("Noch keine Notiz")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .leadingAligned()
                } else {
                    Text(text)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .cardPrivacy()
                        .leadingAligned()
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .leadingAligned()
            }
        }
        .cardStyle()
    }
}

/// Editor der Schnellnotiz. Im Privatsphäre-Modus ist der Text ausgeblendet und nicht bearbeitbar.
private struct QuickNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSecurity.self) private var security
    let schoolClass: SchoolClass

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if security.isPrivacyModeOn {
                        Text("Im Privatsphäre-Modus ausgeblendet")
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("Notiz", text: $text, axis: .vertical)
                            .lineLimit(6...14)
                            .focused($isFocused)
                    }
                } footer: {
                    Text("Erscheint auf der Übersicht dieser Klasse.")
                }
            }
            .navigationTitle(loc("Schnellnotiz · \(schoolClass.shortName)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PrivacyModeButton()
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    ConfirmButton(title: loc("Sichern"), action: save)
                        .disabled(security.isPrivacyModeOn)
                }
            }
        }
        .onAppear {
            text = schoolClass.quickNote
            isFocused = true
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != schoolClass.quickNote {
            schoolClass.quickNote = trimmed
            schoolClass.quickNoteEditedAt = trimmed.isEmpty ? nil : .now
        }
        dismiss()
    }
}
