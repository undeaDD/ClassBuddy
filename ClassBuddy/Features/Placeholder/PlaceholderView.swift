import SwiftUI

/// Platzhalter für Seiten, die noch in Arbeit sind.
struct PlaceholderView: View {
    let tab: AppTab

    var body: some View {
        EmptyStateView(title: tab.title, message: tab.summary, symbol: tab.symbol)
            .navigationTitle(tab.title)
    }
}

#Preview {
    NavigationStack {
        PlaceholderView(tab: .seating)
    }
}
