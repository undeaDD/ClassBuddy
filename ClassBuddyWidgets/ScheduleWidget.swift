import SwiftUI
import WidgetKit

@main
struct ClassBuddyWidgets: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
    }
}

/// „Jetzt & Als Nächstes“: laufende Stunde mit Countdown, sonst die nächste Stunde.
/// Daten schreibt die App (`WidgetSchedule`); ohne geöffnete App bleibt der Stand bis zu 14 Tage gültig.
struct ScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSchedule.widgetKind, provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("Jetzt & Als Nächstes"))
        .description(Text("Die laufende Stunde mit Restzeit, sonst die nächste Stunde – mit Klasse, Fach und Raum."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let current: WidgetSchedule.Lesson?
    let next: [WidgetSchedule.Lesson]
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        Self.sampleEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        let lessons = WidgetSchedule.load()
        completion(context.isPreview && lessons.isEmpty ? Self.sampleEntry : Self.entry(at: .now, lessons: lessons))
    }

    /// Ein Eintrag je Stundenbeginn und -ende; der Countdown läuft dazwischen von selbst (`Text(timerInterval:)`).
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let lessons = WidgetSchedule.load()
        let now = Date.now
        let changes = lessons.flatMap { [$0.start, $0.end] }.filter { $0 > now }.sorted().prefix(40)
        let entries = [Self.entry(at: now, lessons: lessons)] + changes.map { Self.entry(at: $0, lessons: lessons) }
        // Nach dem letzten Wechsel (bzw. spätestens morgen) neu laden – die App schreibt beim nächsten Öffnen nach.
        let reload = changes.last ?? Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        completion(Timeline(entries: entries, policy: .after(reload)))
    }

    private static func entry(at date: Date, lessons: [WidgetSchedule.Lesson]) -> ScheduleEntry {
        let upcoming = WidgetSchedule.upcoming(lessons, at: date)
        return ScheduleEntry(date: date, current: upcoming.current, next: Array(upcoming.next.prefix(3)))
    }

    /// Beispiel für die Widget-Galerie.
    private static var sampleEntry: ScheduleEntry {
        let now = Date.now
        func lesson(_ startOffset: Int, _ number: Int, _ name: String, _ subject: String, _ room: String) -> WidgetSchedule.Lesson {
            WidgetSchedule.Lesson(
                start: now.addingTimeInterval(TimeInterval(startOffset * 60)),
                end: now.addingTimeInterval(TimeInterval((startOffset + 45) * 60)),
                slotNumber: number, className: name, subject: subject, room: room,
                red: 0.0, green: 0.48, blue: 1.0
            )
        }
        return ScheduleEntry(
            date: now,
            current: lesson(-22, 3, "7b", String(localized: "Mathematik"), "R 204"),
            next: [lesson(28, 4, "9a", String(localized: "Physik"), "NW 1"), lesson(85, 5, "Q1", String(localized: "Mathematik"), "R 112")]
        )
    }
}

struct ScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Größen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lesson = entry.current ?? entry.next.first {
                header(isCurrent: entry.current != nil)
                lessonTitle(lesson)
                Spacer(minLength: 0)
                timing(for: lesson, isCurrent: entry.current != nil)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small
            if !followingLessons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Danach")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(followingLessons, id: \.self) { lesson in
                        HStack(spacing: 6) {
                            Capsule().fill(color(of: lesson)).frame(width: 4, height: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: "\(lesson.className) · \(lesson.subject)")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(dayAndTime(lesson.start))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let lesson = entry.current ?? entry.next.first {
                Text(verbatim: "\(lesson.className) · \(lesson.subject)")
                    .font(.headline)
                    .lineLimit(1)
                if let room = lesson.room, !room.isEmpty {
                    Text(room).lineLimit(1)
                }
                if entry.current != nil {
                    Text(timerInterval: lesson.start...lesson.end, countsDown: true)
                        .monospacedDigit()
                } else {
                    Text(dayAndTime(lesson.start))
                }
            } else {
                Text("Keine Stunden")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Auf dem Sperrbildschirm erst nach dem Entsperren lesbar.
        .privacySensitive()
    }

    // MARK: Bausteine

    /// Nächste Stunden ohne die im linken Teil gezeigte.
    private var followingLessons: [WidgetSchedule.Lesson] {
        Array((entry.current == nil ? entry.next.dropFirst() : entry.next[...]).prefix(2))
    }

    private func header(isCurrent: Bool) -> some View {
        Text(isCurrent ? "Jetzt" : "Als Nächstes")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func lessonTitle(_ lesson: WidgetSchedule.Lesson) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: lesson.className)
                .font(.title2.weight(.bold))
                .foregroundStyle(color(of: lesson))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: lesson.subject)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if let room = lesson.room, !room.isEmpty {
                Text(verbatim: room)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .privacySensitive()
    }

    @ViewBuilder
    private func timing(for lesson: WidgetSchedule.Lesson, isCurrent: Bool) -> some View {
        if isCurrent {
            VStack(alignment: .leading, spacing: 4) {
                Text(timerInterval: lesson.start...lesson.end, countsDown: true)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                ProgressView(timerInterval: lesson.start...lesson.end, countsDown: false) { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(color(of: lesson))
                    .labelsHidden()
            }
        } else {
            Text(dayAndTime(lesson.start))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keine Stunden")
                .font(.headline)
            Text("In den nächsten zwei Wochen steht nichts im Kalender. Öffnen Sie ClassBuddy, um den Plan zu aktualisieren.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func color(of lesson: WidgetSchedule.Lesson) -> Color {
        Color(red: lesson.red, green: lesson.green, blue: lesson.blue)
    }

    /// „Heute, 09:50“ / „Morgen, 08:00“ / „Mo., 13.10., 08:00“.
    private func dayAndTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return String(localized: "Heute, \(time)") }
        if calendar.isDateInTomorrow(date) { return String(localized: "Morgen, \(time)") }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).day().month(.twoDigits))), \(time)"
    }
}
