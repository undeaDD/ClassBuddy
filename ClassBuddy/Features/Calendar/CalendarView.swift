import SwiftData
import SwiftUI

/// Globaler Wochenkalender: Stundenraster aus den Schuleinstellungen,
/// Unterrichtsstunden (Klasse + Fach), freie Termine, Ferien/Feiertage.
/// Optional auf eine Klasse fokussiert (`AppModel.calendarFocusClassID`):
/// dann sind nur deren Stunden farbig, alle anderen neutral.
/// Schmale Ansicht (iPhone): gleitendes 3-Tage-Fenster. Blättern immer unten als schwebende Glas-Leiste.
struct CalendarView: View {
    @Environment(AppModel.self) private var app
    @Environment(SchoolSettings.self) private var settings
    @Query private var lessons: [Lesson]
    @Query private var entries: [CalendarEntry]
    @Query private var holidays: [Holiday]
    @Query private var classes: [SchoolClass]

    @Environment(AppSecurity.self) private var security
    @Environment(\.device) private var device

    @State private var isNewEntryPresented = false

    static let hourHeight: CGFloat = 64
    /// Höhe der Verlängerung unter dem Raster – mehr, als je sichtbar wird.
    private static let bottomExtension: CGFloat = 1000
    private static let gutterWidth: CGFloat = 56
    private let calendar = Calendar.school

    private var weekStart: Date { calendar.startOfWeek(for: app.calendarDate) }
    /// Mitte des 3-Tage-Fensters (iPhone).
    private var dayAnchor: Date { app.calendarDate }

