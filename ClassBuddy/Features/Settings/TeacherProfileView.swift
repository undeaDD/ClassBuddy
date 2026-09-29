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
                Picker("Geschlecht", selection: teacher.gender) {
                    ForEach(Gender.allCases) { option in
                        Text(option.title).tag(Optional(option))
                    }
                    Text("keine Angabe").tag(Gender?.none)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Geburtstag", isOn: Binding(
                    get: { settings.values.teacher.birthday != nil },
                    set: { isOn in
                        settings.values.teacher.birthday = isOn
                            ? Calendar.school.date(byAdding: .year, value: -35, to: .now)
                            : nil
                    }
                ).animation())
                if let birthday = settings.values.teacher.birthday {
                    DatePicker(
                        "Datum",
                        selection: Binding(get: { birthday }, set: { settings.values.teacher.birthday = $0 }),
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .sensitive()
                }
            }
        }
        .disabled(security.isPrivacyModeOn)
        .navigationTitle("Mein Profil")
    }
}
