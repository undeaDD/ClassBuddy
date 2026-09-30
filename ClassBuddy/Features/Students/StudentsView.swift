import SwiftData
import SwiftUI

/// Schülerliste der ausgewählten Klasse: alphabetisch nach Vornamen gruppiert,
/// durchsuchbar. Im Privatsphäre-Modus nur lesend.
struct StudentsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @Query private var classes: [SchoolClass]

    @State private var searchText = ""
    @State private var editorRoute: StudentEditorRoute?
    @State private var studentPendingDeletion: Student?

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == app.selectedClassID }
    }

    /// Bearbeiten ist im Privatsphäre-Modus gesperrt.
    private var canEdit: Bool { !security.isPrivacyModeOn }

    var body: some View {
        ClassScopedView { schoolClass in
            content(for: schoolClass)
        }
        .navigationTitle(AppTab.students.title)
        .navigationSubtitle(selectedClass.map { "\($0.students.count) Schüler" } ?? "")
        .appChrome(tab: .students) {
            if let selectedClass {
                Button("Schüler hinzufügen", image: .plus) {
                    editorRoute = .new(selectedClass)
                }
                .disabled(!canEdit)
            }
        }
        .fullScreenCover(item: $editorRoute) { route in
            StudentEditorView(route: route)
                .softScrollEdges()
        }
        .confirmationDialog(
            "Schüler löschen?",
            isPresented: Binding(
                get: { studentPendingDeletion != nil },
                set: { if !$0 { studentPendingDeletion = nil } }
            ),
            presenting: studentPendingDeletion
        ) { student in
            Button("Löschen", role: .destructive) { delete(student) }
        } message: { _ in
            Text("Das kann nicht rückgängig gemacht werden.")
        }
        // Privatsphäre-Modus an → offene Editoren/Dialoge sofort schließen.
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                editorRoute = nil
                studentPendingDeletion = nil
            }
        }
    }

    @ViewBuilder
    private func content(for schoolClass: SchoolClass) -> some View {
        if schoolClass.students.isEmpty {
            EmptyStateView(
                title: "Noch keine Schüler",
                message: "Füge über + oben rechts die Schülerinnen und Schüler der \(schoolClass.title) hinzu.",
                symbol: AppTab.students.symbol
            )
            .background(Color(.systemGroupedBackground))
        } else {
            let sections = sections(for: filtered(schoolClass.students))
            List {
                ForEach(sections, id: \.letter) { section in
                    Section(section.letter) {
                        ForEach(section.students) { student in
                            row(for: student)
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

    private func row(for student: Student) -> some View {
        Button {
            if canEdit { editorRoute = .edit(student) }
        } label: {
            HStack(spacing: 12) {
                StudentAvatar(student: student, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.fullName)
                        .font(.body.weight(.medium))
                        .sensitive()
                    if let age = student.age {
                        Text("\(age) Jahre")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .sensitive()
                    }
                }
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // Nach rechts wischen: bearbeiten
        .swipeActions(edge: .leading) {
            if canEdit {
                Button("Bearbeiten", image: .editPencil) { editorRoute = .edit(student) }
                    .tint(.accentColor)
            }
        }
        // Nach links wischen: löschen
        .swipeActions(edge: .trailing) {
            if canEdit {
                Button("Löschen", image: .trash, role: .destructive) { studentPendingDeletion = student }
            }
        }
        .contextMenu {
            if canEdit {
                Button("Bearbeiten", image: .editPencil) { editorRoute = .edit(student) }
                Button("Löschen", image: .trash, role: .destructive) { studentPendingDeletion = student }
            }
        }
    }

    private struct LetterSection {
        let letter: String
        let students: [Student]
    }

    private func sections(for students: [Student]) -> [LetterSection] {
        let sorted = students.sorted {
            let byFirst = $0.firstName.localizedStandardCompare($1.firstName)
            return byFirst == .orderedSame
                ? $0.lastName.localizedStandardCompare($1.lastName) == .orderedAscending
                : byFirst == .orderedAscending
        }
        let grouped = Dictionary(grouping: sorted, by: \.sectionLetter)
        return grouped.keys
            .sorted { $0 == "#" ? false : $1 == "#" ? true : $0 < $1 }
            .map { LetterSection(letter: $0, students: grouped[$0] ?? []) }
    }

    private func filtered(_ students: [Student]) -> [Student] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return students }
        return students.filter { $0.fullName.localizedStandardContains(query) }
    }

    private func delete(_ student: Student) {
        modelContext.delete(student)
        do {
            try modelContext.save()
            toasts.success("Schüler gelöscht")
        } catch {
            toasts.error("Löschen fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}

/// Kreis mit Initialen und kleinem Geschlechts-Indikator.
struct StudentAvatar: View {
    let student: Student
    var size: CGFloat = 40

    var body: some View {
        Text(student.initials.isEmpty ? "?" : student.initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .background(.tint.opacity(0.15), in: .circle)
            .overlay(alignment: .bottomTrailing) {
                if let gender = student.gender {
                    GenderBadge(gender: gender, size: size * 0.42)
                        .offset(x: size * 0.08, y: size * 0.08)
                }
            }
    }
}

struct GenderBadge: View {
    let gender: Gender
    var size: CGFloat = 16

    var body: some View {
        Text(gender.symbol)
            .font(.system(size: size * 0.72, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(gender.color, in: .circle)
            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
            .accessibilityLabel(gender.title)
    }
}

extension Gender {
    var color: Color {
        switch self {
        case .female: .pink
        case .male: .blue
        case .diverse: .purple
        }
    }
}