    private var schedule: LessonSchedule {
        LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots)
    }

    private var focusClass: SchoolClass? {
        classes.first { $0.id == app.calendarFocusClassID }
    }

    static let phoneDayCount = 3

    private var days: [(weekday: Int, date: Date)] {
        if device.isPhone {
            return calendar.visibleDays(around: dayAnchor, count: Self.phoneDayCount, weekdays: settings.visibleWeekdays)
                .map { (calendar.mondayBasedWeekday(of: $0), $0) }
        }
        return settings.visibleWeekdays.compactMap { weekday in
            calendar.date(byAdding: .day, value: weekday, to: weekStart).map { (weekday, $0) }
        }
    }

    /// Bezugstag für KW und Monat: iPad der Donnerstag (ISO), iPhone die Mitte des Fensters.
    private var referenceDay: Date {
        if device.isPhone {
            return calendar.visibleDay(from: dayAnchor, direction: 1, weekdays: settings.visibleWeekdays)
        }
        return calendar.date(byAdding: .day, value: 3, to: weekStart) ?? weekStart
    }

    private var weekNumber: Int {
        calendar.component(.weekOfYear, from: referenceDay)
    }

    private var monthTitle: String {
        referenceDay.appFormatted(.dateTime.month(.abbreviated))
    }

    private var weekTitle: String {
        guard let first = days.first?.date, let last = days.last?.date else { return "" }
        let day = Date.FormatStyle.dateTime.day(.twoDigits).month(.twoDigits)
        return "\(first.appFormatted(day)) – \(last.appFormatted(day.year(.twoDigits)))"
    }

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        timeGutter
                        ForEach(days, id: \.date) { day in
                            DayColumn(
                                date: day.date,
                                weekday: day.weekday,
                                schedule: schedule,
                                entries: entries,
                                focusClassID: focusClass?.id
                            )
                            // Abgedunkelten Abend unter 24 Uhr hinaus verlängern: Rand unten,
                            // hinter der Tab-Leiste und beim Nachfedern.
                            .background(alignment: .bottom) {
                                Rectangle().fill(.fill.quaternary)
                                    .overlay(alignment: .leading) { Divider() }
                                    .frame(height: Self.bottomExtension)
                                    .offset(y: Self.bottomExtension)
                                    .allowsHitTesting(false)
                            }
                            .overlay(alignment: .leading) { Divider() }
                        }
                    }
                    .frame(height: Self.hourHeight * 24)
                }
                // Platz unter dem letzten Eintrag, damit die Blättern-Leiste nichts dauerhaft verdeckt.
                // iPhone-Layout: nicht nötig – sie rutscht beim Runterscrollen in die Tab-Leiste.
                .contentMargins(.bottom, device.isPhone ? 0 : 72, for: .scrollContent)
                .onAppear {
                    proxy.scrollTo(max(settings.values.dayStart / 60 - 1, 0), anchor: .top)
                }
            }
        }
        .navigationTitle(AppTab.calendar.title)
        .appNavigationSubtitle(weekTitle)
        .toolbarTitleDisplayMode(.inline)
        .appChrome(tab: .calendar) {
            if let focusClass {
                // Aktiver Klassen-Filter; antippen hebt ihn auf.
                Button {
                    app.calendarFocusClassID = nil
                } label: {
                    Label("Nur \(focusClass.title)", icon: .xmark)
                        .labelStyle(.titleAndIcon)
                }
                .tint(focusClass.displayColor)
            }
            Button("Neuer Termin", icon: .plus) { isNewEntryPresented = true }
                .disabled(security.isPrivacyModeOn)
        }
        // ← Heute → schwebt unten über dem Inhalt und rutscht in die minimierte Tab-Leiste.
        .floatingBottomBar { CalendarPager() }
        // Sheet statt Toolbar-Popover: blockiert die Tab-Leiste während der Eingabe.
        .sheet(isPresented: $isNewEntryPresented) {
            let suggestion = suggestedNewEntryStart
            EntryEditorView(entry: nil, day: suggestion.day, startMinute: suggestion.minute, isSheet: true) { start in
                app.calendarDate = calendar.startOfDay(for: start)
            }
            // iPad: kompaktes Sheet in Inhaltsgröße; iPhone: normales Sheet.
            .fittedSheetOnPad(device)
            .softScrollEdges()
        }
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn { isNewEntryPresented = false }
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

            ForEach(days, id: \.date) { day in
                let isToday = calendar.isDateInToday(day.date)
                VStack(spacing: 2) {
                    Text(day.date.appFormatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    Text(day.date.appFormatted(.dateTime.day()))
                        .font(.title3.weight(isToday ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? .white : .primary)
                        .frame(width: 34, height: 34)
                        .background(isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .circle)
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

    /// Vorschlag für „+“: wenn heute sichtbar ist, heute zur nächsten vollen Stunde,
    /// sonst erster sichtbarer Tag zum Schulbeginn.
    private var suggestedNewEntryStart: (day: Date, minute: Int) {
        let now = Date.now
        if days.contains(where: { calendar.isDate($0.date, inSameDayAs: now) }) {
            let hour = calendar.component(.hour, from: now)
            return (now, min(hour + 1, 23) * 60)
        }
        return (days.first?.date ?? weekStart, settings.values.dayStart)
    }
}

/// ← Heute →: iPad eine Woche weiter, schmale Ansicht ein ganzes 3-Tage-Fenster. Glas-Kapsel.
struct CalendarPager: View {
    @Environment(AppModel.self) private var app
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.device) private var device

    private let calendar = Calendar.school

    var body: some View {
        HStack(spacing: 24) {
            Button(device.isPhone ? "Vorherige Tage" : "Vorherige Woche", icon: .navArrowLeft) { move(by: -1) }
            Button("Heute") { app.calendarDate = calendar.startOfDay(for: .now) }
                .fontWeight(.semibold)
            Button(device.isPhone ? "Nächste Tage" : "Nächste Woche", icon: .navArrowRight) { move(by: 1) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .appGlassEffect(.regular.interactive(), in: .capsule)
    }

    private func move(by pages: Int) {
        app.calendarDate = device.isPhone
            ? calendar.addingVisibleDays(pages * CalendarView.phoneDayCount, to: app.calendarDate, weekdays: settings.visibleWeekdays)
            : calendar.date(byAdding: .weekOfYear, value: pages, to: app.calendarDate) ?? app.calendarDate
    }
}

private extension View {
    /// iPad: Sheet in Inhaltsgröße (`.fitted`); iPhone: normales Sheet, Inhalt oben.
    @ViewBuilder
    func fittedSheetOnPad(_ device: Device) -> some View {
        if device.isPad {
            appPresentationSizing(.fitted)
        } else {
            self
        }
    }
}
