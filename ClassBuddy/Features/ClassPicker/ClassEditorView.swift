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
    /// Name einer `ClassColor` oder eigene Farbe als „#RRGGBB“.
    @State private var colorRaw: String
    /// Zuletzt gewählte eigene Farbe (letztes Farbfeld).
    @AppStorage("classEditor.lastCustomColor") private var lastCustomColor = "#9C6830"
    @State private var customSubject = ""

    init(schoolClass: SchoolClass?, onSave: @escaping (SchoolClass) -> Void = { _ in }) {
        self.schoolClass = schoolClass
        self.onSave = onSave
        _shortName = State(initialValue: schoolClass?.shortName ?? "")
        _subjects = State(initialValue: schoolClass?.subjects ?? [])
        _schoolYear = State(initialValue: schoolClass?.schoolYear ?? SchoolClass.currentSchoolYear)
        _colorRaw = State(initialValue: schoolClass?.colorRaw ?? ClassColor.blue.rawValue)
    }

    private var isNew: Bool { schoolClass == nil }

    private var isValid: Bool {
        !shortName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ClassBadge(shortName: shortName, color: SchoolClass.displayColor(for: colorRaw), size: 88)
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

                    NavigationLink {
                        SubjectPickerView(subjects: $subjects)
                    } label: {
                        Label("Fach hinzufügen", image: .plus)
                    }

                    HStack {
                        TextField("Eigenes Fach", text: $customSubject)
                            .onSubmit(addCustomSubject)
                        Button("Hinzufügen", image: .check, action: addCustomSubject)
                            .labelStyle(.iconOnly)
                            .disabled(customSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Fächer")
                } footer: {
                    Text("Zum Entfernen nach links wischen.")
                }

                Section("Farbe") {
                    // Bricht auf schmalen Bildschirmen in mehrere Zeilen um.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(ClassColor.allCases) { option in
                            Circle()
                                .fill(option.color.gradient)
                                .frame(width: 36, height: 36)
                                .overlay {
                                    if option.rawValue == colorRaw { selectionCheck }
                                }
                                .onTapGesture { colorRaw = option.rawValue }
                                .hoverEffect(.lift)
                                .accessibilityLabel(option.rawValue)
                                .accessibilityAddTraits(option.rawValue == colorRaw ? .isSelected : [])
                        }
                        customColorWell
                    }
                    .padding(.vertical, 4)
                }
            }
            .readableFormWidth()
            .navigationTitle(isNew ? "Neue Klasse" : "Klasse bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                        .glassToolbarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: isNew ? "Anlegen" : "Sichern", action: save)
                        .glassToolbarButton(prominent: true)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var selectionCheck: some View {
        Image(.check)
            .iconSize(18)
            .foregroundStyle(.white)
            .allowsHitTesting(false)
    }

    private var isCustomColor: Bool { ClassColor(rawValue: colorRaw) == nil }

    /// Letztes Farbfeld: systemeigene Farbauswahl, merkt sich die zuletzt gewählte Farbe.
    private var customColorWell: some View {
        ColorPicker(
            "Eigene Farbe",
            selection: Binding(
                get: { Color(hex: isCustomColor ? colorRaw : lastCustomColor) ?? .accentColor },
                set: { newColor in
                    let hex = newColor.hexString
                    lastCustomColor = hex
                    colorRaw = hex
                }
            ),
            supportsOpacity: false
        )
        .labelsHidden()
        .frame(width: 36, height: 36)
        .overlay {
            if isCustomColor { selectionCheck }
        }
        .accessibilityAddTraits(isCustomColor ? .isSelected : [])
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
        target.colorRaw = colorRaw
        try? modelContext.save()
        onSave(target)
        dismiss()
    }
}

/// Unterseite „Fach hinzufügen“: Vorschläge an- und abhaken (Reihenfolge = Reihenfolge des Antippens).
private struct SubjectPickerView: View {
    @Binding var subjects: [String]

    var body: some View {
        List(SchoolClass.suggestedSubjects, id: \.self) { subject in
            let isSelected = subjects.contains(subject)
            Button {
                if isSelected {
                    subjects.removeAll { $0 == subject }
                } else {
                    subjects.append(subject)
                }
            } label: {
                HStack {
                    Text(subject)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if isSelected {
                        Image(.check)
                            .iconSize(20)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .navigationTitle("Fächer")
        .navigationBarTitleDisplayMode(.inline)
    }
}
