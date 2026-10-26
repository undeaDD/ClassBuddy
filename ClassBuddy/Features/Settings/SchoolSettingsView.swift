import SwiftData
import SwiftUI

/// Einstellungen → Schuleinstellungen: Schule, Stundenraster, Pausen, Kalender, Ferien.
struct SchoolSettingsView: View {
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openURL) private var openURL
    @Query private var holidays: [Holiday]
    @AppStorage(AppPreference.hasOpenedSchoolSettings) private var hasOpenedSchoolSettings = false

    @State private var isImporting = false
    /// Aus PLZ und Ort erkanntes Bundesland (Hinweis im Footer).
    @State private var detectedState: String?
    @FocusState private var focus: Field?

    /// Tab-Reihenfolge mit externer Tastatur (`tabOrder`): nur die Adressfelder, die Schulform wird übersprungen.
    private enum Field: Hashable, CaseIterable {
        case name, website, street, postalCode, city, phone, email
    }

    var body: some View {
        @Bindable var settings = settings
        let school = $settings.values.school
        Form {
            Section {
                TextField("Name der Schule", text: school.name)
                    .textContentType(.organizationName)
                    .tabOrder(.name, in: Field.allCases, focus: $focus)
                Picker("Schulform", selection: $settings.values.schoolType) {
                    Text("Nicht festgelegt").tag(SchoolType?.none)
                    ForEach(SchoolType.allCases) { Text($0.title).tag(Optional($0)) }
                }
                HStack {
                    TextField("Website", text: school.website)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .tabOrder(.website, in: Field.allCases, focus: $focus)
                    if let url = settings.values.school.websiteURL {
                        Button("Öffnen", icon: .navArrowRight) { openURL(url) }
                            .labelStyle(.iconOnly)
                    }
                }
                TextField("Straße und Hausnummer", text: school.street)
                    .textContentType(.fullStreetAddress)
                    .tabOrder(.street, in: Field.allCases, focus: $focus)
                HStack {
                    TextField("PLZ", text: school.postalCode)
                        .textContentType(.postalCode)
                        .keyboardType(.numberPad)
                        .tabOrder(.postalCode, in: Field.allCases, focus: $focus)
                        .frame(maxWidth: 100)
                    TextField("Ort", text: school.city)
                        .textContentType(.addressCity)
                        .tabOrder(.city, in: Field.allCases, focus: $focus)
                }
                TextField("Telefon (Sekretariat)", text: school.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .tabOrder(.phone, in: Field.allCases, focus: $focus)
                TextField("E-Mail (Sekretariat)", text: school.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tabOrder(.email, in: Field.allCases, focus: $focus)
            } header: {
                Text("Schule")
            } footer: {
                Text(schoolFooter)
            }

            Section {
                DatePicker("Beginn", selection: timeBinding($settings.values.dayStart), displayedComponents: .hourAndMinute)
                DatePicker("Ende", selection: timeBinding($settings.values.dayEnd), displayedComponents: .hourAndMinute)
                Stepper("Stundenlänge: \(settings.values.lessonDuration) min", value: $settings.values.lessonDuration, in: 5...120, step: 5)
            } header: {
                Text("Schultag")
            }

            Section {
                ForEach($settings.values.breaks) { $pause in
                    // Etwas mehr Abstand vor der Dauer, damit er dem Abstand Dauer ↔ Stepper entspricht.
                    HStack(spacing: 16) {
                        DatePicker("Pause", selection: timeBinding($pause.start), displayedComponents: .hourAndMinute)
                        Stepper(value: $pause.duration, in: 5...120, step: 5) {
                            Text("\(pause.duration) min")
                                .monospacedDigit()
                        }
                        .fixedSize()
                    }
                }
                .onDelete { settings.values.breaks.remove(atOffsets: $0) }

                Button("Pause hinzufügen", icon: .plus) {
                    let start = settings.slots.last?.end ?? settings.values.dayStart
                    // Die Liste löst den Button beim Einfügen der Zeile darüber teils doppelt aus; eine zweite Pause
                    // mit demselben Beginn wäre ohnehin sinnlos.
                    guard !settings.values.breaks.contains(where: { $0.start == start }) else { return }
                    settings.values.breaks.append(BreakTime(start: start, duration: 15))
                }
            } header: {
                Text("Pausen")
            } footer: {
                Text("Zum Entfernen nach links wischen.")
            }

            Section("Stundenraster") {
                if settings.slots.isEmpty {
                    Text("Keine Stunden – Beginn, Ende und Stundenlänge prüfen.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.slots) { slot in
                    LabeledContent("\(slot.number). Stunde", value: slot.timeRange)
                        .monospacedDigit()
                }
            }

            Section {
                NavigationLink {
                    AssessmentTypesView()
                        .hidesTabBar()
                } label: {
                    Label("Leistungsarten und Bereiche", icon: .graduationCap)
                }
            } header: {
                Text("Bewertungen")
            } footer: {
                Text("Skala und Notensystem stellen Sie je Klasse und Fach in der Schülerakte ein.")
            }

            Section("Kalender") {
                Toggle(isOn: $settings.values.showWeekends) {
                    Label("Wochenende anzeigen", icon: .calendar)
                }
            }

            Section {
                // 16 Länder: eigene Unterseite statt Menü.
                Picker(selection: $settings.values.federalState) {
                    Text("Keins").tag(String?.none)
                    ForEach(HolidayImporter.federalStates, id: \.code) { state in
                        Text(HolidayImporter.displayName(ofState: state.code)).tag(Optional(state.code))
                    }
                } label: {
                    Label("Bundesland", icon: .globe)
                }
                .pickerStyle(.navigationLink)
                Button {
                    Task { await importHolidays() }
                } label: {
                    SettingsActionLabel(title: loc("Ferien & Feiertage importieren"), icon: .cloudDownload, isLoading: isImporting)
                }
                .disabled(settings.values.federalState == nil || isImporting)

                if !holidays.isEmpty {
                    LabeledContent(
                        loc("\(holidays.count) Ferien und Feiertage"),
                        value: HolidayImporter.loadedUntil(holidays).map { loc("bis \($0.appDate)") } ?? ""
                    )
                }
            } header: {
                Text("Ferien & Feiertage")
            } footer: {
                Text(importFooter)
            }
        }
        .navigationTitle("Schuleinstellungen")
        .onAppear { hasOpenedSchoolSettings = true }
        // Bundesland aus PLZ und Ort (über dieselbe Ortssuche wie das Wetter, kurz nach der letzten Eingabe).
        .task(id: "\(settings.values.school.postalCode)|\(settings.values.school.city)") {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let code = await WeatherService.federalStateCode(for: settings.values.school) else { return }
            detectedState = code
            settings.values.federalState = code
        }
    }

    private var schoolFooter: String {
        var text = loc("Die Adresse bestimmt Wetter und Ferien, Telefon und E-Mail die Kachel „Sekretariat“.")
        if let detected = detectedState {
            text += " " + loc("Bundesland erkannt: \(HolidayImporter.displayName(ofState: detected)).")
        }
        return text
    }

    private var importFooter: String {
        var parts = [loc("""
            Derzeit nur für deutsche Bundesländer. Quelle: OpenHolidays API (openholidaysapi.org). \
            Es werden nur öffentliche Ferientermine abgerufen.
            """)]
        if let date = settings.values.holidaysImportedAt {
            parts.append(loc("Zuletzt importiert: \(date.appDateTime)."))
        }
        return parts.joined(separator: " ")
    }

    private func importHolidays() async {
        isImporting = true
        defer { isImporting = false }
        await HolidayImporter.importAndReport(settings: settings, context: modelContext, toasts: toasts)
    }

    /// Minuten seit Mitternacht ↔ Date (für DatePicker).
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.school.date(byAdding: .minute, value: minutes.wrappedValue, to: Calendar.school.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let parts = Calendar.school.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
