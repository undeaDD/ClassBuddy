import SwiftUI

/// Gemeinsamer Leerzustand für alle Seiten (keine Daten, keine Klasse, WIP …).
struct EmptyStateView<Actions: View>: View {
    @Environment(\.device) private var device
    let title: String
    let message: String
    let symbol: AppSymbol
    @ViewBuilder var actions: Actions

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                // iPhone: kleiner, damit Titel und Text nicht den halben Bildschirm füllen.
                symbol.image
                    .iconSize(device.isPhone ? 48 : 64)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(device.isPhone ? .title3.bold() : .title2.bold())
            }
        } description: {
            Text(message)
                .font(device.isPhone ? .subheadline : .body)
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

/// Leerzustand für eine Suche ohne Treffer (eigenes Icon statt `ContentUnavailableView.search`).
struct SearchEmptyStateView: View {
    let text: String

    var body: some View {
        EmptyStateView(
            title: loc("Keine Ergebnisse"),
            message: text.isEmpty ? loc("Keine Treffer.") : loc("Keine Treffer für „\(text)“."),
            symbol: .custom(.search)
        )
    }
}

#Preview(loc("Leerzustand")) {
    EmptyStateView(
        title: loc("Keine Schüler"),
        message: loc("Fügen Sie Schülerinnen und Schüler hinzu, um loszulegen."),
        symbol: .custom(.community)
    ) {
        Button("Schüler hinzufügen") {}
            .buttonStyle(.borderedProminent)
    }
}
