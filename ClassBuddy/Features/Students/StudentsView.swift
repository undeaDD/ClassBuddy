import SwiftData
import SwiftUI

/// Schülerliste der ausgewählten Klasse: anlegen, bearbeiten, löschen, suchen.
struct StudentsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Query private var classes: [SchoolClass]

    @State private var searchText = ""
    @State private var editorRoute: StudentEditorRoute?
    @State private var studentPendingDeletion: Student?

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == app.selectedClassID }
    }

    var body: some View {
        Group {
            if let selectedClass {
                content(for: selectedClass)
            } else {
                EmptyStateView(
                    title: "Keine Klasse ausgewählt",
                    message: "Wähle oben links eine Klasse aus.",
                    symbol: AppTab.students.symbol
                )
            }
        }
        .navigationTitle(AppTab.students.title)
        .fullScreenCover(item: $editorRoute) { route in
            StudentEditorView(route: route)
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
    }

    @ViewBuilder
    private func content(for schoolClass: SchoolClass) -> some View {
        let students = filtered(schoolClass.sortedStudents)
        Group {
            if schoolClass.students.isEmpty {
                EmptyStateView(
                    title: "Noch keine Schüler",
                    message: "Füge die Schülerinnen und Schüler der \(schoolClass.title) hinzu.",
                    symbol: AppTab.students.symbol
                ) {
                    Button("Schüler hinzufügen", systemImage: "plus") {
                        editorRoute = .new(schoolClass)
                    }
                    .buttonStyle(.glassProminent)
                }
            } else {
                List {
                    Section {
                        ForEach(students) { student in
                            row(for: student)
                        }
                    } header: {
                        Text("\(schoolClass.students.count) Schüler")
                    }
                }
                .searchable(text: $searchText, prompt: "Schüler suchen")
                .overlay {
                    if students.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Schüler hinzufügen", systemImage: "plus") {
                    editorRoute = .new(schoolClass)
                }
            }
        }
    }

    private func row(for student: Student) -> some View {
        Button {
            editorRoute = .edit(student)
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
            Button("Bearbeiten", systemImage: "pencil") { editorRoute = .edit(student) }
                .tint(.accentColor)
        }
        // Nach links wischen: löschen
        .swipeActions(edge: .trailing) {
            Button("Löschen", systemImage: "trash", role: .destructive) { studentPendingDeletion = student }
        }
        .contextMenu {
            Button("Bearbeiten", systemImage: "pencil") { editorRoute = .edit(student) }
            Button("Löschen", systemImage: "trash", role: .destructive) { studentPendingDeletion = student }
        }
    }

    private func filtered(_ students: [Student]) -> [Student] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return students }
        return students.filter { $0.fullName.localizedStandardContains(query) }
    }

    private func delete(_ student: Student) {
        modelContext.delete(student)
        try? modelContext.save()
    }
}

/// Kreis mit Initialen.
struct StudentAvatar: View {
    let student: Student
    var size: CGFloat = 40

    var body: some View {
        Text(student.initials.isEmpty ? "?" : student.initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .background(.tint.opacity(0.15), in: .circle)
            .sensitiveBlur(radius: 6)
    }
}
