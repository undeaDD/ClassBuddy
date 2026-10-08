import QuickLook
import SwiftData
import SwiftUI

/// Schülerliste einer Checkliste: Antippen hakt ab (mit Datum), Zurücknehmen nur nach Bestätigung.
/// Im Privatsphäre-Modus Namen geschwärzt, nichts abhaken und kein PDF.
struct ChecklistDetailView: View {
    @Environment(AppSecurity.self) private var security
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.device) private var device
    let checklist: Checklist

    enum Filter: String, CaseIterable, Identifiable {
        case all, open, done
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: loc("Alle")
            case .open: loc("Offen")
            case .done: loc("Erledigt")
            }
        }
    }

    @State private var filter: Filter = .all
    @State private var pendingUncheck: Student?
    @State private var isEditorPresented = false
    @State private var pdfPreview: URL?

    private var students: [Student] { checklist.schoolClass?.sortedStudents ?? [] }

    private var visibleStudents: [Student] {
        switch filter {
        case .all: students
        case .open: students.filter { checklist.check(for: $0) == nil }
        case .done: students.filter { checklist.check(for: $0) != nil }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if visibleStudents.isEmpty {
                    EmptyStateView(
                        title: students.isEmpty ? loc("Noch keine Schüler") : loc("Keine Schüler in dieser Auswahl"),
                        message: students.isEmpty
                            ? loc("Die Klasse hat noch keine Schüler.")
                            : (filter == .open ? loc("Alle Schüler sind abgehakt.") : loc("Noch niemand ist abgehakt.")),
                        symbol: AppTab.students.symbol
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVGrid(
                        // iPhone: volle Breite; iPad: mehrere Spalten.
                        columns: device.isPhone
                            ? [GridItem(.flexible(), spacing: 12)]
                            : [GridItem(.adaptive(minimum: 300), spacing: 12)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(visibleStudents) { student in
                            ChecklistStudentRow(student: student, check: checklist.check(for: student)) { toggle(student) }
                        }
                    }
                }
            }
            .padding(24)
            .animation(.smooth, value: filter)
        }
        // Platz für die schwebende Leiste unten.
        .contentMargins(.bottom, 72, for: .scrollContent)
        .background(Color(.systemGroupedBackground))
        .floatingBottomBar {
            FloatingSegmentedPicker(title: loc("Anzeigen"), selection: $filter) {
                ForEach(Filter.allCases) { Text($0.title).tag($0) }
            }
        }
        .navigationTitle(checklist.title)
        .appNavigationSubtitle(checklist.scopeTitle)
        .toolbar { toolbar }
        .sheet(isPresented: $isEditorPresented) {
            ChecklistEditorView(route: .edit(checklist))
        }
        .confirmationDialog(
            "Haken entfernen?",
            isPresented: Binding(get: { pendingUncheck != nil }, set: { if !$0 { pendingUncheck = nil } }),
            titleVisibility: .visible,
            presenting: pendingUncheck
        ) { student in
            Button("Haken entfernen", role: .destructive) { uncheck(student) }
        } message: { student in
            Text(checklist.check(for: student).map { loc("Das Datum (\(ChecklistFormat.checked($0.checkedAt))) wird entfernt.") } ?? "")
        }
        .quickLookPreview($pdfPreview)
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                pendingUncheck = nil
                isEditorPresented = false
                pdfPreview = nil
            }
        }
    }

    private var header: some View {
        let progress = checklist.progress
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if !checklist.subtitle.isEmpty {
                    Text(checklist.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: cardShape)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Bearbeiten", icon: .editPencil) { isEditorPresented = true }
                // Vorschau (Quick Look): dort sichern, drucken oder teilen.
                Button("Als PDF exportieren", icon: .page) { pdfPreview = ChecklistPDF.make(checklist: checklist, students: students) }
            } label: {
                Label("Mehr", icon: .moreHoriz)
            }
            .disabled(security.isPrivacyModeOn)
            .toolbarGroupBackground()
        }
        AppToolbarSpacer(placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            PrivacyModeButton()
                .toolbarGroupBackground()
        }
    }

    // MARK: Abhaken

    private func toggle(_ student: Student) {
        guard !security.isPrivacyModeOn else { return }
        if checklist.check(for: student) != nil {
            pendingUncheck = student
        } else {
            Haptics.tap()
            withAnimation(.smooth) { checklist.check(student, in: modelContext) }
            FunStat.checksSet.increment()
            save()
        }
    }

    private func uncheck(_ student: Student) {
        withAnimation(.smooth) { checklist.uncheck(student, in: modelContext) }
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            toasts.error(loc("Speichern fehlgeschlagen: \(error.localizedDescription)"))
        }
    }
}

