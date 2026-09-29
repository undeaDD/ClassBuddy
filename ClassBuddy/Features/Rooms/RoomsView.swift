import SwiftUI

/// Räume – vorerst Platzhalter.
struct RoomsView: View {
    var body: some View {
        EmptyStateView(
            title: AppTab.rooms.title,
            message: "Hier verwaltest du bald deine Räume und ihre Sitzordnungen.",
            symbol: AppTab.rooms.symbol
        )
        .navigationTitle(AppTab.rooms.title)
        .appChrome(tab: .rooms)
    }
}

#Preview {
    NavigationStack { RoomsView() }
}
