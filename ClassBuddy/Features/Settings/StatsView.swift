import Charts
import SwiftData
import SwiftUI

/// Globale Statistiken: Kennzahlen, Diagramme und Zähler über alle Klassen.
/// Alles wird lokal berechnet; Schülerdaten sind im Privatsphäre-Modus geschwärzt bzw. unscharf.
struct StatsView: View {
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.device) private var device
    @Query(sort: \SchoolClass.shortName) private var classes: [SchoolClass]
    @Query private var lessons: [Lesson]
    @Query private var holidays: [Holiday]
    @Query private var rooms: [Room]
    @Query private var links: [DashboardLink]
    @Query private var seats: [SeatAssignment]
    @Query private var boardPhotos: [BoardPhoto]

    @State private var dataSize: Int64?

    private var students: [Student] { classes.flatMap(\.students) }
    private var recurringLessons: [Lesson] { lessons.filter(\.isRecurring) }
    private var holidayRanges: [HolidayRange] {
        holidays.map { HolidayRange(name: $0.name, start: $0.startDate, end: $0.endDate, isSchoolHoliday: $0.isSchoolHoliday) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section(loc("Überblick"), columns: valueColumns) { overviewCards }
                section(loc("Diagramme"), columns: chartColumns) { chartCards }
                section(loc("Sonstige"), columns: valueColumns) { funCards }
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Globale Statistiken")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PrivacyModeButton()
            }
        }
        .task {
            dataSize = await Task.detached { LocalDataStore.totalSize() }.value
        }
    }

    private var valueColumns: [GridItem] {
        // iPhone: volle Breite untereinander wie in der Übersicht.
        device.isPhone
            ? [GridItem(.flexible(), spacing: 16, alignment: .top)]
            : [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)]
    }

    private var chartColumns: [GridItem] {
        device.isPhone
            ? [GridItem(.flexible(), spacing: 16, alignment: .top)]
            : [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]
    }

    private func section<Content: View>(_ title: String, columns: [GridItem], @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16, content: content)
        }
    }

    // MARK: Überblick

    @ViewBuilder
    private var overviewCards: some View {
        StatCard(
            title: loc("Klassen"),
            value: "\(classes.count)",
            detail: Set(classes.map(\.schoolYear)).sorted().joined(separator: ", ").nonEmpty ?? loc("Noch keine Klassen"),
            symbol: .custom(.graduationCap),
            isSensitive: false
        )
        StatCard(
            title: loc("Schüler"),
            value: "\(students.count)",
            detail: loc("\(students.filter { $0.birthday != nil }.count) mit Geburtstag"),
            symbol: .custom(.community)
        )
        StatCard(
            title: loc("Stunden pro Woche"),
            value: "\(recurringLessons.count)",
            detail: loc("\(weeklyMinutes / 60) h \(weeklyMinutes % 60) min Unterricht"),
            symbol: .custom(.time),
            isSensitive: false
        )
        let seatCount = rooms.reduce(0) { $0 + $1.seatCount }
        StatCard(
            title: loc("Räume"),
            value: "\(rooms.count)",
            detail: loc("\(seatCount) Plätze · \(seats.count) belegt"),
            symbol: .custom(.floorLayout),
            isSensitive: false
        )
        let next = StatsLogic.nextHoliday(holidayRanges, weekdays: settings.visibleWeekdays, today: .now)
        StatCard(
            title: loc("Bis zu den Ferien"),
            value: next.map { loc("\($0.schoolDays) Tage") } ?? "–",
            detail: next.map { loc("Schultage bis \($0.name)") } ?? loc("Keine Ferien importiert"),
            symbol: .custom(.calendar),
            isSensitive: false
        )
        let installDate = InstallInfo.installDate
        StatCard(
            title: loc("App in Benutzung"),
            value: installDate.map { loc("\(max(0, Calendar.school.dateComponents([.day], from: $0, to: .now).day ?? 0)) Tage") } ?? "–",
            detail: installDate.map { loc("Seit \($0.appDate)") },
            symbol: .custom(.app),
            isSensitive: false
        )
        StatCard(
            title: loc("Speicher"),
            value: dataSize.map { $0.formatted(.byteCount(style: .file)) } ?? "…",
            detail: loc("Datenbank, Dokumente und Fotos"),
            symbol: .custom(.data),
            isSensitive: false
        )
        StatCard(
            title: loc("Tafelbilder"),
            value: "\(boardPhotos.count)",
            detail: loc("Eins je Klasse und Fach"),
            symbol: AppTab.board.symbol,
            isSensitive: false
        )
        StatCard(
            title: loc("Eigene Kacheln"),
            value: "\(links.count)",
            detail: loc("In allen Klassen"),
            symbol: .custom(.link),
            isSensitive: false
        )
    }

    /// Unterrichtsminuten pro Woche (Länge der jeweiligen Stunde aus den Schuleinstellungen).
    private var weeklyMinutes: Int {
        let slots = settings.slots
        return recurringLessons.reduce(0) { total, lesson in
            total + (slots.first { $0.index == lesson.slotIndex }.map { $0.end - $0.start } ?? settings.values.lessonDuration)
        }
    }

    // MARK: Diagramme

    @ViewBuilder
    private var chartCards: some View {
        ChartCard(title: loc("Stundenplan"), detail: loc("Regelmäßige Stunden je Wochentag und Stunde"), symbol: .custom(.calendar)) {
            TimetableHeatmap(lessons: recurringLessons, weekdays: settings.visibleWeekdays, slotCount: settings.slots.count)
        }
        ChartCard(title: loc("Stunden je Fach"), detail: loc("Regelmäßige Stunden pro Woche"), symbol: .custom(.graduationCap)) {
            SubjectChart(lessons: recurringLessons)
        }
        ChartCard(title: loc("Schüler je Klasse"), detail: loc("Nach Geschlecht"), symbol: .custom(.community)) {
            StudentsPerClassChart(classes: classes)
                .sensitiveBlur()
        }
        ChartCard(title: loc("Geburtstage je Monat"), detail: loc("Der aktuelle Monat ist hervorgehoben"), symbol: .custom(.birthday)) {
            BirthdayChart(birthdays: students.compactMap(\.birthday))
                .sensitiveBlur()
        }
        let year = StatsLogic.schoolYear(holidayRanges, today: .now)
        ChartCard(
            title: loc("Schuljahr"),
            detail: loc("\(Int((StatsLogic.progress(of: year, at: .now) * 100).rounded())) % geschafft · Ferien grau"),
            symbol: .custom(.graphUp)
        ) {
            SchoolYearChart(year: year, holidays: holidayRanges.filter(\.isSchoolHoliday))
        }
        ChartCard(title: loc("Altersverteilung"), detail: loc("Alle Schüler mit Geburtstag"), symbol: .custom(.graphUp)) {
            AgeChart(birthdays: students.compactMap(\.birthday))
                .sensitiveBlur()
        }
    }

    // MARK: Sonstige

    @ViewBuilder
    private var funCards: some View {
        ForEach(FunStat.allCases) { stat in
            StatCard(title: stat.title, value: stat.formatted(stat.value()), detail: stat.detail, symbol: stat.symbol, isSensitive: false)
        }
    }
}

