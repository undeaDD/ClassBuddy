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
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                // Gleiche Farben wie in der Schnell-Leiste: rot negativ, grau neutral, grün positiv.
                                .buttonStyle(RatingButtonStyle(
                                    tone: activeScale == .counter ? .positive : ObservationScale.tone(of: option.value),
                                    isSelected: value == option.value
                                ))
                            }
                        }
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

    private func load() {
        switch route {
        case .new:
            value = activeScale.options.first { $0.value == 0 }?.value ?? activeScale.options.last?.value ?? 0
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
            modelContext.insert(StudentObservation(
                subject: subject, date: date, slotIndex: slotIndex, kind: kind, scale: activeScale, value: value, note: cleanNote,
                student: student
            ))
            FunStat.observations.increment()
        case .edit(let observation):
            observation.update(kind: kind, scale: activeScale, value: value, note: cleanNote, date: date)
            observation.slotIndex = slotIndex
        }
        try? modelContext.save()
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

/// Bewertung einer Klasse in einem Fach: Skala für Beobachtungen, Notensystem, schriftliche Arbeiten.
struct RecordSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SchoolSettings.self) private var schoolSettings
    let schoolClass: SchoolClass
    let subject: String

    @State private var values = RecordSettings(scale: .sevenStep, gradeSystem: .grades, hasWrittenWork: true, stage: .secondary)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Skala", selection: $values.scale) {
                        ForEach(ObservationScale.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Beobachtungen im Unterricht")
                } footer: {
                    Text("Bisherige Beobachtungen behalten ihre Skala.")
                }
                Section {
                    Picker(selection: $values.gradeSystem) {
                        ForEach(GradeSystem.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label("Notensystem", icon: .graduationCap)
                    }
                    Toggle(isOn: $values.hasWrittenWork) {
                        Label("Schriftliche Arbeiten", icon: .page)
                    }
                } header: {
                    Text("Noten")
                } footer: {
                    Text(loc("""
                        Vorgaben für \(values.stage.title) (aus „\(schoolClass.shortName)“ und der Schulform in den Schuleinstellungen). \
                        Gilt nur für \(schoolClass.title) in \(SchoolClass.displayName(ofSubject: subject)).
                        """))
                }
            }
            .navigationTitle("Bewertung")
            .appNavigationSubtitle(SchoolClass.displayName(ofSubject: subject))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                        .toolbarGroupBackground()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: loc("Sichern")) {
                        schoolClass.setRecordSettings(values, for: subject, in: modelContext)
                        try? modelContext.save()
                        dismiss()
                    }
                        .toolbarGroupBackground(prominent: true)
                }
            }
        }
        .onAppear { values = schoolClass.recordSettings(for: subject, schoolType: schoolSettings.values.schoolType) }
    }
}
