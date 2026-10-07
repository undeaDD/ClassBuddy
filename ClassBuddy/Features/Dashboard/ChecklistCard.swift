import SwiftUI

/// Kachel „Checklisten“: zuletzt bearbeitete Checkliste der Klasse mit Fortschritt; öffnet sie im Checklisten-Tab.
struct ChecklistsDashboardCard: View {
    @Environment(AppModel.self) private var app
    let schoolClass: SchoolClass

    var body: some View {
        let card = DashboardBuiltInCard.checklists
        if let checklist = schoolClass.latestChecklist {
            let progress = checklist.progress
            Button(action: Haptics.tapping { app.openChecklist(checklist.id) }) {
                ChecklistCardContent(
                    title: checklist.subtitle.isEmpty ? checklist.title : "\(checklist.title) · \(checklist.subtitle)",
                    done: progress.done,
                    total: progress.total
                )
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
        } else {
            StatCard(title: card.title, value: "–", detail: loc("Noch keine Checklisten"), symbol: card.symbol, isSensitive: false) {
                app.open(.checklists)
            }
        }
    }
}

/// Inhalt der Checklisten-Kachel (auch Galerie-Vorschau): Titel der Liste, darunter der Fortschrittsbalken.
struct ChecklistCardContent: View {
    let title: String
    let done: Int
    let total: Int

    var body: some View {
        let card = DashboardBuiltInCard.checklists
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: card.title, symbol: card.symbol, showsChevron: true)
            Spacer(minLength: 0)
            // Bis zu zwei Zeilen; feste Höhe verhindert, dass der Platz auf eine Zeile zusammengedrückt wird.
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .leadingAligned()
            ChecklistProgressBar(done: done, total: total)
        }
        .cardStyle()
    }
}
