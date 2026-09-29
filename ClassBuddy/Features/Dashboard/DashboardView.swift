import SwiftData
import SwiftUI

/// Startseite: Überblick über den Tag und die aktive Klasse.
struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Query private var classes: [SchoolClass]

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == app.selectedClassID }
    }

    var body: some View {
        Group {
            if let selectedClass {
                content(for: selectedClass)
            } else {
                noClassState
            }
        }
        .navigationTitle(AppTab.dashboard.title)
    }

    // MARK: Leerzustand

    private var noClassState: some View {
        EmptyStateView(
            title: classes.isEmpty ? "Willkommen!" : "Keine Klasse ausgewählt",
            message: classes.isEmpty
                ? "Lege deine erste Klasse an. Alle Daten bleiben lokal auf diesem iPad."
                : "Wähle oben links eine Klasse aus, um die Übersicht zu sehen.",
            symbol: .system(classes.isEmpty ? "graduationcap" : "person.2.circle")
        ) {
            @Bindable var app = app
            Button(classes.isEmpty ? "Klasse anlegen" : "Klasse auswählen") {
                app.isClassPickerPresented = true
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }

    // MARK: Inhalt

    private func content(for schoolClass: SchoolClass) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(for: schoolClass)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    DashboardCard(title: "Heute", symbol: AppTab.schedule.symbol, destination: .schedule) {
                        CardEmptyHint(text: "Noch kein Stundenplan hinterlegt.")
                    }

                    DashboardCard(title: "Klasse", symbol: AppTab.students.symbol, destination: .students) {
                        HStack(spacing: 0) {
                            StatTile(value: "0", label: "Schüler")
                            Divider().frame(height: 36)
                            StatTile(value: "–", label: "Fehlend heute").sensitive()
                            Divider().frame(height: 36)
                            StatTile(value: "–", label: "Ø Note").sensitive()
                        }
                    }

                    DashboardCard(title: "Schnellzugriff", symbol: .system("bolt"), destination: nil) {
                        QuickLinksGrid(tabs: [.seating, .attendance, .grades, .notes])
                    }

                    DashboardCard(title: "Sitzplan", symbol: AppTab.seating.symbol, destination: .seating) {
                        CardEmptyHint(text: "Noch keine Sitzordnung angelegt.")
                    }

                    DashboardCard(title: "Termine", symbol: AppTab.events.symbol, destination: .events) {
                        CardEmptyHint(text: "Keine anstehenden Termine.")
                    }

                    DashboardCard(title: "Notizen", symbol: AppTab.notes.symbol, destination: .notes) {
                        CardEmptyHint(text: "Noch keine Notizen.")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func header(for schoolClass: SchoolClass) -> some View {
        HStack(spacing: 16) {
            ClassBadge(shortName: schoolClass.shortName, color: schoolClass.color.color, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.largeTitle.bold())
                Text("\(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(schoolClass.title)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: "Guten Morgen"
        case 11..<17: "Hallo"
        default: "Guten Abend"
        }
    }
}

// MARK: - Bausteine

struct DashboardCard<Content: View>: View {
    @Environment(AppModel.self) private var app

    let title: String
    let symbol: AppSymbol
    let destination: AppTab?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, symbol: symbol)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let destination {
                    Button {
                        app.open(destination)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .hoverEffect(.highlight)
                    .accessibilityLabel("\(title) öffnen")
                }
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
        .contentShape(.hoverEffect, .rect(cornerRadius: 22))
        .hoverEffect(.lift)
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CardEmptyHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}

private struct QuickLinksGrid: View {
    @Environment(AppModel.self) private var app
    let tabs: [AppTab]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(tabs) { tab in
                Button {
                    app.open(tab)
                } label: {
                    Label(tab.title, symbol: tab.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(.tint.opacity(0.1), in: .rect(cornerRadius: 12))
                        .contentShape(.hoverEffect, .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
            }
        }
    }
}
