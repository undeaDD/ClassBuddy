import SwiftData
import SwiftUI

/// Checklisten-Tab: Checklisten der Klasse als Kacheln, gruppiert nach aktuellem Fach, „Alle Fächer“ und den übrigen Fächern.
/// Antippen öffnet die Schülerliste, langes Drücken bearbeitet, dupliziert oder löscht.
struct ChecklistsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.device) private var device
    @Query private var classes: [SchoolClass]
    @Query private var lessons: [Lesson]
    @Query private var holidays: [Holiday]

    @State private var editorRoute: ChecklistEditorRoute?
    @State private var openChecklist: Checklist?
    @State private var pendingDeletion: Checklist?

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == app.selectedClassID }
    }

    var body: some View {
        ClassScopedView { schoolClass in
            content(for: schoolClass)
                .task(id: schoolClass.id) { openRequestedChecklist(in: schoolClass) }
        }
        .navigationTitle(AppTab.checklists.title)
        .appChrome(tab: .checklists) {
            if let selectedClass {
                Button("Neue Checkliste", icon: .plus) {
                    editorRoute = .new(selectedClass, subject: currentSubject(in: selectedClass))
                }
                .disabled(security.isPrivacyModeOn)
            }
        }
        .navigationDestination(item: $openChecklist) { checklist in
            ChecklistDetailView(checklist: checklist)
                .hidesTabBar()
        }
        .onChange(of: app.checklistToOpen) {
            if let selectedClass { openRequestedChecklist(in: selectedClass) }
        }
        .sheet(item: $editorRoute) { route in
            ChecklistEditorView(route: route)
        }
        .confirmationDialog(
            "Checkliste löschen?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { checklist in
            Button("Löschen", role: .destructive) { delete(checklist) }
        } message: { _ in
            Text("Alle Haken dieser Checkliste werden entfernt. Das kann nicht rückgängig gemacht werden.")
        }
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                editorRoute = nil
                pendingDeletion = nil
            }
        }
    }

    @ViewBuilder
    private func content(for schoolClass: SchoolClass) -> some View {
        let current = currentSubject(in: schoolClass)
        let groups = ChecklistGrouping.groups(
            schoolClass.checklists.map { .init(id: $0.id, subject: $0.subject, updatedAt: $0.updatedAt) },
            subjects: schoolClass.subjects,
            current: current
        )
        if groups.isEmpty {
            EmptyStateView(
                title: loc("Noch keine Checklisten"),
                message: loc("Legen Sie über + oben rechts eine Checkliste an, z. B. „Name in die Bücher eingetragen“."),
                symbol: AppTab.checklists.symbol
            )
            .background(Color(.systemGroupedBackground))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(groups, id: \.subject) { group in
                        section(group, in: schoolClass)
                    }
                }
                .padding(24)
                .animation(.smooth, value: groups)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func section(_ group: ChecklistGrouping.Group, in schoolClass: SchoolClass) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(group.subject.map(SchoolClass.displayName(ofSubject:)) ?? loc("Alle Fächer"))
                if group.isCurrent {
                    Image(icon: .calendar)
                        .iconSize(16)
                        .foregroundStyle(.tint)
                        .accessibilityLabel(loc("Aktuelle Stunde"))
                }
            }
            .font(.headline)
            .foregroundStyle(.secondary)
            LazyVGrid(
                // iPhone: volle Breite untereinander; iPad: Raster wie in der Übersicht.
                columns: device.isPhone
                    ? [GridItem(.flexible(), spacing: 16)]
                    : [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(group.ids.compactMap { id in schoolClass.checklists.first { $0.id == id } }) { checklist in
                    ChecklistTile(checklist: checklist) { openChecklist = checklist }
                        .contextMenu {
                            if !security.isPrivacyModeOn {
                                Button("Bearbeiten", icon: .editPencil) { editorRoute = .edit(checklist) }
                                Button("Duplizieren", icon: .duplicate) { duplicate(checklist) }
                                Button("Löschen", destructiveIcon: .trash) { pendingDeletion = checklist }
                            }
                        }
                }
            }
        }
    }

    // MARK: Aktionen

    private func currentSubject(in schoolClass: SchoolClass) -> String? {
        BoardSubject.current(for: schoolClass, schedule: LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots))
    }

    /// Kachel „Checklisten“: Checkliste direkt öffnen.
    private func openRequestedChecklist(in schoolClass: SchoolClass) {
        guard let id = app.checklistToOpen else { return }
        app.checklistToOpen = nil
        openChecklist = schoolClass.checklists.first { $0.id == id }
    }

    private func duplicate(_ checklist: Checklist) {
        _ = checklist.duplicate(in: modelContext)
        save(success: loc("Checkliste dupliziert"))
    }

    private func delete(_ checklist: Checklist) {
        modelContext.delete(checklist)
        save(success: loc("Checkliste gelöscht"))
    }

    private func save(success: String) {
        do {
            try modelContext.save()
            toasts.success(success)
        } catch {
            toasts.error(loc("Speichern fehlgeschlagen: \(error.localizedDescription)"))
        }
    }
}

/// Kachel einer Checkliste: Titel, Untertitel, Fortschritt und zuletzt bearbeitet.
private struct ChecklistTile: View {
    let checklist: Checklist
    let action: () -> Void

    var body: some View {
        let progress = checklist.progress
        Button(action: Haptics.tapping(action)) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(checklist.title)
                        .font(.headline)
                        .lineLimit(2)
                    if !checklist.subtitle.isEmpty {
                        Text(checklist.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                ChecklistProgressBar(done: progress.done, total: progress.total)
                HStack {
                    if let due = checklist.dueDate {
                        Text(loc("Bis \(due.appDate)"))
                            .foregroundStyle(checklist.isOverdue ? Color.red : Color.secondary)
                            .fontWeight(checklist.isOverdue ? .semibold : .regular)
                    } else {
                        Text(ChecklistFormat.edited(checklist.updatedAt))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            // Höhe nach Inhalt (kompakter als die Übersichts-Kacheln).
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: cardShape)
            .contentShape(.hoverEffect, cardShape)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .contentShape(.contextMenuPreview, cardShape)
    }
}

/// Fortschritt einer Checkliste: Balken wie bei den Wochenstunden, „x von y erledigt“ darin.
struct ChecklistProgressBar: View {
    let done: Int
    let total: Int

    var body: some View {
        CapsuleProgressBar(
            value: total == 0 ? 0 : Double(done) / Double(total),
            label: loc("\(done) von \(total) erledigt")
        )
    }
}

enum ChecklistFormat {
    /// „Bearbeitet heute um 09:12“ bzw. „Bearbeitet am 6. Okt.“.
    static func edited(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return loc("Bearbeitet heute um \(date.appTime)")
        }
        return loc("Bearbeitet am \(date.appDate)")
    }

    /// „Abgehakt am 6. Okt. um 09:12“.
    static func checked(_ date: Date) -> String {
        loc("Abgehakt am \(date.appDateTime)")
    }
}
