import SwiftUI

/// Startseite – vorerst Platzhalter.
struct DashboardView: View {
    var body: some View {
        ClassScopedView { _ in
            PlaceholderView(tab: .dashboard)
        }
        .navigationTitle(AppTab.dashboard.title)
        .appChrome(tab: .dashboard)
    }
}

#Preview {
    NavigationStack { DashboardView() }
}
