import QuickLook
import SwiftData
import SwiftUI

/// Startseite der ausgewählten Klasse: Kachel-Grid aus Kennzahlen und eigenen
/// Kacheln (Dokumente, Websites). Kacheln lassen sich per Drag & Drop sortieren,
/// eigene Kacheln per langem Druck bearbeiten/entfernen. Reihenfolge je Klasse.
/// Im Privatsphäre-Modus: Inhalte ausgeblendet, keine Änderungen.
struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var lessons: [Lesson]
    @Query private var holidays: [Holiday]

    @State private var isAddDialogPresented = false
    @State private var isFileImporterPresented = false
    @State private var linkEditorRoute: LinkEditorRoute?
    @State private var previewURL: URL?
    @State private var importError: String?

    /// Fest eingebaute Kacheln.
    private enum BuiltInCard: String, CaseIterable {
        case students = "stat.students"
        case nextLesson = "stat.nextLesson"
    }

    private var canEdit: Bool { !security.isPrivacyModeOn }

    var body: some View {
        ClassScopedView { schoolClass in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(orderedCardIDs(for: schoolClass), id: \.self) { cardID in
                        card(cardID, in: schoolClass)
                            .reorderable(id: cardID, enabled: canEdit) { dragged in
                                move(dragged, before: cardID, in: schoolClass)
                            }
                    }

                    if canEdit {
                        AddCard { isAddDialogPresented = true }
                            .confirmationDialog("Kachel hinzufügen", isPresented: $isAddDialogPresented) {
                                Button("Dokument aus „Dateien“") { isFileImporterPresented = true }
                                Button("Website") { linkEditorRoute = .newWebsite(schoolClass) }
                            }
                    }
                }
                .padding(24)
                .animation(.smooth, value: schoolClass.dashboardOrder)
            }
            .background(Color(.systemGroupedBackground))
            .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item]) { result in
                importFile(result, into: schoolClass)
            }
        }
        .navigationTitle(AppTab.dashboard.title)
        .appChrome(tab: .dashboard)
        .sheet(item: $linkEditorRoute) { route in
            LinkEditorView(route: route)
        }
        .quickLookPreview($previewURL)
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                linkEditorRoute = nil
                isAddDialogPresented = false
                previewURL = nil
            }
        }
    }

    // MARK: Kacheln

    @ViewBuilder
    private func card(_ cardID: String, in schoolClass: SchoolClass) -> some View {
        switch BuiltInCard(rawValue: cardID) {
        case .students:
            StatCard(
                title: "Schüler",
                value: "\(schoolClass.students.count)",
                symbol: AppTab.students.symbol
            ) {
                app.open(.students)
            }
        case .nextLesson:
            nextLessonCard(for: schoolClass)
        case nil:
            if let link = schoolClass.dashboardLinks.first(where: { $0.cardID == cardID }) {
                LinkCard(link: link) { open(link) }
                    .contextMenu {
                        if canEdit {
                            Button("Bearbeiten", image: .editPencil) { linkEditorRoute = .edit(link) }
                            Button("Entfernen", image: .trash, role: .destructive) { remove(link) }
                        }
                    }
            }
        }
    }

    /// Nächste Stunde der Klasse; öffnet den Kalender auf diese Klasse fokussiert.
    private func nextLessonCard(for schoolClass: SchoolClass) -> some View {
        let schedule = LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots)
        let next = schedule.nextLesson(forClass: schoolClass.id)
        return StatCard(
            title: "Nächste Stunde",
            value: next.map { relativeDay($0.start) } ?? "–",
            detail: next.map { next in
                ["\(next.slot.number). Stunde, \(next.slot.start.clockString)", next.lesson.subject]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            } ?? "Noch keine Stunde im Kalender",
            symbol: AppTab.calendar.symbol
        ) {
            app.openCalendar(focusing: schoolClass.id, at: next?.start)
        }
    }

    private func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.school
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInTomorrow(date) { return "Morgen" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: Reihenfolge

    /// Gespeicherte Reihenfolge; neue Kacheln hinten, gelöschte fallen raus.
    private func orderedCardIDs(for schoolClass: SchoolClass) -> [String] {
        let available = BuiltInCard.allCases.map(\.rawValue)
            + schoolClass.dashboardLinks.sorted { $0.createdAt < $1.createdAt }.map(\.cardID)
        let saved = schoolClass.dashboardOrder.filter(available.contains)
        return saved + available.filter { !saved.contains($0) }
    }

    private func move(_ dragged: String, before target: String, in schoolClass: SchoolClass) {
        guard dragged != target else { return }
        var order = orderedCardIDs(for: schoolClass)
        guard let from = order.firstIndex(of: dragged), let to = order.firstIndex(of: target) else { return }
        // Gezogene Kachel übernimmt den Platz der Ziel-Kachel.
        order.remove(at: from)
        order.insert(dragged, at: to)
        schoolClass.dashboardOrder = order
        try? modelContext.save()
    }

    // MARK: Eigene Kacheln

    private func open(_ link: DashboardLink) {
        guard let url = link.url else { return }
        switch link.kind {
        case .website: openURL(url)
        case .file: previewURL = url
        }
    }

    private func importFile(_ result: Result<URL, Error>, into schoolClass: SchoolClass) {
        do {
            let source = try result.get()
            let path = try LinkFileStore.importFile(from: source)
            let title = source.deletingPathExtension().lastPathComponent
            modelContext.insert(DashboardLink(title: title, kind: .file, location: path, schoolClass: schoolClass))
            try modelContext.save()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func remove(_ link: DashboardLink) {
        LinkFileStore.removeFile(of: link)
        modelContext.delete(link)
        try? modelContext.save()
    }
}

// MARK: - Drag & Drop

private extension View {
    /// Kachel per Drag & Drop umsortierbar (langes Drücken, dann ziehen).
    @ViewBuilder
    func reorderable(id: String, enabled: Bool, onDrop: @escaping (String) -> Void) -> some View {
        if enabled {
            draggable(id)
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first else { return false }
                    onDrop(dragged)
                    return true
                }
        } else {
            self
        }
    }
}

// MARK: - Kacheln

private let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
private let cardMinHeight: CGFloat = 150

/// Kennzahl-Kachel; antippen öffnet die zugehörige Seite.
/// Wert und Detail werden im Privatsphäre-Modus ausgeblendet.
struct StatCard: View {
    let title: String
    let value: String
    var detail: String?
    let symbol: AppSymbol
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: title, symbol: symbol, showsChevron: action != nil)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .sensitive()
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .sensitive()
                    }
                }
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .disabled(action == nil)
    }
}

