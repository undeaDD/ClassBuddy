import SwiftData
import SwiftUI

/// Vollbild-Formular zum Anlegen (`schoolClass == nil`) oder Bearbeiten einer Klasse.
/// Änderungen werden erst bei „Sichern“ übernommen.
struct ClassEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let schoolClass: SchoolClass?
    var onSave: (SchoolClass) -> Void = { _ in }

    @State private var shortName: String
    @State private var subjects: [String]
    @State private var schoolYear: String
    @State private var color: ClassColor
    @State private var customSubject = ""

    init(schoolClass: SchoolClass?, onSave: @escaping (SchoolClass) -> Void = { _ in }) {
        self.schoolClass = schoolClass
        self.onSave = onSave
        _shortName = State(initialValue: schoolClass?.shortName ?? "")
        _subjects = State(initialValue: schoolClass?.subjects ?? [])
        _schoolYear = State(initialValue: schoolClass?.schoolYear ?? SchoolClass.currentSchoolYear)
        _color = State(initialValue: schoolClass?.color ?? .blue)
    }

    private var isNew: Bool { schoolClass == nil }

    private var isValid: Bool {
        !shortName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Vorschläge, die noch nicht ausgewählt sind.
    private var remainingSuggestions: [String] {
        SchoolClass.suggestedSubjects.filter { !subjects.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ClassBadge(shortName: shortName, color: color.color, size: 88)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Klasse") {
                    TextField("Kürzel (z. B. 7b)", text: $shortName)
                        .textInputAutocapitalization(.never)
                    TextField("Schuljahr", text: $schoolYear)
                }

                Section {
                    ForEach(subjects, id: \.self) { subject in
                        Text(subject)
                    }
                    .onDelete { subjects.remove(atOffsets: $0) }
                    .onMove { subjects.move(fromOffsets: $0, toOffset: $1) }

                    Menu {
                        ForEach(remainingSuggestions, id: \.self) { subject in
                            Button(subject) { subjects.append(subject) }
                        }
                    } label: {
                        Label("Fach hinzufügen", systemImage: "plus.circle.fill")
                    }
                    .disabled(remainingSuggestions.isEmpty)

                    HStack {
                        TextField("Eigenes Fach", text: $customSubject)
                            .onSubmit(addCustomSubject)
                        Button("Hinzufügen", systemImage: "return", action: addCustomSubject)
                            .labelStyle(.iconOnly)
                            .disabled(customSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Fächer")
                } footer: {
                    Text("Zum Entfernen nach links wischen.")
                }

                Section("Farbe") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 12) {
                        ForEach(ClassColor.allCases) { option in
                            Circle()
                                .fill(option.color.gradient)
                                .frame(width: 36, height: 36)
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
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isNew ? "Neue Klasse" : "Klasse bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Anlegen" : "Sichern", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func addCustomSubject() {
        let subject = customSubject.trimmingCharacters(in: .whitespaces)
        guard !subject.isEmpty else { return }
        if !subjects.contains(subject) { subjects.append(subject) }
        customSubject = ""
    }

    private func save() {
        let target = schoolClass ?? {
            let newClass = SchoolClass(shortName: "")
            modelContext.insert(newClass)
            return newClass
        }()
        target.shortName = shortName.trimmingCharacters(in: .whitespaces)
        target.subjects = subjects
        target.schoolYear = schoolYear.trimmingCharacters(in: .whitespaces)
        target.color = color
        try? modelContext.save()
        onSave(target)
        dismiss()
    }
}
