import SwiftData
import SwiftUI

/// Eine Tagesspalte (0–24 Uhr): Raster, Pausen, Stunden-Slots, Termine.
/// - Tipp auf einen leeren Slot: Klasse + Fach festlegen.
/// - Tipp auf eine Stunde: Räume-Tab (später: Raum mit Sitzplan der Klasse).
/// - Langes Drücken auf Stunde/Termin: Menü mit Bearbeiten und Entfernen.
/// - Tipp auf freie Fläche: neuer Termin (auf 15 Minuten gerundet).
/// Im Privatsphäre-Modus nur lesend (keine Popover zum Anlegen/Bearbeiten).
struct DayColumn: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var app
    @Environment(SchoolSettings.self) private var settings
    @Environment(AppSecurity.self) private var security

    let date: Date
    let weekday: Int
    let schedule: LessonSchedule
    let entries: [CalendarEntry]
    /// Nur Stunden dieser Klasse farbig; alle anderen neutral.
    var focusClassID: UUID?

    @State private var selectedSlot: LessonSlot?
    @State private var newEntryMinute: Int?
    @State private var editingEntry: CalendarEntry?

    private let calendar = Calendar.school
    private var hourHeight: CGFloat { CalendarView.hourHeight }
    private var totalHeight: CGFloat { hourHeight * 24 }

    private func y(_ minutes: Int) -> CGFloat { CGFloat(minutes) / 60 * hourHeight }

    private var holiday: Holiday? { schedule.holiday(on: date) }

    private var canEdit: Bool { !security.isPrivacyModeOn }

    var body: some View {
        ZStack(alignment: .top) {
            // Freie Fläche → neuer Termin
            Color.clear
                .contentShape(.rect)
                .onTapGesture { location in
                    guard canEdit else { return }
                    let minute = Int((location.y / hourHeight * 60 / 15).rounded(.down)) * 15
                    newEntryMinute = min(max(minute, 0), 24 * 60 - 15)
                }

            backgroundLayers

            ForEach(settings.slots) { slot in
                // In den Ferien nur belegte (Einzel-)Stunden zeigen.
                if holiday == nil || schedule.lesson(on: date, slotIndex: slot.index) != nil {
                    slotView(slot)
                }
            }

            ForEach(entriesOfDay) { entry in
                entryView(entry)
            }

            if calendar.isDateInToday(date) {
                nowIndicator
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Privatsphäre-Modus an → offene Popover sofort schließen.
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                selectedSlot = nil
                newEntryMinute = nil
                editingEntry = nil
            }
        }
        .popover(
            isPresented: Binding(get: { newEntryMinute != nil }, set: { if !$0 { newEntryMinute = nil } }),
            attachmentAnchor: .point(UnitPoint(x: 0.5, y: y(newEntryMinute ?? 0) / totalHeight))
        ) {
            EntryEditorView(entry: nil, day: date, startMinute: newEntryMinute ?? settings.values.dayStart)
                .softScrollEdges()
        }
    }

    // MARK: Hintergrund

    @ViewBuilder
    private var backgroundLayers: some View {
        let start = settings.values.dayStart
        let end = settings.values.dayEnd

        Group {
            // Außerhalb der Schulzeit abdunkeln
            Rectangle().fill(.fill.quaternary)
                .frame(height: y(start))
                .frame(maxHeight: .infinity, alignment: .top)
            Rectangle().fill(.fill.quaternary)
                .frame(height: y(24 * 60 - end))
                .frame(maxHeight: .infinity, alignment: .bottom)

            // Stundenlinien
            ForEach(1..<24, id: \.self) { hour in
                Rectangle().fill(.separator)
                    .frame(height: 0.5)
                    .offset(y: y(hour * 60))
            }

            if holiday != nil {
                Rectangle().fill(.orange.opacity(0.07))
            }

            // Pausen
            ForEach(settings.sortedBreaks) { pause in
                Text("Pause")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.fill.tertiary)
                    .frame(height: y(pause.duration))
                    .offset(y: y(pause.start))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Stunden

    private func slotView(_ slot: LessonSlot) -> some View {
        let lesson = schedule.lesson(on: date, slotIndex: slot.index)
        let isDimmed = focusClassID != nil && lesson != nil && lesson?.schoolClass?.id != focusClassID
        return SlotCell(slot: slot, lesson: lesson, isDimmed: isDimmed)
            .frame(height: y(slot.end - slot.start))
            .padding(.horizontal, 3)
            .onTapGesture {
                if let lesson, let room = lesson.room {
                    app.openSeatingPlan(room: room, schoolClass: lesson.schoolClass)
                } else if lesson != nil {
                    app.open(.rooms)
                } else if canEdit {
                    selectedSlot = slot
                }
            }
            .hoverEffect(.highlight)
            .contextMenu {
                if canEdit, let lesson {
                    editMenu(edit: { selectedSlot = slot }, remove: { delete(lesson) })
                }
            }
            .popover(isPresented: Binding(
                get: { selectedSlot == slot },
                set: { if !$0 { selectedSlot = nil } }
            )) {
                LessonEditorView(date: date, weekday: weekday, slot: slot, lesson: lesson)
                    .softScrollEdges()
            }
            .offset(y: y(slot.start))
    }

    // MARK: Termine

    private var entriesOfDay: [CalendarEntry] {
        entries.filter { calendar.isDate($0.start, inSameDayAs: date) }
    }

    private func entryView(_ entry: CalendarEntry) -> some View {
        let start = minutes(of: entry.start)
        let duration = max(Int(entry.end.timeIntervalSince(entry.start) / 60), 20)
        let isDimmed = focusClassID != nil && entry.schoolClass != nil && entry.schoolClass?.id != focusClassID
        return EntryCard(entry: entry, isDimmed: isDimmed)
            .frame(height: y(duration))
            .padding(.leading, 12)
            .padding(.trailing, 3)
            // Antippen bewusst ohne Aktion (später eigene Ansicht); Bearbeiten per langem Drücken.
            .hoverEffect(.lift)
            .contextMenu {
                if canEdit {
                    editMenu(edit: { editingEntry = entry }, remove: { delete(entry) })
                }
            }
            .popover(isPresented: Binding(
                get: { editingEntry?.id == entry.id },
                set: { if !$0 { editingEntry = nil } }
            )) {
                EntryEditorView(entry: entry, day: date, startMinute: start)
                    .softScrollEdges()
            }
            .offset(y: y(start))
    }

    private var nowIndicator: some View {
        TimelineView(.everyMinute) { context in
            let minute = minutes(of: context.date)
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .offset(y: y(minute) - 4)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    // MARK: Menü

    @ViewBuilder
    private func editMenu(edit: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        Button("Bearbeiten", icon: .editPencil, action: edit)
        Button("Entfernen", destructiveIcon: .trash, action: remove)
    }

    private func delete(_ model: some PersistentModel) {
        modelContext.delete(model)
        try? modelContext.save()
    }

    // MARK: Hilfen

    private func minutes(of date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// Stunden-Slot:
/// - leer: gestrichelt mit Stundennummer
/// - belegt: Stundennummer + Fach oben, Klasse groß unten rechts, Farbstreifen links
/// - gedimmt (Kalender-Fokus auf andere Klasse): neutrale Fläche ohne Text
private struct SlotCell: View {
    let slot: LessonSlot
    let lesson: Lesson?
    var isDimmed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let lesson, let schoolClass = lesson.schoolClass {
                if isDimmed {
                    shape.fill(.fill.secondary)
                } else {
                    filledCell(lesson: lesson, schoolClass: schoolClass, shape: shape)
                }
            } else {
                Text("\(slot.number).")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(shape.strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
        .contentShape(.hoverEffect, shape)
        .contentShape(shape)
    }

    private func filledCell(lesson: Lesson, schoolClass: SchoolClass, shape: RoundedRectangle) -> some View {
        let color = schoolClass.displayColor
        let number = Text("\(slot.number).")
            .font(.caption2.weight(.semibold))
            .opacity(0.7)
        let subject = Text(SchoolClass.displayName(ofSubject: lesson.subject))
            .font(.caption2)
            .lineLimit(1)
            .sensitive()
        // Einmalig-Symbol vor dem Kürzel (unten), damit oben Platz für das Fach bleibt.
        let className = HStack(alignment: .lastTextBaseline, spacing: 3) {
            if !lesson.isRecurring {
                Image(icon: .number1Circle).iconSize(12)
            }
            Text(schoolClass.shortName)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .sensitive()
        }
        // Zeigt so viel, wie in die Zelle passt (kurze Stunden: alles in einer Zeile).
        return ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    number
                    if !lesson.subject.isEmpty { subject }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    className
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                number
                if !lesson.subject.isEmpty { subject }
                Spacer(minLength: 0)
                className
            }
            className
        }
        .foregroundStyle(color)
        .padding(.vertical, 4)
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Fläche + Farbstreifen links gemeinsam auf die Rundung zuschneiden.
        .background {
            HStack(spacing: 0) {
                color.frame(width: 4)
                color.opacity(0.18)
            }
        }
        .clipShape(shape)
    }
}

/// Termin: ohne Klasse in der Akzentfarbe, mit Klasse wie eine Stunde in der Klassenfarbe
/// (Farbstreifen links, Kürzel unten rechts). Gedimmt wie Stunden beim Kalender-Fokus.
/// Zeigt so viel, wie in die Karte passt (kurze Termine: nur Titel bzw. Titel + Kürzel).
private struct EntryCard: View {
    @Environment(\.appAccent) private var accent
    let entry: CalendarEntry
    var isDimmed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let schoolClass = entry.schoolClass {
                if isDimmed {
                    shape.fill(.fill.secondary)
                        .background(Color(.systemBackground), in: shape)
                } else {
                    classCard(schoolClass, shape: shape)
                }
            } else {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 1) {
                        title
                        time
                    }
                    title
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(accent.gradient, in: shape)
            }
        }
        .contentShape(.hoverEffect, shape)
        .contentShape(shape)
    }

    private var title: some View {
        Text(entry.title.isEmpty ? "Termin" : entry.title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .sensitive()
    }

    private var time: some View {
        Text(entry.start.appFormatted(date: .omitted, time: .shortened))
            .font(.caption2)
    }

    private func classCard(_ schoolClass: SchoolClass, shape: RoundedRectangle) -> some View {
        let color = schoolClass.displayColor
        let className = Text(schoolClass.shortName)
            .font(.title3.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .sensitive()
        return ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    title
                    time
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    className
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                title
                Spacer(minLength: 0)
                className
            }
            title
        }
        .foregroundStyle(color)
        .padding(.vertical, 4)
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Deckender Grund, damit darunterliegende Stunden-Slots nicht durchscheinen.
        .background {
            HStack(spacing: 0) {
                color.frame(width: 4)
                color.opacity(0.18)
            }
            .background(Color(.systemBackground))
        }
        .clipShape(shape)
    }
}
