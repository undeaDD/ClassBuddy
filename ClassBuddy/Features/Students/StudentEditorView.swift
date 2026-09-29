import SwiftData
import SwiftUI

enum StudentEditorRoute: Identifiable {
    case new(SchoolClass)
    case edit(Student)

    var id: String {
        switch self {
        case .new(let schoolClass): "new-\(schoolClass.id)"
        case .edit(let student): student.id.uuidString
        }
    }
}

/// Vollbild-Formular für Schüler-Stammdaten. Übernahme erst bei „Sichern“.
struct StudentEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let route: StudentEditorRoute

    @State private var firstName: String
    @State private var lastName: String
    @State private var birthday: Date?
    @State private var gender: Gender?
    @State private var notes: String

    init(route: StudentEditorRoute) {
        self.route = route
        let student: Student? = if case .edit(let student) = route { student } else { nil }
        _firstName = State(initialValue: student?.firstName ?? "")
        _lastName = State(initialValue: student?.lastName ?? "")
        _birthday = State(initialValue: student?.birthday)
        _gender = State(initialValue: student?.gender)
        _notes = State(initialValue: student?.notes ?? "")
    }

    private var isNew: Bool {
        if case .new = route { true } else { false }
    }

    private var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            || !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Vorname", text: $firstName)
                        .textContentType(.givenName)
                        .sensitive()
                    TextField("Nachname", text: $lastName)
                        .textContentType(.familyName)
                        .sensitive()
                }

                Section("Geschlecht") {
                    GenderPicker(selection: $gender)
                }

                Section {
                    BirthdayField(birthday: $birthday, suggestedAge: 12)
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(4...12)
                        .sensitive()
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isNew ? "Neuer Schüler" : "Schüler bearbeiten")
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

    private func save() {
        let student: Student
        switch route {
        case .new(let schoolClass):
            student = Student(firstName: "", lastName: "", schoolClass: schoolClass)
            modelContext.insert(student)
        case .edit(let existing):
            student = existing
        }
        student.firstName = firstName.trimmingCharacters(in: .whitespaces)
        student.lastName = lastName.trimmingCharacters(in: .whitespaces)
        student.birthday = birthday
        student.gender = gender
        student.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        dismiss()
    }
}