private extension FunStat {
    var symbol: AppSymbol {
        switch self {
        case .appLaunches: .custom(.app)
        case .randomPicks: DashboardBuiltInCard.randomStudent.symbol
        case .groupsDealt: DashboardBuiltInCard.groups.symbol
        case .timerMinutes: DashboardBuiltInCard.timer.symbol
        case .loudSeconds: DashboardBuiltInCard.noiseMeter.symbol
        case .boardPhotos: AppTab.board.symbol
        case .checksSet: AppTab.checklists.symbol
        case .observations: AppTab.notes.symbol
        }
    }

    var detail: String {
        switch self {
        case .appLaunches: loc("So oft wurde die App geöffnet")
        case .randomPicks: loc("Mit der Kachel „Zufallsauswahl“")
        case .groupsDealt: loc("Mit der Kachel „Gruppen“")
        case .timerMinutes: loc("Gelaufene Zeit aller Timer")
        case .loudSeconds: loc("Rote Ampel der Lautstärke-Kachel")
        case .boardPhotos: loc("Alle Scans, auch ersetzte")
        case .checksSet: loc("In allen Checklisten")
        case .observations: loc("Im Sitzplan und in der Schülerakte eingetragen")
        }
    }
}

// MARK: - Karten und Diagramme

/// Einheitliche Rundung aller Balken, Flächen und Zellen in den Diagrammen.
private let chartCornerRadius: CGFloat = 4

/// Diagramm-Kachel: Kopf wie die Übersichts-Kacheln, darunter das Diagramm in fester Höhe.
private struct ChartCard<Content: View>: View {
    let title: String
    let detail: String
    let symbol: AppSymbol
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: title, symbol: symbol, showsChevron: false)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content
                .frame(height: 200)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: cardShape)
    }
}

