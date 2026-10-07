import SwiftUI

/// Einstellungen → Mein Profil: Daten der Lehrkraft.
/// Im Privatsphäre-Modus ausgeblendet und nicht bearbeitbar.
struct TeacherProfileView: View {
    @Environment(SchoolSettings.self) private var settings
    @Environment(AppSecurity.self) private var security

    var body: some View {
        @Bindable var settings = settings
        let teacher = $settings.values.teacher
        Form {
            Section {
                NameFields(firstName: teacher.firstName, lastName: teacher.lastName)
            } header: {
                Text("Name")
            } footer: {
                Text("Steht im Sitzplan am Lehrerpult und im Sitzplan-PDF.")
            }

            Section {
                NavigationLink {
                    SubjectPickerView(subjects: teacher.subjects, title: loc("Hauptfächer"))
                } label: {
                    LabeledContent {
                        Text(settings.values.teacher.subjects.isEmpty
                            ? loc("Keine")
                            : settings.values.teacher.subjects.map(SchoolClass.displayName(ofSubject:)).joined(separator: ", "))
                            .lineLimit(1)
                    } label: {
                        Label("Hauptfächer", icon: .graduationCap)
                    }
                }
            } footer: {
                Text("Stehen beim Anlegen einer Klasse oben in der Fächerauswahl.")
            }

            Section("Optional") {
                GenderPicker(selection: teacher.gender)
                BirthdayField(birthday: teacher.birthday, suggestedAge: 35)
            }
        }
        .disabled(security.isPrivacyModeOn)
        .navigationTitle("Mein Profil")
    }
}
