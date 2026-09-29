import SwiftUI

/// Gemeinsamer Leerzustand für alle Seiten (keine Daten, keine Klasse, WIP …).
struct EmptyStateView<Actions: View>: View {
    let title: String
    let message: String
    let symbol: AppSymbol
    @ViewBuilder var actions: Actions

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                // Feste Größe, damit SF Symbols und eigene SVG-Icons gleich groß sind.
                symbol.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.title2.bold())
            }
        } description: {
            Text(message)
                .frame(maxWidth: 420)
        } actions: {
            actions
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, message: String, symbol: AppSymbol) {
        self.init(title: title, message: message, symbol: symbol) { EmptyView() }
    }
}

#Preview("Leerzustand") {
    EmptyStateView(
        title: "Keine Schüler",
        message: "Füge Schülerinnen und Schüler hinzu, um loszulegen.",
        symbol: .system("person.3")
    ) {
        Button("Schüler hinzufügen") {}
            .buttonStyle(.borderedProminent)
    }
}
