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
            Section("Name") {
                TextField("Vorname", text: teacher.firstName)
                    .textContentType(.givenName)
                    .sensitive()
                TextField("Nachname", text: teacher.lastName)
                    .textContentType(.familyName)
                    .sensitive()
            }

            Section("Geschlecht") {
                GenderPicker(selection: teacher.gender)
            }

            Section {
                BirthdayField(birthday: teacher.birthday, suggestedAge: 35)
            }
        }
        .disabled(security.isPrivacyModeOn)
        .navigationTitle("Mein Profil")
    }
}
