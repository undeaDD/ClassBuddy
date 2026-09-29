import SwiftUI

/// Startseite – vorerst Platzhalter.
struct DashboardView: View {
    var body: some View {
        PlaceholderView(tab: .dashboard)
    }
}

#Preview {
    NavigationStack { DashboardView() }
}
