import SwiftData
import SwiftUI

/// Zeigt den Inhalt nur, wenn eine Klasse ausgewählt ist – sonst einen einheitlichen Leerzustand.
/// Auf der Übersicht (`showsFirstClassTip`) steht darüber der Tipp „Erste Klasse anlegen“; nach dem
/// Schließen füllt der Leerzustand wieder die ganze Höhe.
struct ClassScopedView<Content: View>: View {
    @Environment(AppModel.self) private var app
    @Environment(\.device) private var device
    @Query private var classes: [SchoolClass]

    var showsFirstClassTip = false
    @ViewBuilder var content: (SchoolClass) -> Content

    var body: some View {
        // Gelöschte Klassen nie mehr anzeigen (zwischen Löschen und Aktualisieren der Abfrage).
        if let schoolClass = classes.first(where: { $0.id == app.selectedClassID && !$0.isDeleted }) {
            content(schoolClass)
        } else {
            VStack(spacing: 0) {
                if showsFirstClassTip, DashboardTipCard.showsFirstClassTip(classes: classes) {
                    DashboardTipCard(schoolClass: nil)
                        .frame(maxWidth: device.isPhone ? .infinity : 480)
                        .padding(24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                EmptyStateView(
                    title: loc("Keine Klasse ausgewählt"),
                    message: classes.isEmpty
                        ? loc("Legen Sie oben links Ihre erste Klasse an.")
                        : loc("Wählen Sie oben links eine Klasse aus.")
                )
                .frame(maxHeight: .infinity)
            }
            .animation(.smooth, value: TipVisibility.shared.displayable)
            .background(Color(.systemGroupedBackground))
        }
    }
}
