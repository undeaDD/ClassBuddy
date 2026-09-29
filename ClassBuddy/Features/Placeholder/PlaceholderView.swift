import SwiftUI

/// Platzhalter für Seiten, die noch in Arbeit sind.
/// Zeigt den gemeinsamen Leerzustand plus die geplanten Funktionen des Tabs.
struct PlaceholderView: View {
    let tab: AppTab

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                EmptyStateView(
                    title: tab.title,
                    message: tab.summary,
                    symbol: tab.symbol,
                    badge: "In Arbeit"
                )
                .frame(minHeight: 360)

                if !tab.plannedFeatures.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Geplant")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        ForEach(tab.plannedFeatures, id: \.self) { feature in
                            Label(feature, systemImage: "circle.dashed")
                                .foregroundStyle(.primary)
                        }
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                    .padding(20)
                    .background(.background.secondary, in: .rect(cornerRadius: 20))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal)
        }
        .navigationTitle(tab.title)
    }
}

#Preview {
    NavigationStack {
        PlaceholderView(tab: .seating)
    }
}
