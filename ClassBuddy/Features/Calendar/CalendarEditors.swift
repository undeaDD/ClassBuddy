import SwiftData
import SwiftUI

/// Klasse + Fach für einen Stunden-Slot, wöchentlich oder einmalig.
/// iPad: Popover am Slot; iPhone: Sheet.
struct LessonEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.device) private var device
    @Query(sort: [SortDescriptor(\SchoolClass.schoolYear, order: .reverse), SortDescriptor(\SchoolClass.shortName)])
    private var classes: [SchoolClass]
    @Query(sort: [SortDescriptor(\Room.sortIndex), SortDescriptor(\Room.name)]) private var rooms: [Room]

    let date: Date
    let weekday: Int
    let slot: LessonSlot
    let lesson: Lesson?

    @State private var classID: UUID?
    @State private var subject: String
    @State private var isRecurring: Bool
    @State private var roomID: UUID?

    init(date: Date, weekday: Int, slot: LessonSlot, lesson: Lesson?) {
        self.date = date
        self.weekday = weekday
        self.slot = slot
        self.lesson = lesson
        _classID = State(initialValue: lesson?.schoolClass?.id)
        _subject = State(initialValue: lesson?.subject ?? "")
        _isRecurring = State(initialValue: lesson?.isRecurring ?? true)
        _roomID = State(initialValue: lesson?.room?.id)
    }

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == classID }
    }

    private var selectedRoom: Room? {
        rooms.first { $0.id == roomID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $classID) {
                        Text("Keine").tag(UUID?.none)
                        ForEach(classes) { schoolClass in
                            Text(schoolClass.title).tag(Optional(schoolClass.id))
                        }
                    } label: {
                        Label("Klasse", icon: .community)
                    }
                    Picker(selection: $subject) {
                        Text("Kein Fach").tag("")
                        ForEach(selectedClass?.subjects ?? [], id: \.self) { subject in
                            Text(SchoolClass.displayName(ofSubject: subject)).tag(subject)
                        }
                    } label: {
                        Label("Fach", icon: .graduationCap)
                    }
                    .disabled(selectedClass?.subjects.isEmpty ?? true)
                } footer: {
                    if classes.isEmpty {
                        Text("Legen Sie zuerst oben links eine Klasse an.")
                    } else if selectedClass?.subjects.isEmpty == true {
                        Text("Für diese Klasse sind noch keine Fächer hinterlegt.")
                    }
                }

                Section {
                    Picker(selection: $roomID) {
                        Text("Kein Raum").tag(UUID?.none)
                        ForEach(rooms) { room in
                            Text(room.name).tag(Optional(room.id))
                        }
                    } label: {
                        Label("Raum", symbol: AppTab.rooms.symbol)
                    }
                } footer: {
                    if let selectedRoom, !selectedRoom.allows(subject: subject) {
                        Text("\(SchoolClass.displayName(ofSubject: subject)) wird laut Raumplanung nicht in \(selectedRoom.name) unterrichtet.")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Toggle(isOn: $isRecurring) {
                        Label("Jede Woche", icon: .number1Circle)
                    }
                } footer: {
                    Text(isRecurring
                        ? loc("Jeden \(date.appFormatted(.dateTime.weekday(.wide))), \(slot.number). Stunde (\(slot.timeRange))")
                        : loc("Nur am \(date.appFormatted(.dateTime.weekday(.wide))), \(date.appDate), \(slot.number). Stunde"))
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
                if device.isPhone {
                    ToolbarItem(placement: .cancellationAction) {
                        CancelButton()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: loc("Sichern"), action: save)
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
        .editorPresentation(device, width: 380, height: lesson == nil ? 400 : 470)
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
        target.room = selectedRoom
        try? modelContext.save()
        dismiss()
    }

    private func remove() {
        if let lesson { modelContext.delete(lesson) }
        try? modelContext.save()
        dismiss()
    }
}

/// Freier Termin anlegen / bearbeiten. iPad: Popover (bzw. Sheet über „+“); iPhone: Sheet.
struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.device) private var device
    @Query(sort: [SortDescriptor(\SchoolClass.schoolYear, order: .reverse), SortDescriptor(\SchoolClass.shortName)])
    private var classes: [SchoolClass]
    @Query(sort: [SortDescriptor(\Room.sortIndex), SortDescriptor(\Room.name)]) private var rooms: [Room]

    let entry: CalendarEntry?
    /// Als Sheet gezeigt (nicht als Popover) → Abbrechen-Button nötig.
    var isSheet = false
    /// Nach dem Sichern mit dem Beginn aufgerufen (z. B. um zur Woche zu springen).
    var onSave: (Date) -> Void = { _ in }

    @State private var title: String
    @State private var start: Date
    @State private var duration: Int
    @State private var notes: String
    @State private var classID: UUID?
    @State private var roomID: UUID?

    init(entry: CalendarEntry?, day: Date, startMinute: Int, isSheet: Bool = false, onSave: @escaping (Date) -> Void = { _ in }) {
        self.entry = entry
        self.isSheet = isSheet
        self.onSave = onSave
        let defaultStart = Calendar.school.date(byAdding: .minute, value: startMinute, to: Calendar.school.startOfDay(for: day)) ?? day
        _title = State(initialValue: entry?.title ?? "")
        _start = State(initialValue: entry?.start ?? defaultStart)
        _duration = State(initialValue: entry.map { max(Int($0.end.timeIntervalSince($0.start) / 60), 15) } ?? 60)
        _notes = State(initialValue: entry?.notes ?? "")
        _classID = State(initialValue: entry?.schoolClass?.id)
        _roomID = State(initialValue: entry?.room?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        TextField("Titel", text: $title)
                            .sensitive()
                    } icon: {
                        Image(icon: .label)
                    }
                    DatePicker(selection: $start) {
                        Label("Beginn", icon: .calendar)
                    }
                    Stepper(value: $duration, in: 15...(12 * 60), step: 15) {
                        Label("Dauer: \(durationText)", icon: .timer)
                    }
                    // Optional: Termin einer Klasse zuordnen → in deren Farbe (z. B. Ausflug, Elternabend).
                    Picker(selection: $classID) {
                        Text("Keine").tag(UUID?.none)
                        ForEach(classes) { schoolClass in
                            Text(schoolClass.title).tag(Optional(schoolClass.id))
                        }
                    } label: {
                        Label("Klasse", icon: .community)
                    }
                    // Optional: Raum → Antippen des Termins öffnet den Sitzplan (ohne Klasse leer, z. B. zum Drucken).
                    Picker(selection: $roomID) {
                        Text("Kein Raum").tag(UUID?.none)
                        ForEach(rooms) { room in
                            Text(room.name).tag(Optional(room.id))
                        }
                    } label: {
                        Label("Raum", symbol: AppTab.rooms.symbol)
                    }
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
                if isSheet || device.isPhone {
                    ToolbarItem(placement: .cancellationAction) {
                        CancelButton()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: entry == nil ? loc("Anlegen") : loc("Sichern"), action: save)
                }
            }
        }
        .editorPresentation(device, width: 380, height: entry == nil ? 468 : 538)
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
        target.schoolClass = classes.first { $0.id == classID }
        target.room = rooms.first { $0.id == roomID }
        try? modelContext.save()
        onSave(start)
        dismiss()
    }

    private func remove() {
        if let entry { modelContext.delete(entry) }
        try? modelContext.save()
        dismiss()
    }
}

