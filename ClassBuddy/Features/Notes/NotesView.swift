import SwiftUI

/// Notizen-Tab: Schüler der ausgewählten Klasse (alphabetisch mit Schnell-Index, durchsuchbar) → Fächer → Notizen.
struct NotesView: View {
    @State private var searchText = ""

    var body: some View {
        ClassScopedView { schoolClass in
            content(for: schoolClass)
        }
        .navigationTitle(AppTab.notes.title)
        .appChrome(tab: .notes)
    }

    @ViewBuilder
    private func content(for schoolClass: SchoolClass) -> some View {
        if schoolClass.students.isEmpty {
            EmptyStateView(
                title: loc("Noch keine Schüler"),
                message: loc("Legen Sie im Tab „Schüler“ die Schülerinnen und Schüler der \(schoolClass.title) an."),
                symbol: AppTab.notes.symbol
            )
            .background(Color(.systemGroupedBackground))
        } else {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            let sections = StudentLetterSection.sections(
                for: schoolClass.students.filter { query.isEmpty || $0.fullName.localizedStandardContains(query) }
            )
            List {
                ForEach(sections, id: \.letter) { section in
                    Section(section.letter) {
                        ForEach(section.students) { student in
                            NavigationLink {
                                StudentSubjectsView(student: student)
                            } label: {
                                StudentNameRow(student: student, detail: Self.noteCountText(for: student))
                            }
                        }
                    }
                    .sectionIndexLabel(section.letter)
                }
            }
            .listSectionIndexVisibility(.visible)
            .searchable(text: $searchText, prompt: "Schüler suchen")
            .overlay {
                if sections.isEmpty {
                    SearchEmptyStateView(text: searchText)
                }
            }
        }
    }

    /// „3 Notizen“ unter dem Namen.
    private static func noteCountText(for student: Student) -> String {
        student.noteCount == 1 ? loc("1 Notiz") : loc("\(student.noteCount) Notizen")
    }
}

/// Fächer eines Schülers (= Fächer seiner Klasse) → Notizen je Fach.
struct StudentSubjectsView: View {
    let student: Student

    private var subjects: [String] { student.schoolClass?.subjects ?? [] }

    var body: some View {
        List {
            Section {
                StudentNameRow(student: student, size: 56)
            }
            Section("Fächer") {
                ForEach(subjects, id: \.self) { subject in
                    NavigationLink(SchoolClass.displayName(ofSubject: subject)) {
                        StudentNotesView(student: student, subject: subject)
                    }
                }
            }
        }
        .overlay {
            if subjects.isEmpty {
                EmptyStateView(
                    title: loc("Keine Fächer"),
                    message: loc("Tragen Sie bei der Klasse die Fächer ein, die Sie dort unterrichten."),
                    symbol: AppTab.notes.symbol
                )
            }
        }
        .navigationTitle(AppTab.notes.title)
        .navigationBarTitleDisplayMode(.inline)
        .privacyModeToolbar()
    }
}

/// Notizen zu einem Schüler in einem Fach – vorerst Platzhalter (Planung in der Aufgabenliste im Projektordner).
struct StudentNotesView: View {
    let student: Student
    let subject: String

    var body: some View {
        VStack(spacing: 0) {
            StudentNameRow(student: student, size: 56)
                .environment(\.avatarCutout, [Color(.systemGroupedBackground)])
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            EmptyStateView(
                title: loc("Noch keine Notizen"),
                message: loc("Hier entstehen bald die Notizen für dieses Fach."),
                symbol: AppTab.notes.symbol
            )
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(SchoolClass.displayName(ofSubject: subject))
        .navigationBarTitleDisplayMode(.inline)
        .privacyModeToolbar()
    }
}

/// Foto/Initialen und voller Name, optional eine Zeile darunter (im Privatsphäre-Modus geschwärzt).
struct StudentNameRow: View {
    let student: Student
    var size: CGFloat = 40
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            StudentAvatar(student: student, size: size)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.fullName)
                    .font(size > 40 ? .title3.weight(.semibold) : .body.weight(.medium))
                    .sensitive()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .sensitive()
                }
            }
        }
    }
}

extension Student {
    /// Anzahl Notizen über alle Fächer – bis zum Notizen-Modell immer 0.
    var noteCount: Int { 0 }
}

extension View {
    /// Privatsphäre-Modus rechts außen – für Unterseiten mit Schülerdaten (die Tab-Toolbar gilt dort nicht).
    func privacyModeToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PrivacyModeButton()
            }
        }
    }
}
