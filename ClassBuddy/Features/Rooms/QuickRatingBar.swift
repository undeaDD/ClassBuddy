import SwiftData
import SwiftUI

/// Schnell-Leiste im Sitzplan: Schüler antippen → Bewertung auf der Skala, Ereignisse, abwesend / verspätet, Notiz.
/// Ein Tipp speichert sofort; die letzte Bewertung lässt sich direkt in der Leiste zurücknehmen.
struct QuickRatingBar: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SchoolSettings.self) private var schoolSettings
    @Environment(\.device) private var device
    let student: Student
    let lesson: LessonContext
    let onOpenRecord: () -> Void
    let onClose: () -> Void

    @State private var lastSaved: StudentObservation?
    /// Ziehen nach unten zum Schließen.
    @State private var dragOffset: CGFloat = 0
    @State private var isNotePresented = false
    @State private var noteText = ""

    private var settings: RecordSettings {
        student.schoolClass?.recordSettings(for: lesson.subject, schoolType: schoolSettings.values.schoolType)
            ?? RecordSettings.defaults(className: "", schoolType: nil)
    }

    private var absence: Absence? { student.absence(in: lesson) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, -6)
                .accessibilityHidden(true)
            header
            scaleButtons
            eventButtons
            footer
        }
        .padding(18)
        .frame(maxWidth: 760)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color(.separator), lineWidth: 0.5))
        .padding(.horizontal, device.isPhone ? 12 : 24)
        .padding(.bottom, 16)
        // Inhalt bewegt sich als Ganzes mit der Leiste (sonst blenden die Knöpfe von oben ein).
        .geometryGroup()
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { dragOffset = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 80 || value.predictedEndTranslation.height > 200 {
                        onClose()
                    }
                    withAnimation(.smooth) { dragOffset = 0 }
                }
        )
        .onChange(of: student.id) { lastSaved = nil }
        .alert("Notiz", isPresented: $isNotePresented) {
            TextField("Was ist aufgefallen?", text: $noteText)
            Button("Sichern") { save(kind: .note, note: noteText) }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(student.fullName)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("Schließen", icon: .xmark, role: .appClose, action: onClose)
                .labelStyle(.iconOnly)
                .appGlassButtonStyle()
                .buttonBorderShape(.circle)
            StudentAvatar(student: student, size: 40)
            Text(student.fullName)
                .font(.headline)
                .lineLimit(1)
                .sensitive()
            Spacer(minLength: 8)
            Button("Details", action: onOpenRecord)
                .font(.subheadline.weight(.medium))
                .appGlassButtonStyle()
                .buttonBorderShape(.capsule)
        }
    }

    private var scaleButtons: some View {
        let options = settings.scale.options
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: options.count), spacing: 8) {
            ForEach(options, id: \.value) { option in
                Button {
                    save(kind: .rating, value: option.value)
                } label: {
                    ScaleOptionLabel(option: option, iconSize: 26)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(RatingButtonStyle(tone: settings.scale == .counter ? .positive : ObservationScale.tone(of: option.value)))
            }
        }
    }

    /// Alle Aktionen immer sichtbar: iPhone zwei Spalten, iPad eine Zeile mit vier.
    private var eventButtons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: device.isPhone ? 2 : 4), spacing: 8) {
            chip(loc("Hausaufgabe fehlt")) { save(kind: .homework) }
                chip(Absence.Kind.absent.title, isOn: absence?.kind == .absent) {
                    student.toggleAbsent(in: lesson, context: modelContext)
                    persist()
                }
                chip(lateTitle, isOn: absence?.kind == .late) {
                    student.toggleLate(in: lesson, context: modelContext)
                    persist()
                }
                chip(loc("Notiz …")) {
                    noteText = ""
                    isNotePresented = true
                }
        }
    }

    /// Hinweis links; nach dem Speichern rechts „Rückgängig“ für die letzte Eingabe.
    private var footer: some View {
        HStack(spacing: 12) {
            Text(lastSaved.map { loc("Gespeichert: \($0.label)") } ?? loc("Ein Tipp speichert sofort."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if lastSaved != nil {
                Button("Rückgängig", icon: .undo, action: undo)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .appGlassButtonStyle()
                    .buttonBorderShape(.capsule)
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 36)
    }

    private func chip(_ title: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: Haptics.tapping(action)) {
            Text(title)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .capsule)
                .overlay(Capsule().strokeBorder(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var lateTitle: String {
        guard absence?.kind == .late, let arrived = absence?.arrivedAt else { return Absence.Kind.late.title }
        return loc("Verspätet · \(arrived.appTime)")
    }

    // MARK: Speichern

    private func save(kind: StudentObservation.Kind, value: Int = 0, note: String = "") {
        let observation = StudentObservation(
            subject: lesson.subject, date: .now, slotIndex: lesson.slotIndex, kind: kind, scale: settings.scale,
            value: value, note: note.trimmingCharacters(in: .whitespacesAndNewlines), student: student
        )
        modelContext.insert(observation)
        Haptics.tap()
        withAnimation(.smooth) { lastSaved = observation }
        FunStat.observations.increment()
        persist()
    }

    private func undo() {
        guard let lastSaved else { return }
        modelContext.delete(lastSaved)
        withAnimation(.smooth) { self.lastSaved = nil }
        persist()
    }

    private func persist() {
        try? modelContext.save()
    }
}

/// Bewertungsknopf: rot getönt (negativ), neutral grau, grün getönt (positiv).
struct RatingButtonStyle: ButtonStyle {
    let tone: ObservationScale.Tone
    /// Ausgewählt (Editor): kräftigere Füllung und Rahmen.
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        let color: Color = switch tone {
        case .negative: .red
        case .neutral: .gray
        case .positive: .green
        }
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .foregroundStyle(tone == .neutral ? AnyShapeStyle(.primary) : AnyShapeStyle(color))
            .background(color.opacity(configuration.isPressed || isSelected ? 0.28 : 0.12), in: shape)
            .overlay(shape.strokeBorder(isSelected ? color : .clear, lineWidth: 2))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Hinweis oben im Sitzplan, was die gestrichelten Tische bedeuten.
struct UnobservedLegend: View {
    var body: some View {
        Label {
            Text(loc("Gestrichelt: seit \(ObservationCoverage.threshold) Stunden ohne Beobachtung"))
        } icon: {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 18, height: 12)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .padding(12)
    }
}

/// Schülerakte im Sitzplan: Stunde, in der erfasst wird, und Markierungen der Tische.
enum SeatingPlanRecords {
    /// Heute, laufende Stunde der Klasse (sonst ohne Stunde), Fach: gewähltes bzw. der Stunde, sonst das erste Fach.
    static func lessonContext(
        for schoolClass: SchoolClass, schedule: LessonSchedule, preferred: [String?], now: Date = .now
    ) -> LessonContext? {
        guard let first = schoolClass.subjects.first else { return nil }
        let current = schedule.currentLesson(classID: schoolClass.id, now: now)
        let subject = (preferred + [current?.subject]).compactMap { $0 }.first { schoolClass.subjects.contains($0) } ?? first
        return LessonContext(day: Calendar.school.startOfDay(for: now), slotIndex: current?.slotIndex ?? -1, subject: subject)
    }

    /// Tische von Schülern, die seit mindestens drei Stunden des Fachs nicht beobachtet wurden.
    static func unobservedTables(
        occupants: [UUID: Student], classID: UUID, lesson: LessonContext, schedule: LessonSchedule
    ) -> Set<UUID> {
        let starts = schedule.pastLessonStarts(classID: classID, subject: lesson.subject)
        guard starts.count >= ObservationCoverage.threshold else { return [] }
        return Set(occupants.compactMap { table, student in
            let last = student.observations(in: lesson.subject).first?.date
            let count = ObservationCoverage.lessonsWithout(lastObservation: last, since: student.createdAt, lessonStarts: starts)
            return count >= ObservationCoverage.threshold ? table : nil
        })
    }

    /// Tische abwesender Schüler in der aktuellen Stunde.
    static func absentTables(occupants: [UUID: Student], lesson: LessonContext) -> Set<UUID> {
        Set(occupants.compactMap { table, student in student.absence(in: lesson)?.kind == .absent ? table : nil })
    }
}