private struct EmptyChart: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Wochentags- und Monatsnamen in der App-Sprache.
private enum ChartLabels {
    static var calendar: Calendar {
        var calendar = Calendar.school
        calendar.locale = AppLanguage.current.locale
        return calendar
    }

    /// 0 = Montag.
    static func weekday(_ index: Int) -> String {
        let symbols = calendar.shortWeekdaySymbols
        return symbols[(index + 1) % symbols.count]
    }

    static func month(_ index: Int) -> String {
        calendar.veryShortMonthSymbols[index]
    }
}

/// Belegung: eine Farbe, je mehr Stunden (mehrere Klassen gleichzeitig), desto kräftiger.
private struct TimetableHeatmap: View {
    @Environment(\.appAccent) private var accent
    let lessons: [Lesson]
    let weekdays: [Int]
    let slotCount: Int

    private struct Cell: Identifiable {
        let weekday: Int
        let slot: Int
        let lessons: Int
        var id: String { "\(weekday)-\(slot)" }
    }

    var body: some View {
        let counts = StatsLogic.heatmap(lessons.map { ($0.weekday, $0.slotIndex) })
        let maxCount = max(counts.values.max() ?? 1, 1)
        let cells = weekdays.flatMap { day in
            (0..<max(slotCount, 1)).map { Cell(weekday: day, slot: $0, lessons: counts[.init(weekday: day, slot: $0)] ?? 0) }
        }
        if lessons.isEmpty {
            EmptyChart(text: loc("Noch keine regelmäßigen Stunden"))
        } else {
            Chart(cells) { cell in
                RectangleMark(
                    x: .value("Stunde", "\(cell.slot + 1)"),
                    y: .value("Tag", ChartLabels.weekday(cell.weekday)),
                    width: .ratio(0.86),
                    height: .ratio(0.86)
                )
                .cornerRadius(chartCornerRadius)
                .foregroundStyle(cell.lessons == 0
                    ? AnyShapeStyle(.quaternary)
                    : AnyShapeStyle(accent.opacity(0.35 + 0.65 * Double(cell.lessons) / Double(maxCount))))
                .accessibilityValue(loc("\(cell.lessons) Stunden"))
            }
            .chartYScale(domain: weekdays.map(ChartLabels.weekday))
            .chartXScale(domain: (0..<max(slotCount, 1)).map { "\($0 + 1)" })
            .chartXAxis { AxisMarks { AxisValueLabel() } }
            .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel() } }
        }
    }
}

/// Regelmäßige Stunden je Fach als liegende Balken (häufigste oben, Rest unter „Andere“).
private struct SubjectChart: View {
    @Environment(\.appAccent) private var accent
    let lessons: [Lesson]

