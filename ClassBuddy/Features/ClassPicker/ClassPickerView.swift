import SwiftData
import SwiftUI

/// Liste aller Klassen: wechseln, anlegen, bearbeiten, löschen.
struct ClassPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\SchoolClass.schoolYear, order: .reverse), SortDescriptor(\SchoolClass.shortName)])
    private var classes: [SchoolClass]

    @State private var isCreating = false
    @State private var editingClass: SchoolClass?
    @State private var classPendingDeletion: SchoolClass?

    var body: some View {
        NavigationStack {
            Group {
                if classes.isEmpty {
                    EmptyStateView(
                        title: "Noch keine Klassen",
                        message: "Lege deine erste Klasse an.",
                        symbol: .system("person.2.badge.plus")
                    ) {
                        Button("Klasse anlegen") { isCreating = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(classes) { schoolClass in
                            row(for: schoolClass)
                        }
                    }
                }
            }
            .navigationTitle("Klassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Neue Klasse", systemImage: "plus") { isCreating = true }
                }
            }
            .navigationDestination(isPresented: $isCreating) {
                ClassEditorView(schoolClass: nil) { newClass in
                    app.selectedClassID = newClass.id
                    app.isClassPickerPresented = false
                }
            }
            .navigationDestination(item: $editingClass) { schoolClass in
                ClassEditorView(schoolClass: schoolClass) { _ in
                    editingClass = nil
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
            } message: { _ in
                Text("Alle Daten dieser Klasse werden entfernt. Das kann nicht rückgängig gemacht werden.")
            }
        }
        .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
    }

    private func row(for schoolClass: SchoolClass) -> some View {
        Button {
            app.selectedClassID = schoolClass.id
            app.isClassPickerPresented = false
        } label: {
            HStack(spacing: 12) {
                ClassBadge(shortName: schoolClass.shortName, color: schoolClass.color.color, size: 40)
                VStack(alignment: .leading) {
                    Text(schoolClass.title).font(.body.weight(.medium))
                    Text(schoolClass.detailLine).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if app.selectedClassID == schoolClass.id {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .swipeActions(edge: .trailing) {
            Button("Löschen", systemImage: "trash", role: .destructive) {
                classPendingDeletion = schoolClass
            }
            Button("Bearbeiten", systemImage: "pencil") {
                editingClass = schoolClass
            }
            .tint(.accentColor)
        }
        // Lange drücken (Finger oder Apple Pencil) bzw. Rechtsklick.
        .contextMenu {
            Button("Bearbeiten", systemImage: "pencil") {
                editingClass = schoolClass
            }
            Button("Löschen", systemImage: "trash", role: .destructive) {
                classPendingDeletion = schoolClass
            }
        }
    }

    private func delete(_ schoolClass: SchoolClass) {
        if app.selectedClassID == schoolClass.id { app.selectedClassID = nil }
        modelContext.delete(schoolClass)
        try? modelContext.save()
    }
}

/// Formular zum Anlegen (`schoolClass == nil`) oder Bearbeiten einer Klasse.
struct ClassEditorView: View {
    @Environment(\.modelContext) private var modelContext

    let schoolClass: SchoolClass?
    /// Wird nach dem Speichern aufgerufen und übernimmt das Schließen
    /// (Popover schließen bzw. zurück zur Liste).
    var onSave: (SchoolClass) -> Void

    @State private var shortName: String
    @State private var subtitle: String
    @State private var schoolYear: String
    @State private var color: ClassColor

    init(schoolClass: SchoolClass?, onSave: @escaping (SchoolClass) -> Void) {
        self.schoolClass = schoolClass
        self.onSave = onSave
        _shortName = State(initialValue: schoolClass?.shortName ?? "")
        _subtitle = State(initialValue: schoolClass?.subtitle ?? "")
        _schoolYear = State(initialValue: schoolClass?.schoolYear ?? SchoolClass.currentSchoolYear)
        _color = State(initialValue: schoolClass?.color ?? .blue)
    }

    private var isValid: Bool {
        !shortName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    ClassBadge(shortName: shortName, color: color.color, size: 72)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section("Klasse") {
                TextField("Kürzel (z. B. 7b)", text: $shortName)
                    .textInputAutocapitalization(.never)
                TextField("Fach / Rolle (z. B. Mathematik)", text: $subtitle)
                TextField("Schuljahr", text: $schoolYear)
            }
            Section("Farbe") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(ClassColor.allCases) { option in
                        Circle()
                            .fill(option.color.gradient)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if option == color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture { color = option }
                            .hoverEffect(.lift)
                            .accessibilityLabel(option.rawValue)
                            .accessibilityAddTraits(option == color ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(schoolClass == nil ? "Neue Klasse" : "Klasse bearbeiten")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(schoolClass == nil ? "Anlegen" : "Sichern", action: save)
                    .disabled(!isValid)
            }
        }
    }

    private func save() {
        let target = schoolClass ?? {
            let newClass = SchoolClass(shortName: "")
            modelContext.insert(newClass)
            return newClass
        }()
        target.shortName = shortName.trimmingCharacters(in: .whitespaces)
        target.subtitle = subtitle.trimmingCharacters(in: .whitespaces)
        target.schoolYear = schoolYear.trimmingCharacters(in: .whitespaces)
        target.color = color
        try? modelContext.save()
        onSave(target)
    }
}
