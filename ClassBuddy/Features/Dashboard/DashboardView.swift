import SwiftUI

/// Startseite: Kennzahlen der ausgewählten Klasse als Kachel-Grid.
struct DashboardView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ClassScopedView { schoolClass in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    StatCard(
                        title: "Schüler",
                        value: "\(schoolClass.students.count)",
                        symbol: AppTab.students.symbol
                    ) {
                        app.open(.students)
                    }
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(AppTab.dashboard.title)
        .appChrome(tab: .dashboard)
    }
}

/// Kennzahl-Kachel; antippen öffnet die zugehörige Seite.
struct StatCard: View {
    let title: String
    let value: String
    let symbol: AppSymbol
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(title, symbol: symbol)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(value)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 22))
            .contentShape(.hoverEffect, .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .disabled(action == nil)
    }
}

#Preview {
    NavigationStack { DashboardView() }
}
