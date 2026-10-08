import QuickLook
import SwiftData
import SwiftUI

/// Schülerakte für ein Fach: Mündlich (Beobachtungen als Zeitleiste) und Fehlzeiten.
/// Einträge antippen zum Bearbeiten (Änderungen werden vermerkt), nach links wischen zum Löschen.
/// Im Privatsphäre-Modus geschwärzt und nur lesend.
struct StudentRecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var schoolSettings
    let student: Student
    let subject: String

    enum Segment: String, CaseIterable, Identifiable {
        case oral, assessments, absences
        var id: String { rawValue }

        var title: String {
            switch self {
            case .oral: loc("Mündlich")
            case .assessments: loc("Leistungen")
            case .absences: loc("Fehlzeiten")
            }
        }
    }

    @State private var segment: Segment = .oral
    @State private var observationRoute: ObservationEditorRoute?
    @State private var absenceRoute: AbsenceEditorRoute?
    @State private var isSettingsPresented = false
    @State private var pdfPreview: URL?

    private var settings: RecordSettings {
        student.schoolClass?.recordSettings(for: subject, schoolType: schoolSettings.values.schoolType)
            ?? RecordSettings.defaults(className: "", schoolType: nil)
    }

    private var observations: [StudentObservation] { student.observations(in: subject) }

    private var absences: [Absence] {
        student.absences.filter { $0.subject == subject }.sorted { ($0.day, $0.slotIndex) > ($1.day, $1.slotIndex) }
    }

    private var canEdit: Bool { !security.isPrivacyModeOn }

    var body: some View {
        List {
            Section {
                StudentNameRow(
                    student: student,
                    size: 56,
                    detail: student.schoolClass.map { "\($0.title) · \(SchoolClass.displayName(ofSubject: subject))" },
                    showsContactButtons: true
                )
            }
            switch segment {
            case .oral: oralSections
            case .assessments: StudentAssessmentSections(student: student, subject: subject, system: settings.gradeSystem)
            case .absences: absenceSections
            }
        }
        // Platz für die schwebende Leiste unten.
        .contentMargins(.bottom, 72, for: .scrollContent)
        .floatingBottomBar {
            FloatingSegmentedPicker(title: loc("Bereich"), selection: $segment) {
                ForEach(Segment.allCases) { Text($0.title).tag($0) }
            }
        }
        .navigationTitle(SchoolClass.displayName(ofSubject: subject))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $observationRoute) { route in
            ObservationEditorView(route: route, scale: settings.scale, slots: schoolSettings.slots)
        }
        .sheet(item: $absenceRoute) { route in
            AbsenceEditorView(route: route, slots: schoolSettings.slots)
        }
        .sheet(isPresented: $isSettingsPresented) {
            if let schoolClass = student.schoolClass {
                RecordSettingsView(schoolClass: schoolClass, subject: subject)
            }
        }
        .quickLookPreview($pdfPreview)
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                pdfPreview = nil
                observationRoute = nil
                absenceRoute = nil
                isSettingsPresented = false
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Beobachtung hinzufügen", icon: .plus) { observationRoute = .new(student, subject: subject) }
                Button("Fehlzeit hinzufügen", icon: .plus) { absenceRoute = .new(student, subject: subject) }
                Divider()
                // Vorschau (Quick Look): dort sichern, drucken oder teilen.
                Button("Als PDF exportieren", icon: .page) { pdfPreview = StudentRecordPDF.make(student: student, subject: subject) }
                Button("Bewertung einstellen", icon: .settings) { isSettingsPresented = true }
            } label: {
                Label("Hinzufügen", icon: .plus)
            }
            .disabled(!canEdit)
            .toolbarGroupBackground()
        }
        AppToolbarSpacer(placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            PrivacyModeButton()
                .toolbarGroupBackground()
        }
    }

    // MARK: Mündlich

    @ViewBuilder
    private var oralSections: some View {
        let ratings = observations.filter { $0.kind == .rating }
        Section {
            HStack(spacing: 8) {
                metric(loc("Beobachtungen"), value: "\(observations.count)")
                metric(loc("Häufigste"), value: StudentRecordFormat.mostFrequent(ratings) ?? "–")
                metric(loc("Letzte"), value: ratings.first?.label ?? "–")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text(loc("Skala: \(settings.scale.title)"))
        }
        if observations.isEmpty {
            Section {
                Text("Noch keine Beobachtungen. Im Sitzplan den Schüler antippen oder oben + verwenden.")
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(StudentRecordFormat.monthGroups(observations), id: \.title) { group in
            Section(group.title) {
                ForEach(group.items) { observation in
                    Button {
                        if canEdit { observationRoute = .edit(observation) }
                    } label: {
                        ObservationRow(observation: observation, slots: schoolSettings.slots)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if canEdit {
                            Button("Löschen", icon: .trash, role: .destructive) { delete(observation) }
                                .tint(.red)
                        }
                    }
                }
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .sensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Fehlzeiten

    @ViewBuilder
    private var absenceSections: some View {
        let absentCount = absences.filter { $0.kind == .absent }.count
        let lateCount = absences.count - absentCount
        Section {
            HStack(spacing: 8) {
                metric(loc("Abwesend"), value: StudentRecordFormat.lessons(absentCount))
                metric(loc("Verspätet"), value: "\(lateCount)×")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        Section {
            if absences.isEmpty {
                Text("Keine Fehlzeiten in diesem Fach.")
                    .foregroundStyle(.secondary)
            }
            ForEach(absences) { absence in
                Button {
                    if canEdit { absenceRoute = .edit(absence) }
                } label: {
                    AbsenceRow(absence: absence, slots: schoolSettings.slots)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    if canEdit {
                        Button("Löschen", icon: .trash, role: .destructive) { delete(absence) }
                            .tint(.red)
                    }
                }
            }
        }
    }

    // MARK: Löschen

    private func delete(_ model: some PersistentModel) {
        modelContext.delete(model)
        try? modelContext.save()
    }
}

/// Zeile einer Beobachtung: Datum, Stunde, Notiz bzw. Änderungsvermerk; rechts der Wert.
private struct ObservationRow: View {
    @Environment(\.device) private var device
    let observation: StudentObservation
    let slots: [LessonSlot]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // iPad: Notiz neben dem Datum (genug Platz), iPhone: darunter.
                if device.isPad {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(StudentRecordFormat.dateLine(observation.date, slotIndex: observation.slotIndex, slots: slots))
                            .fixedSize()
                        note
                    }
                } else {
                    Text(StudentRecordFormat.dateLine(observation.date, slotIndex: observation.slotIndex, slots: slots))
                    note
                }
                if let edited = observation.editedAt {
                    Text(loc("Nachträglich geändert am \(edited.appDate) (vorher „\(observation.previousLabel)“)"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Group {
                if observation.kind == .rating, let icon = observation.scale.icon(for: observation.value) {
                    Image(icon: icon).iconSize(24).accessibilityLabel(observation.label)
                } else {
                    Text(observation.label)
                }
            }
                .font(observation.kind == .rating ? .title3.weight(.bold) : .subheadline)
                .foregroundStyle(StudentRecordFormat.color(for: observation))
                .sensitive()
        }
        .contentShape(.rect)
    }
}

extension ObservationRow {
    @ViewBuilder
    fileprivate var note: some View {
        if !observation.note.isEmpty {
            Text(observation.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .sensitive()
        }
    }
}

/// Zeile einer Fehlzeit: Datum und Stunde; „verspätet“ mit Uhrzeit und Minuten.
private struct AbsenceRow: View {
    let absence: Absence
    let slots: [LessonSlot]

    var body: some View {
        HStack {
            Text(StudentRecordFormat.dateLine(absence.day, slotIndex: absence.slotIndex, slots: slots, showsTime: false))
            Spacer()
            Text(detail)
                .foregroundStyle(absence.kind == .absent ? Color.primary : Color.orange)
                .sensitive()
        }
        .contentShape(.rect)
    }

    private var detail: String {
        guard absence.kind == .late else { return Absence.Kind.absent.title }
        let time = absence.arrivedAt.map(\.appTime) ?? "–"
        if let minutes = absence.lateMinutes(slots: slots) { return loc("Verspätet · \(time) (\(minutes) min)") }
        return loc("Verspätet · \(time)")
    }
}

/// Texte und Gruppierung der Schülerakte.
enum StudentRecordFormat {
    static func count(_ count: Int) -> String {
        count == 1 ? loc("1 Beobachtung") : loc("\(count) Beobachtungen")
    }

    static func lessons(_ count: Int) -> String {
        count == 1 ? loc("1 Stunde") : loc("\(count) Stunden")
    }

    /// „Di 6. Okt · 3. Std“ (optional mit Uhrzeit, wenn ohne Stunde).
    static func dateLine(_ date: Date, slotIndex: Int, slots: [LessonSlot], showsTime: Bool = true) -> String {
        let day = date.appDate
        if let slot = slots.first(where: { $0.index == slotIndex }) { return loc("\(day) · \(slot.number). Std") }
        return showsTime ? date.appDateTime : day
    }

    /// Häufigster Bewertungswert (bei Gleichstand der neuere).
    static func mostFrequent(_ ratings: [StudentObservation]) -> String? {
        let counts = Dictionary(grouping: ratings, by: \.label).mapValues(\.count)
        return ratings.map(\.label).max { counts[$0, default: 0] < counts[$1, default: 0] }
    }

    static func color(for observation: StudentObservation) -> Color {
        guard observation.kind == .rating else { return .secondary }
        switch ObservationScale.tone(of: observation.value) {
        case .negative: return .red
        case .neutral: return .primary
        case .positive: return observation.scale == .counter ? .primary : .green
        }
    }

    struct MonthGroup {
        let title: String
        let items: [StudentObservation]
    }

    /// Nach Monat gruppiert, neueste zuerst.
    static func monthGroups(_ observations: [StudentObservation]) -> [MonthGroup] {
        var groups: [MonthGroup] = []
        for observation in observations {
            let title = observation.date.formatted(.dateTime.month(.wide).year())
            if groups.last?.title == title {
                groups[groups.count - 1] = MonthGroup(title: title, items: groups[groups.count - 1].items + [observation])
            } else {
                groups.append(MonthGroup(title: title, items: [observation]))
            }
        }
        return groups
    }
}

/// Wert einer Skala: Icon (Daumen) oder Text (− − − bis + + +, Smileys).
struct ScaleOptionLabel: View {
    let option: ObservationScale.Option
    var iconSize: CGFloat = 24

    var body: some View {
        if let icon = option.icon {
            Image(icon: icon)
                .iconSize(iconSize)
                .accessibilityLabel(option.label)
        } else {
            Text(option.label)
        }
    }
}
