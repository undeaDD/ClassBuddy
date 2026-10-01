import SwiftData
import SwiftUI

/// Zeigt den Inhalt nur, wenn eine Klasse ausgewählt ist – sonst einen einheitlichen Leerzustand.
struct ClassScopedView<Content: View>: View {
    @Environment(AppModel.self) private var app
    @Query private var classes: [SchoolClass]

    @ViewBuilder var content: (SchoolClass) -> Content

    var body: some View {
        if let schoolClass = classes.first(where: { $0.id == app.selectedClassID }) {
            content(schoolClass)
        } else {
            EmptyStateView(
                title: loc("Keine Klasse ausgewählt"),
                message: classes.isEmpty
                    ? loc("Legen Sie oben links Ihre erste Klasse an.")
                    : loc("Wählen Sie oben links eine Klasse aus."),
                symbol: .custom(.userXmark)
            )
            .background(Color(.systemGroupedBackground))
        }
    }
}
