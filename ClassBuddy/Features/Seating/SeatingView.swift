import SwiftUI

/// Sitzplatzverwaltung – vorerst Platzhalter.
struct SeatingView: View {
    var body: some View {
        ClassScopedView { _ in
            PlaceholderView(tab: .seating)
        }
        .navigationTitle(AppTab.seating.title)
        .appChrome(tab: .seating)
    }
}

#Preview {
    NavigationStack { SeatingView() }
}
