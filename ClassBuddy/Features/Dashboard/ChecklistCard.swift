import SwiftUI

/// Kachel „Checklisten“: zuletzt bearbeitete Checkliste der Klasse mit Fortschritt; öffnet sie im Checklisten-Tab.
struct ChecklistsDashboardCard: View {
    @Environment(AppModel.self) private var app
    let schoolClass: SchoolClass

    var body: some View {
        let card = DashboardBuiltInCard.checklists
        if let checklist = schoolClass.latestChecklist {
            let progress = checklist.progress
            StatCard(
                title: card.title,
                value: "\(progress.done)/\(progress.total)",
                detail: checklist.subtitle.isEmpty ? checklist.title : "\(checklist.title) · \(checklist.subtitle)",
                symbol: card.symbol,
                isSensitive: false
            ) {
                app.openChecklist(checklist.id)
            }
        } else {
            StatCard(title: card.title, value: "–", detail: loc("Noch keine Checklisten"), symbol: card.symbol, isSensitive: false) {
                app.open(.checklists)
            }
        }
    }
}
