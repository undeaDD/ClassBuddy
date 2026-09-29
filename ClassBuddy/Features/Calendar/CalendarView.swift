import SwiftData
import SwiftUI

/// Globaler Wochenkalender: Stundenraster aus den Schuleinstellungen,
/// Unterrichtsstunden (Klasse + Fach), freie Termine, Ferien/Feiertage.
/// Optional auf eine Klasse fokussiert (`AppModel.calendarFocusClassID`):
/// dann sind nur deren Stunden farbig, alle anderen neutral.
struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @Environment(SchoolSettings.self) private var settings
    @Query private var lessons: [Lesson]
    @Query private var entries: [CalendarEntry]
    @Query private var holidays: [Holiday]
    @Query private var classes: [SchoolClass]

    @Environment(AppSecurity.self) private var security

    @State private var weekStart = Calendar.school.startOfWeek(for: .now)
    @State private var isNewEntryPresented = false

    static let hourHeight: CGFloat = 64
    private static let gutterWidth: CGFloat = 56
    private let calendar = Calendar.school

    private var schedule: LessonSchedule {
        LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots)
    }

    private var focusClass: SchoolClass? {
        classes.first { $0.id == app.calendarFocusClassID }
    }

    private var days: [(weekday: Int, date: Date)] {
        settings.visibleWeekdays.compactMap { weekday in
            calendar.date(byAdding: .day, value: weekday, to: weekStart).map { (weekday, $0) }
        }
    }

    private var weekNumber: Int {
        calendar.component(.weekOfYear, from: weekStart)
    }

    /// Monat der Woche (nach ISO: Monat des Donnerstags).
    private var monthTitle: String {
        let thursday = calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
        return thursday.formatted(.dateTime.month(.abbreviated))
    }

    private var weekTitle: String {
        let end = calendar.date(byAdding: .day, value: settings.visibleWeekdays.count - 1, to: weekStart) ?? weekStart
        return "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        timeGutter
                        ForEach(days, id: \.weekday) { day in
                            DayColumn(
                                date: day.date,
                                weekday: day.weekday,
                                schedule: schedule,
                                entries: entries,
                                focusClassID: focusClass?.id
                            )
                            .overlay(alignment: .leading) { Divider() }
                        }
                    }
                    .frame(height: Self.hourHeight * 24)
                }
                .onAppear {
                    proxy.scrollTo(max(settings.values.dayStart / 60 - 1, 0), anchor: .top)
                }
            }
        }
        .navigationTitle(AppTab.calendar.title)
        .navigationSubtitle(weekTitle)
        .toolbarTitleDisplayMode(.inline)
        .appChrome(tab: .calendar) {
            if let focusClass {
                // Aktiver Klassen-Filter; antippen hebt ihn auf.
                Button {
                    app.calendarFocusClassID = nil
                } label: {
                    Label("Nur \(focusClass.title)", image: .xmark)
                        .labelStyle(.titleAndIcon)
                }
                .tint(focusClass.color.color)
            }
            Button("Neuer Termin", image: .plus) { isNewEntryPresented = true }
                .disabled(security.isPrivacyModeOn)
            Button("Vorherige Woche", image: .navArrowLeft) { moveWeek(by: -1) }
            Button("Heute") { weekStart = calendar.startOfWeek(for: .now) }
            Button("Nächste Woche", image: .navArrowRight) { moveWeek(by: 1) }
        }
        // Sheet statt Toolbar-Popover: blockiert die Tab-Leiste während der Eingabe.
        .sheet(isPresented: $isNewEntryPresented) {
            let suggestion = suggestedNewEntryStart
            EntryEditorView(entry: nil, day: suggestion.day, startMinute: suggestion.minute) { start in
                weekStart = calendar.startOfWeek(for: start)
            }
            .presentationSizing(.fitted)
        }
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn { isNewEntryPresented = false }
        }
        // Sprung aus der Übersicht („Nächste Stunde“) in die passende Woche.
        .onChange(of: app.calendarJumpDate, initial: true) { _, date in
            guard let date else { return }
            weekStart = calendar.startOfWeek(for: date)
            app.calendarJumpDate = nil
        }
    }

    // MARK: Kopfzeile

    private var dayHeader: some View {
        HStack(spacing: 0) {
            // Kalenderwoche + Monat über der Zeitspalte
            VStack(spacing: 0) {
                Text("KW \(weekNumber)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Text(monthTitle)
                    .font(.subheadline.weight(.heavy))
            }
            .foregroundStyle(.primary)
            .frame(width: Self.gutterWidth)

            ForEach(days, id: \.weekday) { day in
                let isToday = calendar.isDateInToday(day.date)
                VStack(spacing: 2) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isToday ? Color.accentColor : .secondary)
                    Text(day.date.formatted(.dateTime.day()))
                        .font(.title3.weight(isToday ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? .white : .primary)
                        .frame(width: 34, height: 34)
                        .background(isToday ? Color.accentColor : .clear, in: .circle)
                    Text(schedule.holiday(on: day.date)?.name ?? " ")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: Zeitleiste

    private var timeGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hour == 0 ? "" : (hour * 60).clockString)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: Self.gutterWidth - 8, height: Self.hourHeight, alignment: .topTrailing)
                    .offset(y: -7)
                    .id(hour)
            }
        }
        .frame(width: Self.gutterWidth, alignment: .leading)
    }

    /// Vorschlag für „+“: in der aktuellen Woche heute zur nächsten vollen Stunde,
    /// sonst Wochenbeginn zum Schulbeginn.
    private var suggestedNewEntryStart: (day: Date, minute: Int) {
        let now = Date.now
        if calendar.isDate(now, equalTo: weekStart, toGranularity: .weekOfYear) {
            let hour = calendar.component(.hour, from: now)
            return (now, min(hour + 1, 23) * 60)
        }
        return (weekStart, settings.values.dayStart)
    }

    private func moveWeek(by weeks: Int) {
        weekStart = calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart) ?? weekStart
    }
}
