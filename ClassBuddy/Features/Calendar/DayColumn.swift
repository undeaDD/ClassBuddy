import SwiftData
import SwiftUI

/// Eine Tagesspalte (0–24 Uhr): Raster, Pausen, Stunden-Slots, Termine.
/// - Tipp auf einen Slot: Klasse + Fach festlegen.
/// - Tipp auf freie Fläche: neuer Termin (auf 15 Minuten gerundet).
struct DayColumn: View {
    @Environment(SchoolSettings.self) private var settings

    let date: Date
    let weekday: Int
    let lessons: [Lesson]
    let entries: [CalendarEntry]
    let holiday: Holiday?

    @State private var selectedSlot: LessonSlot?
    @State private var newEntryMinute: Int?
    @State private var editingEntry: CalendarEntry?

    private let calendar = Calendar.school
    private var hourHeight: CGFloat { CalendarView.hourHeight }
    private var totalHeight: CGFloat { hourHeight * 24 }

    private func y(_ minutes: Int) -> CGFloat { CGFloat(minutes) / 60 * hourHeight }

    var body: some View {
        ZStack(alignment: .top) {
            // Freie Fläche → neuer Termin
            Color.clear
                .contentShape(.rect)
                .onTapGesture { location in
                    let minute = Int((location.y / hourHeight * 60 / 15).rounded(.down)) * 15
                    newEntryMinute = min(max(minute, 0), 24 * 60 - 15)
                }

            backgroundLayers

            if holiday == nil || !singleLessonsOnly.isEmpty {
                ForEach(settings.slots) { slot in
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
        .popover(
            isPresented: Binding(get: { newEntryMinute != nil }, set: { if !$0 { newEntryMinute = nil } }),
            attachmentAnchor: .point(UnitPoint(x: 0.5, y: y(newEntryMinute ?? 0) / totalHeight))
        ) {
            EntryEditorView(entry: nil, day: date, startMinute: newEntryMinute ?? settings.values.dayStart)
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

    private var singleLessonsOnly: [Lesson] {
        lessons.filter { !$0.isRecurring && isSameDay($0.date) }
    }

    private func lesson(for slot: LessonSlot) -> Lesson? {
        if let single = lessons.first(where: { !$0.isRecurring && $0.slotIndex == slot.index && isSameDay($0.date) }) {
            return single
        }
        guard holiday == nil else { return nil }
        return lessons.first { $0.isRecurring && $0.weekday == weekday && $0.slotIndex == slot.index }
    }

    private func slotView(_ slot: LessonSlot) -> some View {
        let lesson = lesson(for: slot)
        return SlotCell(slot: slot, lesson: lesson)
            .frame(height: y(slot.end - slot.start))
            .padding(.horizontal, 3)
            .onTapGesture { selectedSlot = slot }
            .hoverEffect(.highlight)
            .popover(isPresented: Binding(
                get: { selectedSlot == slot },
                set: { if !$0 { selectedSlot = nil } }
            )) {
                LessonEditorView(date: date, weekday: weekday, slot: slot, lesson: lesson)
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
        return EntryCard(entry: entry)
            .frame(height: y(duration))
            .padding(.leading, 12)
            .padding(.trailing, 3)
            .onTapGesture { editingEntry = entry }
            .hoverEffect(.lift)
            .popover(isPresented: Binding(
                get: { editingEntry?.id == entry.id },
                set: { if !$0 { editingEntry = nil } }
            )) {
                EntryEditorView(entry: entry, day: date, startMinute: start)
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

    // MARK: Hilfen

    private func isSameDay(_ other: Date?) -> Bool {
        other.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }

    private func minutes(of date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// Stunden-Slot: leer (gestrichelt, Stundennummer) oder belegt (Klasse + Fach).
private struct SlotCell: View {
    let slot: LessonSlot
    let lesson: Lesson?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if let lesson, let schoolClass = lesson.schoolClass {
                let color = schoolClass.color.color
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(schoolClass.shortName).font(.caption.weight(.bold))
                            .sensitive()
                        if !lesson.isRecurring {
                            Image(systemName: "1.circle").font(.caption2)
                        }
                    }
                    if !lesson.subject.isEmpty {
                        Text(lesson.subject).font(.caption2)
                            .sensitive()
                    }
                }
                .foregroundStyle(color)
                .padding(6)
                .padding(.leading, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Fläche + Farbstreifen links gemeinsam auf die Rundung zuschneiden.
                .background {
                    HStack(spacing: 0) {
                        color.frame(width: 4)
                        color.opacity(0.18)
                    }
                }
                .clipShape(shape)
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
}

private struct EntryCard: View {
    let entry: CalendarEntry

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.title.isEmpty ? "Termin" : entry.title)
                .font(.caption.weight(.semibold))
                .sensitive()
            Text(entry.start.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.accentColor.gradient, in: shape)
        .contentShape(.hoverEffect, shape)
        .contentShape(shape)
    }
}