/// Eigene Kachel: Dokument oder Website.
private struct LinkCard: View {
    let link: DashboardLink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(
                    title: link.kind == .file ? "Dokument" : "Website",
                    symbol: link.kind == .file ? .system("doc") : .system("link"),
                    showsChevron: true
                )
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title.isEmpty ? link.detail : link.title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                        .sensitive()
                    Text(link.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .sensitive()
                }
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }
}

/// „+“-Kachel am Ende des Grids.
private struct AddCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(.plus).iconSize(36)
                Text("Kachel hinzufügen")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight)
            .overlay(cardShape.strokeBorder(.tint.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
            .contentShape(.hoverEffect, cardShape)
            .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }
}

private struct CardHeader: View {
    let title: String
    let symbol: AppSymbol
    let showsChevron: Bool

    var body: some View {
        HStack {
            Label(title, symbol: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            if showsChevron {
                Image(.navArrowRight)
                    .iconSize(18)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
            // Weiß (hell) bzw. Dunkelgrau (dunkel) auf dem gruppierten Hintergrund.
            .background(Color(.secondarySystemGroupedBackground), in: cardShape)
            .contentShape(.hoverEffect, cardShape)
            .contentShape(.dragPreview, cardShape)
    }
}

#Preview {
    NavigationStack { DashboardView() }
}