/// Abbrechen als Icon-Button (xmark) in Editor-Toolbars.
struct CancelButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Abbrechen", icon: .xmark, role: .cancel) { dismiss() }
    }
}

/// Bestätigen als Icon-Button (Haken); `title` ist das Accessibility-Label.
struct ConfirmButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, icon: .check, role: .confirm, action: action)
    }
}

extension View {
    /// Runde Glas-Blase für Icon-Buttons in Toolbars, in denen das System keine zeichnet
    /// (Inhalte, die aus dem Klassen-Popover heraus präsentiert werden).
    /// `prominent`: in der Akzentfarbe getöntes Glas mit weißem Icon (statt `.glassProminent`).
    @ViewBuilder
    func glassToolbarButton(prominent: Bool = false) -> some View {
        if prominent {
            modifier(ProminentGlassButton())
        } else {
            labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
        }
    }
}

private struct ProminentGlassButton: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appAccent) private var accent

    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(8)
            .glassEffect(.regular.tint(accent).interactive(), in: .circle)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

private extension View {
    /// iPad: feste Popover-Größe, auch in kompakter Umgebung als Popover.
    /// iPhone: normales Sheet ohne feste Größe (Inhalt beginnt oben).
    @ViewBuilder
    func editorPresentation(_ device: Device, width: CGFloat, height: CGFloat) -> some View {
        if device.isPad {
            frame(width: width, height: height)
                .presentationCompactAdaptation(.popover)
        } else {
            presentationCompactAdaptation(.sheet)
        }
    }
}
