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
                symbol.image
                    .font(.system(size: 56, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 112, height: 112)
                    .background(.tint.opacity(0.12), in: .circle)
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
