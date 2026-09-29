import SwiftData
import SwiftUI

/// Popover-Liste aller Klassen: wechseln, anlegen, bearbeiten, löschen.
struct ClassPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\SchoolClass.schoolYear, order: .reverse), SortDescriptor(\SchoolClass.shortName)])
    private var classes: [SchoolClass]

    @State private var editorRoute: ClassEditorRoute?
    @State private var closePickerAfterEditor = false
    @State private var classPendingDeletion: SchoolClass?
    @State private var searchText = ""

    /// Klassen gefiltert nach Suche, gruppiert nach Schuljahr (neuestes zuerst).
    private var sections: [(year: String, classes: [SchoolClass])] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty ? classes : classes.filter {
            $0.shortName.localizedStandardContains(query)
                || $0.subjects.contains { $0.localizedStandardContains(query) }
        }
        let grouped = Dictionary(grouping: matches, by: \.schoolYear)
        return grouped.keys.sorted(by: >).map { (year: $0, classes: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if classes.isEmpty {
                    Text("Noch keine Klassen")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(sections, id: \.year) { section in
                            Section(section.year.isEmpty ? "Ohne Schuljahr" : "Schuljahr \(section.year)") {
                                ForEach(section.classes) { schoolClass in
                                    row(for: schoolClass)
                                }
                            }
                        }
                    }
                    // Suche im Privatsphäre-Modus ausblenden (würde Namen verraten).
                    .searchable(if: canEdit, text: $searchText, prompt: "Klasse oder Fach")
                    .overlay {
                        if sections.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                }
            }
            .navigationTitle("Klassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Keine Klasse ausgewählt → Leerzustände der Seiten.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abwählen") {
                        app.selectedClassID = nil
                        app.isClassPickerPresented = false
                    }
                    .disabled(app.selectedClassID == nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Neue Klasse", image: .plus) { editorRoute = .new }
                        .disabled(!canEdit)
                }
            }
            .confirmationDialog(
                "Klasse löschen?",
                isPresented: Binding(
                    get: { classPendingDeletion != nil },
                    set: { if !$0 { classPendingDeletion = nil } }
                ),
                presenting: classPendingDeletion
            ) { schoolClass in
                Button("\(schoolClass.title) löschen", role: .destructive) { delete(schoolClass) }
            } message: { schoolClass in
                Text("Die Klasse und alle \(schoolClass.students.count) Schüler werden entfernt. Das kann nicht rückgängig gemacht werden.")
            }
        }
        .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
        // Vollbild-Editor direkt aus dem Popover. Das Popover wird erst geschlossen,
        // wenn der Editor komplett weg ist (sonst kollidieren beide Übergänge).
        .fullScreenCover(item: $editorRoute, onDismiss: {
            if closePickerAfterEditor {
                closePickerAfterEditor = false
                app.isClassPickerPresented = false
            }
        }, content: { route in
            ClassEditorView(schoolClass: route.schoolClass) { saved in
                if route.schoolClass == nil {
                    app.selectedClassID = saved.id
                    closePickerAfterEditor = true
                }
            }
            .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
        })
        // Privatsphäre-Modus an → Editor/Dialog sofort schließen.
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                searchText = ""
                editorRoute = nil
                classPendingDeletion = nil
            }
        }
    }

    /// Bearbeiten ist im Privatsphäre-Modus gesperrt.
    private var canEdit: Bool { !security.isPrivacyModeOn }

    private func row(for schoolClass: SchoolClass) -> some View {
        Button {
            // Erneutes Antippen der aktiven Klasse hebt die Auswahl auf.
            app.selectedClassID = app.selectedClassID == schoolClass.id ? nil : schoolClass.id
            app.isClassPickerPresented = false
        } label: {
            HStack(spacing: 12) {
                ClassBadge(shortName: schoolClass.shortName, color: schoolClass.color.color, size: 40)
                VStack(alignment: .leading) {
                    Text(schoolClass.title).font(.body.weight(.medium))
                        .sensitive()
                    Text(schoolClass.detailLine).font(.caption).foregroundStyle(.secondary)
                        .sensitive()
                }
                Spacer()
                if app.selectedClassID == schoolClass.id {
                    Image(.check)
                        .iconSize(20)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // Nach rechts wischen: bearbeiten
        .swipeActions(edge: .leading) {
            if canEdit {
                Button("Bearbeiten", image: .editPencil) {
                    editorRoute = .edit(schoolClass)
                }
                .tint(.accentColor)
            }
        }
        // Nach links wischen: löschen
        .swipeActions(edge: .trailing) {
            if canEdit {
                Button("Löschen", image: .trash, role: .destructive) {
                    classPendingDeletion = schoolClass
                }
            }
        }
        // Lange drücken (Finger oder Apple Pencil) bzw. Rechtsklick.
        .contextMenu {
            if canEdit {
                Button("Bearbeiten", image: .editPencil) {
                    editorRoute = .edit(schoolClass)
                }
                Button("Löschen", image: .trash, role: .destructive) {
                    classPendingDeletion = schoolClass
                }
            }
        }
    }

    private func delete(_ schoolClass: SchoolClass) {
        if app.selectedClassID == schoolClass.id { app.selectedClassID = nil }
        // Kopierte Dokumente der Übersichts-Kacheln mit entfernen.
        schoolClass.dashboardLinks.forEach(LinkFileStore.removeFile)
        modelContext.delete(schoolClass)
        try? modelContext.save()
    }
}

enum ClassEditorRoute: Identifiable {
    case new
    case edit(SchoolClass)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let schoolClass): schoolClass.id.uuidString
        }
    }

    var schoolClass: SchoolClass? {
        if case .edit(let schoolClass) = self { schoolClass } else { nil }
    }
}

private extension View {
    @ViewBuilder
    func searchable(if enabled: Bool, text: Binding<String>, prompt: String) -> some View {
        if enabled {
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        } else {
            self
        }
    }
}
