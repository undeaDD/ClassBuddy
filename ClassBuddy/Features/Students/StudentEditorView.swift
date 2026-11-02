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
    @State private var phone: String
    @State private var email: String
    @State private var otherContact: String
    @State private var photo: Data?
    /// Nach dem Anlegen offen bleiben (geleert) für den nächsten Schüler.
    @State private var keepOpen = false
    @State private var lastCreated: String?
    @FocusState private var focus: PersonField?

    init(route: StudentEditorRoute) {
        self.route = route
        let student: Student? = if case .edit(let student) = route { student } else { nil }
        _firstName = State(initialValue: student?.firstName ?? "")
        _lastName = State(initialValue: student?.lastName ?? "")
        _birthday = State(initialValue: student?.birthday)
        _gender = State(initialValue: student?.gender)
        _notes = State(initialValue: student?.notes ?? "")
        _phone = State(initialValue: student?.phone ?? "")
        _email = State(initialValue: student?.email ?? "")
        _otherContact = State(initialValue: student?.otherContact ?? "")
        _photo = State(initialValue: student?.photo)
    }

    /// Tab-Reihenfolge mit externer Tastatur: nur die Textfelder, Foto, Geschlecht und Geburtstag werden übersprungen.
    private static let tabOrder: [PersonField] = [.firstName, .lastName, .phone, .email, .otherContact, .notes]

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
                Section {
                    StudentAvatar(initials: initials, photo: photo, gender: gender, size: 88)
                        .environment(\.avatarCutout, [Color(.systemGroupedBackground)])
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section("Name") {
                    NameFields(firstName: $firstName, lastName: $lastName, focus: $focus, order: Self.tabOrder)
                }

                Section("Foto") {
                    ProfilePhotoRow(photo: $photo)
                }

                Section("Kontakt") {
                    ContactField(title: "Telefon", text: $phone, icon: .phone)
                        .tabOrder(.phone, in: Self.tabOrder, focus: $focus)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    ContactField(title: "E-Mail", text: $email, icon: .sendMail)
                        .tabOrder(.email, in: Self.tabOrder, focus: $focus)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ContactField(title: "Sonstiges (z. B. Eltern)", text: $otherContact, icon: .notes)
                        .tabOrder(.otherContact, in: Self.tabOrder, focus: $focus)
                }

                Section("Optional") {
                    GenderPicker(selection: $gender)
                    BirthdayField(birthday: $birthday, suggestedAge: 12)
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(4...12)
                        .tabOrder(.notes, in: Self.tabOrder, focus: $focus)
                        .sensitive()
                }

                if isNew {
                    KeepOpenSection(keepOpen: $keepOpen, lastCreated: lastCreated)
                }
            }
            .readableFormWidth()
            .onAppear {
                guard isNew else { return }
                focus = .firstName
                lastCreated = LastCreated.student(in: modelContext)?.fullName
            }
            .navigationTitle(isNew ? "Neuer Schüler" : "Schüler bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                        .toolbarGroupBackground()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: isNew ? loc("Anlegen") : loc("Sichern"), action: save)
                        .disabled(!isValid)
                        .toolbarGroupBackground(prominent: true)
                }
            }
        }
    }

    private var initials: String {
        [firstName.first, lastName.first].compactMap { $0 }.map(String.init).joined()
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
        student.phone = phone.trimmingCharacters(in: .whitespaces)
        student.email = email.trimmingCharacters(in: .whitespaces)
        student.otherContact = otherContact.trimmingCharacters(in: .whitespacesAndNewlines)
        student.photo = photo
        try? modelContext.save()
        if isNew {
            LastCreated.record(student.id, as: .student)
            lastCreated = student.fullName
        }
        if isNew && keepOpen {
            clearForm()
        } else {
            dismiss()
        }
    }

    /// Leert das Formular für den nächsten Schüler und setzt den Fokus wieder auf den Vornamen.
    private func clearForm() {
        firstName = ""
        lastName = ""
        birthday = nil
        gender = nil
        notes = ""
        phone = ""
        email = ""
        otherContact = ""
        photo = nil
        focus = .firstName
    }
}

/// Eine Kontaktzeile: Icon vorne, Eingabefeld, im Privatsphäre-Modus verborgen.
private struct ContactField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let icon: AppIcon

    var body: some View {
        Label {
            TextField(title, text: $text)
                .sensitive()
        } icon: {
            Image(icon: icon)
        }
    }
}
