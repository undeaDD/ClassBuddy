import SwiftData
import SwiftUI

/// Vollbild-Formular zum Anlegen (`schoolClass == nil`) oder Bearbeiten einer Klasse.
/// Änderungen werden erst bei „Sichern“ übernommen.
struct ClassEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.appAccent) private var accent

    let schoolClass: SchoolClass?
    var onSave: (SchoolClass) -> Void = { _ in }

    @State private var shortName: String
    @State private var subjects: [String]
    @State private var schoolYear: String
    /// Name einer `ClassColor` oder eigene Farbe als „#RRGGBB“.
    @State private var colorRaw: String
    /// Zuletzt gewählte eigene Farbe (letztes Farbfeld).
    @AppStorage("classEditor.lastCustomColor") private var lastCustomColor = "#9C6830"

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
                    Label {
                        TextField("Kürzel (z. B. 7b)", text: $shortName)
                            .textInputAutocapitalization(.never)
                    } icon: {
                        Image(icon: .label)
                    }
                    Label {
                        TextField("Schuljahr", text: $schoolYear)
                    } icon: {
                        Image(icon: .calendar)
                    }
                }

                Section {
                    ForEach(subjects, id: \.self) { subject in
                        Text(SchoolClass.displayName(ofSubject: subject))
                    }
                    .onDelete { subjects.remove(atOffsets: $0) }
                    .onMove { subjects.move(fromOffsets: $0, toOffset: $1) }

                    NavigationLink {
                        SubjectPickerView(subjects: $subjects, preferred: settings.values.teacher.subjects)
                    } label: {
                        Label("Fach hinzufügen", icon: .graduationCap)
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
                    ConfirmButton(title: isNew ? loc("Anlegen") : loc("Sichern"), action: save)
                        .glassToolbarButton(prominent: true)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var selectionCheck: some View {
        Image(icon: .check)
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
                get: { Color(hex: isCustomColor ? colorRaw : lastCustomColor) ?? accent },
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
        target.removeBoardPhotosOfRemovedSubjects(in: modelContext)
        target.removeChecklistsOfRemovedSubjects(in: modelContext)
        try? modelContext.save()
        onSave(target)
        dismiss()
    }
}

/// Unterseite „Fach hinzufügen“: Vorschläge an- und abhaken (Reihenfolge = Reihenfolge des Antippens).
/// `preferred` (Hauptfächer aus dem Profil) steht in einem eigenen Abschnitt oben.
struct SubjectPickerView: View {
    @Binding var subjects: [String]
    var preferred: [String] = []
    var title = loc("Fächer")

    @State private var customSubject = ""

    private var others: [String] {
        SchoolClass.suggestedSubjects.filter { !preferred.contains($0) }
    }

    /// Gewählte Fächer, die weder vorgeschlagen noch Hauptfach sind (selbst eingegeben).
    private var customSubjects: [String] {
        subjects.filter { !SchoolClass.suggestedSubjects.contains($0) && !preferred.contains($0) }
    }

    var body: some View {
        List {
            if preferred.isEmpty {
                ForEach(SchoolClass.suggestedSubjects, id: \.self, content: row)
            } else {
                Section("Ihre Hauptfächer") {
                    ForEach(preferred, id: \.self, content: row)
                }
                Section("Weitere Fächer") {
                    ForEach(others, id: \.self, content: row)
                }
            }

            Section("Eigene Fächer") {
                ForEach(customSubjects, id: \.self, content: row)
                HStack {
                    TextField("Eigenes Fach", text: $customSubject)
                        .onSubmit(addCustomSubject)
                    Button("Hinzufügen", icon: .check, action: addCustomSubject)
                        .labelStyle(.iconOnly)
                        .disabled(customSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addCustomSubject() {
        let subject = customSubject.trimmingCharacters(in: .whitespaces)
        guard !subject.isEmpty else { return }
        if !subjects.contains(subject) { subjects.append(subject) }
        customSubject = ""
    }

    private func row(_ subject: String) -> some View {
        let isSelected = subjects.contains(subject)
        return Button {
            if isSelected {
                subjects.removeAll { $0 == subject }
            } else {
                subjects.append(subject)
            }
        } label: {
            HStack {
                Text(SchoolClass.displayName(ofSubject: subject))
                    .foregroundStyle(Color.primary)
                Spacer()
                if isSelected {
                    Image(icon: .check)
                        .iconSize(20)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
