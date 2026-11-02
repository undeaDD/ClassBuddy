import SwiftData
import SwiftUI

enum ObservationEditorRoute: Identifiable {
    case new(Student, subject: String)
    case edit(StudentObservation)

    var id: String {
        switch self {
        case .new(let student, let subject): "new-\(student.id)-\(subject)"
        case .edit(let observation): observation.id.uuidString
        }
    }
}

/// Beobachtung anlegen oder bearbeiten: Art, Wert auf der Skala, Datum, Stunde, Notiz.
/// Geänderte Bewertungen werden mit dem vorherigen Wert vermerkt.
struct ObservationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let route: ObservationEditorRoute
    /// Skala für neue Beobachtungen (bestehende behalten ihre).
    let scale: ObservationScale
    let slots: [LessonSlot]

    @State private var kind: StudentObservation.Kind = .rating
    @State private var value = 0
    @State private var date = Date.now
    @State private var slotIndex = -1
    @State private var note = ""
    /// Nach dem Anlegen offen bleiben (geleert) für die nächste Beobachtung.
    @State private var keepOpen = false
    @State private var lastCreated: String?

    private var isNew: Bool {
        if case .new = route { return true }
        return false
    }

    private var activeScale: ObservationScale {
        if case .edit(let observation) = route { return observation.scale }
        return scale
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(StudentObservation.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    if kind == .rating {
                        HStack(spacing: 6) {
                            ForEach(activeScale.options, id: \.value) { option in
                                Button {
                                    value = option.value
                                } label: {
                                    ScaleOptionLabel(option: option, iconSize: 22)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                                }
                                // Gleiche Farben wie in der Schnell-Leiste: rot negativ, grau neutral, grün positiv.
                                .buttonStyle(RatingButtonStyle(
                                    tone: activeScale == .counter ? .positive : ObservationScale.tone(of: option.value),
                                    isSelected: value == option.value
                                ))
                            }
                        }
                        // Alle gleich hoch, auch wenn „− − −“ übereinander steht.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    DatePicker(selection: $date) {
                        Label("Datum", icon: .calendar)
                    }
                    Picker(selection: $slotIndex) {
                        Text("Ohne Stunde").tag(-1)
                        ForEach(slots) { Text(loc("\($0.number). Stunde")).tag($0.index) }
                    } label: {
                        Label("Stunde", icon: .time)
                    }
                }
                Section("Notiz") {
                    TextField("Was ist aufgefallen?", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                        .sensitive()
                }
                if isNew {
                    KeepOpenSection(keepOpen: $keepOpen, lastCreated: lastCreated)
                }
            }
            .navigationTitle(isNew ? "Neue Beobachtung" : "Beobachtung bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                        .toolbarGroupBackground()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: isNew ? loc("Anlegen") : loc("Sichern"), action: save)
                        .disabled(kind == .note && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .toolbarGroupBackground(prominent: true)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    /// „+ + · 03.11., 10:15“ (Bewertung bzw. Art und wann).
    private static func summary(of observation: StudentObservation) -> String {
        "\(observation.label) · \(observation.date.appFormatted(.dateTime.day().month().hour().minute()))"
    }

    private func load() {
        switch route {
        case .new(let student, let subject):
            value = activeScale.options.first { $0.value == 0 }?.value ?? activeScale.options.last?.value ?? 0
            lastCreated = student.observations(in: subject).max { $0.createdAt < $1.createdAt }.map(Self.summary)
        case .edit(let observation):
            kind = observation.kind
            value = observation.value
            date = observation.date
            slotIndex = observation.slotIndex
            note = observation.note
        }
    }

    private func save() {
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch route {
        case .new(let student, let subject):
            let observation = StudentObservation(
                subject: subject, date: date, slotIndex: slotIndex, kind: kind, scale: activeScale, value: value, note: cleanNote,
                student: student
            )
            modelContext.insert(observation)
            FunStat.observations.increment()
            try? modelContext.save()
            if keepOpen {
                // Gesichert: Notiz leeren, Art, Wert, Datum und Stunde für die nächste behalten.
                lastCreated = Self.summary(of: observation)
                note = ""
                Haptics.notify(.success)
                return
            }
        case .edit(let observation):
            observation.update(kind: kind, scale: activeScale, value: value, note: cleanNote, date: date)
            observation.slotIndex = slotIndex
            try? modelContext.save()
        }
        dismiss()
    }
}

enum AbsenceEditorRoute: Identifiable {
    case new(Student, subject: String)
    case edit(Absence)

    var id: String {
        switch self {
        case .new(let student, let subject): "new-\(student.id)-\(subject)"
        case .edit(let absence): absence.id.uuidString
        }
    }
}

/// Fehlzeit anlegen oder korrigieren: abwesend oder verspätet (mit Uhrzeit), Tag und Stunde.
struct AbsenceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let route: AbsenceEditorRoute
    let slots: [LessonSlot]

    @State private var kind: Absence.Kind = .absent
    @State private var day = Date.now
    @State private var slotIndex = -1
    @State private var arrivedAt = Date.now

    private var isNew: Bool {
        if case .new = route { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(Absence.Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    DatePicker(selection: $day, displayedComponents: .date) {
                        Label("Tag", icon: .calendar)
                    }
                    Picker(selection: $slotIndex) {
                        Text("Ohne Stunde").tag(-1)
                        ForEach(slots) { Text(loc("\($0.number). Stunde")).tag($0.index) }
                    } label: {
                        Label("Stunde", icon: .time)
                    }
                    if kind == .late {
                        DatePicker(selection: $arrivedAt, displayedComponents: .hourAndMinute) {
                            Label("Eingetroffen um", icon: .timer)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Neue Fehlzeit" : "Fehlzeit bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                        .toolbarGroupBackground()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: isNew ? loc("Anlegen") : loc("Sichern"), action: save)
                        .toolbarGroupBackground(prominent: true)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: load)
    }

    private func load() {
        guard case .edit(let absence) = route else { return }
        kind = absence.kind
        day = absence.day
        slotIndex = absence.slotIndex
        arrivedAt = absence.arrivedAt ?? .now
    }

    /// Uhrzeit des Eintreffens auf den gewählten Tag legen.
    private var arrival: Date {
        let calendar = Calendar.school
        let time = calendar.dateComponents([.hour, .minute], from: arrivedAt)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? arrivedAt
    }

    private func save() {
        switch route {
        case .new(let student, let subject):
            modelContext.insert(Absence(
                subject: subject, day: day, slotIndex: slotIndex, kind: kind, arrivedAt: kind == .late ? arrival : nil, student: student
            ))
        case .edit(let absence):
            absence.kind = kind
            absence.day = Calendar.school.startOfDay(for: day)
            absence.slotIndex = slotIndex
            absence.arrivedAt = kind == .late ? arrival : nil
        }
        try? modelContext.save()
        dismiss()
    }
}

/// Skala für Beobachtungen, Notensystem und schriftliche Arbeiten (Schuleinstellungen je Stufe, eigene Bewertung einer Klasse).
struct RecordChoiceSections: View {
    @Binding var choice: RecordChoice

    var body: some View {
        Section {
            Picker("Skala", selection: $choice.scale) {
                ForEach(ObservationScale.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Beobachtungen im Unterricht")
        } footer: {
            Text("Bisherige Beobachtungen behalten ihre Skala.")
        }
        Section("Noten") {
            Picker(selection: $choice.gradeSystem) {
                ForEach(GradeSystem.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Notensystem", icon: .graduationCap)
            }
            Toggle(isOn: $choice.hasWrittenWork) {
                Label("Schriftliche Arbeiten", icon: .page)
            }
        }
    }
}

/// Schuleinstellungen › Bewertung: je Stufe der Schulform Skala und Noten (Vorgabe der App oder eigene Wahl).
struct SchoolRecordSettingsView: View {
    @Environment(SchoolSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(SchoolStage.stages(of: settings.values.schoolType), id: \.self) { stage in
                    NavigationLink {
                        StageRecordSettingsView(stage: stage)
                            .hidesTabBar()
                    } label: {
                        LabeledContent {
                            Text(choice(for: stage).scale.title)
                                .lineLimit(1)
                        } label: {
                            Label(stage.title, icon: .settings)
                        }
                    }
                }
            } footer: {
                Text(loc("""
                    Gilt für alle Klassen der Stufe; die Stufe ergibt sich aus der Schulform und der Klassenbezeichnung. \
                    Einzelne Klassen können in ihren Einstellungen eine eigene Bewertung haben.
                    """))
            }
        }
        .navigationTitle("Bewertung")
    }

    private func choice(for stage: SchoolStage) -> RecordChoice {
        settings.values.stageChoices[stage] ?? stage.builtInChoice
    }
}

private struct StageRecordSettingsView: View {
    @Environment(SchoolSettings.self) private var settings
    let stage: SchoolStage

    var body: some View {
        Form {
            RecordChoiceSections(choice: Binding(
                get: { settings.values.stageChoices[stage] ?? stage.builtInChoice },
                set: { settings.values.recordChoices[stage.rawValue] = $0 == stage.builtInChoice ? nil : $0 }
            ))
            if settings.values.recordChoices[stage.rawValue] != nil {
                Section {
                    Button("Vorgabe wiederherstellen") { settings.values.recordChoices[stage.rawValue] = nil }
                }
            }
        }
        .navigationTitle(stage.title)
    }
}