/// Zeile: Avatar, Name, Abhak-Datum bzw. „Offen“; rechts Kreis (offen) oder Kreis mit Haken (Akzentfarbe).
private struct ChecklistStudentRow: View {
    let student: Student
    let check: ChecklistCheck?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                StudentAvatar(student: student, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.fullName)
                        .font(.body.weight(.medium))
                        .sensitive()
                    Text(check.map { ChecklistFormat.checked($0.checkedAt) } ?? loc("Offen"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                CheckCircle(isChecked: check != nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityValue(check == nil ? loc("Offen") : loc("Erledigt"))
    }
}

/// Kreis (Textfarbe) bzw. Kreis mit Haken (Akzentfarbe).
private struct CheckCircle: View {
    let isChecked: Bool

    var body: some View {
        Image(icon: isChecked ? .checkmarkOn : .checkmarkOff)
            .iconSize(28)
            .foregroundStyle(isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .contentTransition(.symbolEffect(.replace))
    }
}

/// PDF der Checkliste (A4 hoch, hell): links Titel und Untertitel, rechts Exportdatum, Klasse und Fach;
/// darunter die Schüler mit Haken und Datum, bei vielen Schülern auf mehreren Seiten.
enum ChecklistPDF {
    private static let rowsPerPage = 28

    static func make(checklist: Checklist, students: [Student], exportedAt: Date = .now) -> URL? {
        let page = CGSize(width: 595, height: 842)
        let pages = stride(from: 0, to: max(students.count, 1), by: rowsPerPage).map {
            Array(students[min($0, students.count)..<min($0 + rowsPerPage, students.count)])
        }
        let scope = [checklist.schoolClass?.title, checklist.isGlobal ? nil : SchoolClass.displayName(ofSubject: checklist.subject)]
            .compactMap { $0 }
            .joined(separator: " · ")

        let fileName = checklist.title.replacingOccurrences(of: "/", with: "-")
        let url = URL.temporaryDirectory.appending(path: loc("Checkliste \(fileName).pdf"))
        var box = CGRect(origin: .zero, size: page)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for (index, rows) in pages.enumerated() {
            let content = VStack(alignment: .leading, spacing: 16) {
                if index == 0 {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(checklist.title).font(.title.bold())
                            if !checklist.subtitle.isEmpty {
                                Text(checklist.subtitle).font(.title3).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(loc("Exportiert am \(exportedAt.appDate)"))
                            Text(scope)
                            if let due = checklist.dueDate {
                                Text(loc("Bis \(due.appDate)"))
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(rows) { student in
                        ChecklistPDFRow(student: student, check: checklist.check(for: student))
                        Divider()
                    }
                }
                Spacer(minLength: 0)
                SeatingPlanPDF.footer
            }
            .padding(36)
            .frame(width: page.width, height: page.height, alignment: .topLeading)
            .background(.white)
            .environment(\.colorScheme, .light)

            ImageRenderer(content: content).render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }
}

/// Zeile im Checklisten-PDF: Kreis bzw. Kreis mit Haken, Name, Abhak-Datum.
private struct ChecklistPDFRow: View {
    let student: Student
    let check: ChecklistCheck?

    var body: some View {
        HStack {
            Image(icon: check == nil ? .checkmarkOff : .checkmarkOn)
                .iconSize(16)
                .foregroundStyle(.black)
                .frame(width: 24)
            Text(student.fullName)
            Spacer()
            Text(check.map { $0.checkedAt.appDate } ?? "–")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.vertical, 6)
    }
}
