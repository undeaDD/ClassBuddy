import PhotosUI
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
    @State private var photoSelection: PhotosPickerItem?
    /// Gewähltes Foto, bevor der Ausschnitt feststeht.
    @State private var cropRequest: CropRequest?

    private struct CropRequest: Identifiable {
        let id = UUID()
        let image: UIImage
    }

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
                    NameFields(firstName: $firstName, lastName: $lastName)
                }

                Section("Foto") {
                    photoRow
                }

                Section("Kontakt") {
                    ContactField(title: "Telefon", text: $phone, icon: .phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    ContactField(title: "E-Mail", text: $email, icon: .sendMail)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    ContactField(title: "Sonstiges (z. B. Eltern)", text: $otherContact, icon: .notes)
                }

                Section("Optional") {
                    GenderPicker(selection: $gender)
                    BirthdayField(birthday: $birthday, suggestedAge: 12)
                }

                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(4...12)
                        .sensitive()
                }
            }
            .readableFormWidth()
            .onChange(of: photoSelection) { _, item in
                guard let item else { return }
                photoSelection = nil
                Task {
                    // Für den Zuschnitt auf 2048 px verkleinern – große Fotos bleiben so flüssig.
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let prepared = StudentPhoto.prepare(data, maxPixel: 2048),
                          let image = UIImage(data: prepared)
                    else { return }
                    cropRequest = CropRequest(image: image)
                }
            }
            .fullScreenCover(item: $cropRequest) { request in
                PhotoCropView(image: request.image) { photo = $0 }
            }
            .navigationTitle(isNew ? "Neuer Schüler" : "Schüler bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: isNew ? loc("Anlegen") : loc("Sichern"), action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var initials: String {
        [firstName.first, lastName.first].compactMap { $0 }.map(String.init).joined()
    }

    /// Foto wählen bzw. ändern; das x entfernt es wieder (wie beim Geburtstag).
    private var photoRow: some View {
        HStack {
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Label {
                    Text(photo == nil ? "Foto auswählen" : "Foto ändern")
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(icon: .image)
                }
            }
            Spacer()
            if photo != nil {
                Button("Foto entfernen", icon: .xmark) { photo = nil }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .buttonStyle(.borderless)
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
        student.phone = phone.trimmingCharacters(in: .whitespaces)
        student.email = email.trimmingCharacters(in: .whitespaces)
        student.otherContact = otherContact.trimmingCharacters(in: .whitespacesAndNewlines)
        student.photo = photo
        try? modelContext.save()
        dismiss()
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