    var body: some View {
        let counts = Dictionary(grouping: lessons) { lesson in
            let name = SchoolClass.displayName(ofSubject: lesson.subject)
            return name.isEmpty ? loc("Ohne Fach") : name
        }
            .map { (subject: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.subject < $1.subject }
        let top = Array(counts.prefix(5))
        let rest = counts.dropFirst(5).reduce(0) { $0 + $1.count }
        let rows = rest > 0 ? top + [(subject: loc("Andere"), count: rest)] : top
        if rows.isEmpty {
            EmptyChart(text: loc("Noch keine regelmäßigen Stunden"))
        } else {
            Chart(rows, id: \.subject) { row in
                BarMark(x: .value("Stunden", row.count), y: .value("Fach", row.subject), height: .ratio(0.6))
                    .cornerRadius(chartCornerRadius)
                    .foregroundStyle(accent)
                    .annotation(position: .trailing) {
                        Text("\(row.count)").font(.caption).foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: rows.map(\.subject))
            .chartXAxis(.hidden)
        }
    }
}

/// Schüler je Klasse, gestapelt nach Geschlecht (feste Farben, Legende darunter).
private struct StudentsPerClassChart: View {
    let classes: [SchoolClass]

    private struct Row: Identifiable {
        let className: String
        let group: String
        let students: Int
        var id: String { "\(className)-\(group)" }
    }

    private static let unknown = loc("Unbekannt")
    private static var groups: [String] { Gender.allCases.map(\.displayTitle) + [unknown] }

    var body: some View {
        let rows = classes.flatMap { schoolClass in
            let name = schoolClass.shortName
            let students = schoolClass.students
            return Gender.allCases.map { gender in
                Row(className: name, group: gender.displayTitle, students: students.filter { $0.gender == gender }.count)
            } + [Row(className: name, group: Self.unknown, students: students.filter { $0.gender == nil }.count)]
        }
        .filter { $0.students > 0 }
        if rows.isEmpty {
            EmptyChart(text: loc("Noch keine Schüler"))
        } else {
            Chart(rows) { row in
                BarMark(x: .value("Klasse", row.className), y: .value("Schüler", row.students), width: .ratio(0.6))
                    .foregroundStyle(by: .value("Geschlecht", row.group))
                    .cornerRadius(chartCornerRadius)
            }
            .chartForegroundStyleScale(domain: Self.groups, range: [Color.pink, Color.blue, Color.purple, Color.gray])
            .chartXScale(domain: classes.map(\.shortName))
            .chartLegend(position: .bottom, alignment: .leading)
        }
    }
}

/// Geburtstage je Monat; der laufende Monat in voller Farbe.
private struct BirthdayChart: View {
    @Environment(\.appAccent) private var accent
    let birthdays: [Date]

    var body: some View {
        let counts = StatsLogic.birthdaysPerMonth(birthdays)
        let current = Calendar.school.component(.month, from: .now) - 1
        if birthdays.isEmpty {
            EmptyChart(text: loc("Noch keine Geburtstage eingetragen"))
        } else {
            Chart(Array(counts.enumerated()), id: \.offset) { month, count in
                BarMark(x: .value("Monat", "\(month)"), y: .value("Geburtstage", count), width: .ratio(0.6))
                    .cornerRadius(chartCornerRadius)
                    .foregroundStyle(month == current ? accent : accent.opacity(0.35))
            }
            .chartXScale(domain: (0..<12).map { "\($0)" })
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let index = value.as(String.self).flatMap(Int.init) { Text(ChartLabels.month(index)) }
                    }
                }
            }
        }
    }
}

/// Schuljahr als Zeitleiste: geschaffter Teil in der Akzentfarbe, Ferien grau, heute als Linie.
private struct SchoolYearChart: View {
    @Environment(\.appAccent) private var accent
    let year: DateInterval
    let holidays: [HolidayRange]

    var body: some View {
        let now = min(max(Date.now, year.start), year.end)
        let inYear = holidays.filter { $0.end >= year.start && $0.start <= year.end }
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                BarMark(xStart: .value("Beginn", year.start), xEnd: .value("Ende", year.end), y: .value("Jahr", ""), height: .fixed(28))
                    .foregroundStyle(.quaternary)
                    .cornerRadius(chartCornerRadius)
                BarMark(xStart: .value("Beginn", year.start), xEnd: .value("Heute", now), y: .value("Jahr", ""), height: .fixed(28))
                    .foregroundStyle(accent)
                    .cornerRadius(chartCornerRadius)
                ForEach(inYear, id: \.self) { holiday in
                    BarMark(
                        xStart: .value("Beginn", max(holiday.start, year.start)),
                        xEnd: .value("Ende", min(holiday.end.addingTimeInterval(86_400), year.end)),
                        y: .value("Jahr", ""),
                        height: .fixed(28)
                    )
                    .foregroundStyle(Color.gray.opacity(0.6))
                    .cornerRadius(chartCornerRadius)
                }
                RuleMark(x: .value("Heute", now))
                    .foregroundStyle(.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXScale(domain: year.start...year.end)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .frame(height: 80)
            HStack {
                Text(year.start.appDate)
                Spacer()
                Text(year.end.appDate)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if holidays.isEmpty {
                Text("Ferien in den Schuleinstellungen importieren, damit das Schuljahr genau stimmt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Anzahl Schüler je Alter.
private struct AgeChart: View {
    @Environment(\.appAccent) private var accent
    let birthdays: [Date]

    var body: some View {
        let ages = StatsLogic.ageDistribution(birthdays, today: .now)
        if ages.isEmpty {
            EmptyChart(text: loc("Noch keine Geburtstage eingetragen"))
        } else {
            Chart(ages, id: \.age) { row in
                BarMark(x: .value("Alter", "\(row.age)"), y: .value("Schüler", row.count), width: .ratio(0.6))
                    .cornerRadius(chartCornerRadius)
                    .foregroundStyle(accent)
            }
            .chartXScale(domain: ages.map { "\($0.age)" })
        }
    }
}
