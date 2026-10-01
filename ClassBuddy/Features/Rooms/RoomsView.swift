import SwiftUI

/// Räume – vorerst Platzhalter.
struct RoomsView: View {
    var body: some View {
        EmptyStateView(
            title: AppTab.rooms.title,
            message: loc("Hier verwalten Sie bald Ihre Räume und deren Sitzordnungen."),
            symbol: AppTab.rooms.symbol
        )
        .background(Color(.systemGroupedBackground))
        .navigationTitle(AppTab.rooms.title)
        // Später die Anzahl der Räume, wie „n Schüler“ in der Schülerliste.
        .navigationSubtitle("Noch keine Räume")
        .appChrome(tab: .rooms)
    }
}

#Preview {
    NavigationStack { RoomsView() }
}
