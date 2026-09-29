import SwiftData
import SwiftUI

/// Einstellungen → Schuleinstellungen: Schule, Stundenraster, Pausen, Kalender, Ferien.
struct SchoolSettingsView: View {
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \Holiday.startDate) private var holidays: [Holiday]

    @State private var isImporting = false
    @State private var importMessage: String?

    var body: some View {
        @Bindable var settings = settings
        let school = $settings.values.school
        Form {
            Section("Schule") {
                TextField("Name der Schule", text: school.name)
                    .textContentType(.organizationName)
                HStack {
                    TextField("Website", text: school.website)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let url = settings.values.school.websiteURL {
                        Button("Öffnen", image: .navArrowRight) { openURL(url) }
                            .labelStyle(.iconOnly)
                    }
                }
                TextField("Straße und Hausnummer", text: school.street)
                    .textContentType(.fullStreetAddress)
                HStack {
                    TextField("PLZ", text: school.postalCode)
                        .textContentType(.postalCode)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 100)
                    TextField("Ort", text: school.city)
                        .textContentType(.addressCity)
                }
                TextField("Telefon (Sekretariat)", text: school.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField("E-Mail (Sekretariat)", text: school.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
                    HStack {
                        DatePicker("Pause", selection: timeBinding($pause.start), displayedComponents: .hourAndMinute)
                        Stepper("\(pause.duration) min", value: $pause.duration, in: 5...120, step: 5)
                            .fixedSize()
                    }
                }
                .onDelete { settings.values.breaks.remove(atOffsets: $0) }

                Button("Pause hinzufügen", systemImage: "plus.circle.fill") {
                    let start = settings.slots.last?.end ?? settings.values.dayStart
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

            Section("Kalender") {
                Toggle("Wochenende anzeigen", isOn: $settings.values.showWeekends)
            }

            Section {
                Picker("Bundesland", selection: $settings.values.federalState) {
                    Text("Keins").tag(String?.none)
                    ForEach(HolidayImporter.federalStates, id: \.code) { state in
                        Text(state.name).tag(Optional(state.code))
                    }
                }
                Button {
                    Task { await importHolidays() }
                } label: {
                    HStack {
                        Label("Ferien & Feiertage importieren", systemImage: "arrow.down.circle")
                        if isImporting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(settings.values.federalState == nil || isImporting)

                if !upcomingHolidays.isEmpty {
                    ForEach(upcomingHolidays) { holiday in
                        LabeledContent(holiday.name, value: dateRange(holiday))
                    }
                }
            } header: {
                Text("Ferien & Feiertage")
            } footer: {
                Text(importFooter)
            }
        }
        .navigationTitle("Schuleinstellungen")
    }

    private var upcomingHolidays: [Holiday] {
        let today = Calendar.school.startOfDay(for: .now)
        return Array(holidays.filter { $0.endDate >= today }.prefix(6))
    }

    private var importFooter: String {
        var parts = ["Quelle: OpenHolidays API (openholidaysapi.org). Es werden nur öffentliche Ferientermine abgerufen."]
        if let message = importMessage {
            parts.append(message)
        } else if let date = settings.values.holidaysImportedAt {
            parts.append("Zuletzt importiert: \(date.formatted(date: .abbreviated, time: .shortened)).")
        }
        return parts.joined(separator: " ")
    }

    private func dateRange(_ holiday: Holiday) -> String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return Calendar.school.isDate(holiday.startDate, inSameDayAs: holiday.endDate)
            ? holiday.startDate.formatted(style)
            : "\(holiday.startDate.formatted(style)) – \(holiday.endDate.formatted(style))"
    }

    private func importHolidays() async {
        guard let state = settings.values.federalState else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let count = try await HolidayImporter.importHolidays(for: state, into: modelContext)
            settings.values.holidaysImportedAt = .now
            importMessage = "\(count) Einträge importiert."
        } catch {
            importMessage = error.localizedDescription
        }
    }

    /// Minuten seit Mitternacht ↔ Date (für DatePicker).
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.school.date(byAdding: .minute, value: minutes.wrappedValue, to: Calendar.school.startOfDay(for: .now)) ?? .now
            },
            set: { date in
                let c = Calendar.school.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
