import SwiftData
import SwiftUI

/// Startseite: Kennzahlen der ausgewählten Klasse als Kachel-Grid.
struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(SchoolSettings.self) private var settings
    @Query private var lessons: [Lesson]
    @Query private var holidays: [Holiday]

    var body: some View {
        ClassScopedView { schoolClass in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    StatCard(
                        title: "Schüler",
                        value: "\(schoolClass.students.count)",
                        symbol: AppTab.students.symbol
                    ) {
                        app.open(.students)
                    }

                    nextLessonCard(for: schoolClass)
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(AppTab.dashboard.title)
        .appChrome(tab: .dashboard)
    }

    /// Nächste Stunde der Klasse; öffnet den Kalender auf diese Klasse fokussiert.
    private func nextLessonCard(for schoolClass: SchoolClass) -> some View {
        let schedule = LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots)
        let next = schedule.nextLesson(forClass: schoolClass.id)
        return StatCard(
            title: "Nächste Stunde",
            value: next.map { relativeDay($0.start) } ?? "–",
            detail: next.map { next in
                ["\(next.slot.number). Stunde, \(next.slot.start.clockString)", next.lesson.subject]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            } ?? "Noch keine Stunde im Kalender",
            symbol: AppTab.calendar.symbol
        ) {
            app.openCalendar(focusing: schoolClass.id, at: next?.start)
        }
    }

    private func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.school
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInTomorrow(date) { return "Morgen" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// Kennzahl-Kachel; antippen öffnet die zugehörige Seite.
/// Wert und Detail werden im Privatsphäre-Modus ausgeblendet.
struct StatCard: View {
    let title: String
    let value: String
    var detail: String?
    let symbol: AppSymbol
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(title, symbol: symbol)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .sensitive()
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .sensitive()
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Weiß (hell) bzw. Dunkelgrau (dunkel) auf dem gruppierten Hintergrund.
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .contentShape(.hoverEffect, .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .disabled(action == nil)
    }
}

#Preview {
    NavigationStack { DashboardView() }
}
