import SwiftData
import SwiftUI

/// Popover: Klasse + Fach für einen Stunden-Slot, wöchentlich oder einmalig.
struct LessonEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\SchoolClass.schoolYear, order: .reverse), SortDescriptor(\SchoolClass.shortName)])
    private var classes: [SchoolClass]

    let date: Date
    let weekday: Int
    let slot: LessonSlot
    let lesson: Lesson?

    @State private var classID: UUID?
    @State private var subject: String
    @State private var isRecurring: Bool

    init(date: Date, weekday: Int, slot: LessonSlot, lesson: Lesson?) {
        self.date = date
        self.weekday = weekday
        self.slot = slot
        self.lesson = lesson
        _classID = State(initialValue: lesson?.schoolClass?.id)
        _subject = State(initialValue: lesson?.subject ?? "")
        _isRecurring = State(initialValue: lesson?.isRecurring ?? true)
    }

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == classID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Klasse", selection: $classID) {
                        Text("Keine").tag(UUID?.none)
                        ForEach(classes) { schoolClass in
                            Text(schoolClass.title).tag(Optional(schoolClass.id))
                        }
                    }
                    Picker("Fach", selection: $subject) {
                        Text("Kein Fach").tag("")
                        ForEach(selectedClass?.subjects ?? [], id: \.self) { subject in
                            Text(subject).tag(subject)
                        }
                    }
                    .disabled(selectedClass?.subjects.isEmpty ?? true)
                } footer: {
                    if classes.isEmpty {
                        Text("Lege zuerst oben links eine Klasse an.")
                    } else if selectedClass?.subjects.isEmpty == true {
                        Text("Für diese Klasse sind noch keine Fächer hinterlegt.")
                    }
                }

                Section {
                    Toggle("Jede Woche", isOn: $isRecurring)
                } footer: {
                    Text(isRecurring
                        ? "Jeden \(date.formatted(.dateTime.weekday(.wide))), \(slot.number). Stunde (\(slot.timeRange))"
                        : "Nur am \(date.formatted(.dateTime.weekday(.wide).day().month(.wide))), \(slot.number). Stunde")
                }

                if lesson != nil {
                    Section {
                        Button("Stunde entfernen", role: .destructive, action: remove)
                    }
                }
            }
            .navigationTitle("\(slot.number). Stunde")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save)
                        .disabled(selectedClass == nil)
                }
            }
            .onChange(of: classID) {
                // Fach zurücksetzen, wenn es in der neuen Klasse nicht existiert.
                if let selectedClass, !selectedClass.subjects.contains(subject) {
                    subject = selectedClass.subjects.first ?? ""
                }
            }
        }
        .frame(width: 380, height: lesson == nil ? 330 : 400)
        .presentationCompactAdaptation(.popover)
    }

    private func save() {
        guard let selectedClass else { return }
        let target = lesson ?? {
            let new = Lesson(weekday: weekday, slotIndex: slot.index, subject: "", isRecurring: true, date: nil, schoolClass: nil)
            modelContext.insert(new)
            return new
        }()
        target.schoolClass = selectedClass
        target.subject = subject
        target.isRecurring = isRecurring
        target.weekday = weekday
        target.slotIndex = slot.index
        target.date = isRecurring ? nil : Calendar.school.startOfDay(for: date)
        try? modelContext.save()
        dismiss()
    }

    private func remove() {
        if let lesson { modelContext.delete(lesson) }
        try? modelContext.save()
        dismiss()
    }
}

/// Popover: freier Termin anlegen / bearbeiten.
struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let entry: CalendarEntry?

    @State private var title: String
    @State private var start: Date
    @State private var duration: Int
    @State private var notes: String

    init(entry: CalendarEntry?, day: Date, startMinute: Int) {
        self.entry = entry
        let defaultStart = Calendar.school.date(byAdding: .minute, value: startMinute, to: Calendar.school.startOfDay(for: day)) ?? day
        _title = State(initialValue: entry?.title ?? "")
        _start = State(initialValue: entry?.start ?? defaultStart)
        _duration = State(initialValue: entry.map { max(Int($0.end.timeIntervalSince($0.start) / 60), 15) } ?? 60)
        _notes = State(initialValue: entry?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $title)
                        .sensitive()
                    DatePicker("Beginn", selection: $start)
                    Stepper("Dauer: \(durationText)", value: $duration, in: 15...(12 * 60), step: 15)
                }
                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                        .sensitive()
                }
                if entry != nil {
                    Section {
                        Button("Termin löschen", role: .destructive, action: remove)
                    }
                }
            }
            .navigationTitle(entry == nil ? "Neuer Termin" : "Termin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(entry == nil ? "Anlegen" : "Sichern", action: save)
                }
            }
        }
        .frame(width: 380, height: entry == nil ? 380 : 450)
        .presentationCompactAdaptation(.popover)
    }

    private var durationText: String {
        duration < 60 ? "\(duration) min"
            : duration % 60 == 0 ? "\(duration / 60) h"
            : "\(duration / 60) h \(duration % 60) min"
    }

    private func save() {
        let target = entry ?? {
            let new = CalendarEntry(title: "", start: start, end: start)
            modelContext.insert(new)
            return new
        }()
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.start = start
        target.end = start.addingTimeInterval(TimeInterval(duration * 60))
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        dismiss()
    }

    private func remove() {
        if let entry { modelContext.delete(entry) }
        try? modelContext.save()
        dismiss()
    }
}
