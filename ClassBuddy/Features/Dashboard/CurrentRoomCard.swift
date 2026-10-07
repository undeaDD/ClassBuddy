import SwiftUI

/// Kachel „Aktueller Raum“ bzw. „Nächster Raum“; öffnet den Sitzplan (ohne Raum: die Raumübersicht).
struct CurrentRoomCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.device) private var device
    let schedule: LessonSchedule
    let classID: UUID

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let result = RoomLocator.locate(schedule: schedule, classID: classID, now: context.date)
            StatCard(
                title: result?.isCurrent == false ? loc("Nächster Raum") : DashboardBuiltInCard.room.title,
                value: result?.room.name ?? "–",
                detail: result.map(detail) ?? loc("Noch keiner Stunde ist ein Raum zugeordnet"),
                symbol: DashboardBuiltInCard.room.symbol
            ) {
                if let result {
                    app.openSeatingPlan(room: result.room, schoolClass: result.next.lesson.schoolClass, subject: result.next.lesson.subject)
                } else {
                    app.openRooms(isPhone: device.isPhone)
                }
            }
        }
    }

    /// „Jetzt · 3. Stunde · 7b“ bzw. „Morgen · 3. Stunde · 7b“.
    private func detail(_ result: RoomLocator.Result) -> String {
        let calendar = Calendar.school
        let when = result.isCurrent ? loc("Jetzt")
            : calendar.isDateInToday(result.next.start) ? "Heute"
            : calendar.isDateInTomorrow(result.next.start) ? loc("Morgen")
            : result.next.start.appDate
        return [when, loc("\(result.next.slot.number). Stunde"), result.next.lesson.schoolClass?.shortName ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
