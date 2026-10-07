import QuickLook
import SwiftData
import SwiftUI

/// Bewertungen-Tab: „Schüler“ (alphabetisch mit Schnell-Index, durchsuchbar → Fächer → Schülerakte;
/// Export der Notenübersicht bzw. Mitarbeitsliste je Fach) oder „Leistungen“ der Klasse
/// (Klassenarbeiten, Tests, Referate … mit Noten je Schüler).
struct NotesView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Query private var classes: [SchoolClass]
    @State private var searchText = ""
    @State private var mode: Mode = .students
    @State private var assessmentRoute: AssessmentEditorRoute?
    /// Export (PDF / Excel) für Quick Look.
    @State private var exportPreview: URL?

    enum Mode: String, CaseIterable, Identifiable {
        case students, assessments
        var id: String { rawValue }

        var title: String {
            switch self {
            case .students: loc("Schüler")
            case .assessments: loc("Leistungen")
            }
        }
    }

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == app.selectedClassID }
    }

    var body: some View {
        ClassScopedView { schoolClass in
            Group {
                switch mode {
                case .students: content(for: schoolClass)
                case .assessments: AssessmentListView(schoolClass: schoolClass, editorRoute: $assessmentRoute)
                }
            }
            // Platz für die schwebende Leiste unten (mit dem Daumen erreichbar).
            .contentMargins(.bottom, 72, for: .scrollContent)
            .floatingBottomBar {
                FloatingSegmentedPicker(title: loc("Ansicht"), selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
            }
        }
        .navigationTitle(AppTab.notes.title)
        .appChrome(tab: .notes) {
            if let selectedClass, !selectedClass.subjects.isEmpty {
                switch mode {
                case .students:
                    exportMenu(for: selectedClass)
                case .assessments:
                    Button("Neue Leistung", icon: .plus) { assessmentRoute = .new(selectedClass, subject: nil) }
                        .disabled(security.isPrivacyModeOn)
                }
            }
        }
        .quickLookPreview($exportPreview)
        .sheet(item: $assessmentRoute) { AssessmentEditorView(route: $0) }
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                assessmentRoute = nil
                exportPreview = nil
            }
        }
    }

    /// Export je Fach: Notenübersicht (PDF / Excel) und Mitarbeitsliste (PDF), Vorschau in Quick Look.
    private func exportMenu(for schoolClass: SchoolClass) -> some View {
        Menu {
            ForEach(schoolClass.subjects, id: \.self) { subject in
                Section(SchoolClass.displayName(ofSubject: subject)) {
                    Button("Notenübersicht (PDF)", icon: .page) {
                        exportPreview = GradeOverviewTable(schoolClass: schoolClass, subject: subject).pdfFile()
                    }
                    Button("Notenübersicht (Excel)", icon: .shareIos) {
                        exportPreview = GradeOverviewTable(schoolClass: schoolClass, subject: subject).excelFile()
                    }
                    Button("Mitarbeitsliste (PDF)", icon: .page) {
                        exportPreview = GradeOverviewTable(schoolClass: schoolClass, subject: subject).participationPDF()
                    }
                }
            }
        } label: {
            Label("Exportieren", icon: .shareIos)
        }
        .disabled(security.isPrivacyModeOn)
    }

    @ViewBuilder
    private func content(for schoolClass: SchoolClass) -> some View {
        if schoolClass.students.isEmpty {
            EmptyStateView(
                title: loc("Noch keine Schüler"),
                message: loc("Legen Sie im Tab „Schüler“ die Schülerinnen und Schüler der \(schoolClass.title) an."),
                symbol: AppTab.notes.symbol
            )
            .background(Color(.systemGroupedBackground))
        } else {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            let sections = StudentLetterSection.sections(
                for: schoolClass.students.filter { query.isEmpty || $0.fullName.localizedStandardContains(query) }
            )
            List {
                ForEach(sections, id: \.letter) { section in
                    Section(section.letter) {
                        ForEach(section.students) { student in
                            NavigationLink {
                                StudentSubjectsView(student: student)
                            } label: {
                                StudentNameRow(student: student, detail: Self.noteCountText(for: student))
                            }
                        }
                    }
                    .sectionIndexLabel(section.letter)
                }
            }
            .listSectionIndexVisibility(.visible)
            .searchable(text: $searchText, prompt: "Schüler suchen")
            .overlay {
                if sections.isEmpty {
                    SearchEmptyStateView(text: searchText)
                }
            }
        }
    }

    /// „3 Notizen“ unter dem Namen.
    private static func noteCountText(for student: Student) -> String {
        StudentRecordFormat.count(student.noteCount)
    }
}

/// Fächer eines Schülers (= Fächer seiner Klasse) → Notizen je Fach.
struct StudentSubjectsView: View {
    let student: Student

    private var subjects: [String] { student.schoolClass?.subjects ?? [] }

    var body: some View {
        List {
            Section {
                StudentNameRow(student: student, size: 56)
            }
            Section("Fächer") {
                ForEach(subjects, id: \.self) { subject in
                    NavigationLink {
                        StudentRecordView(student: student, subject: subject)
                    } label: {
                        LabeledContent(SchoolClass.displayName(ofSubject: subject)) {
                            Text(StudentRecordFormat.count(student.observations(in: subject).count))
                        }
                    }
                }
            }
        }
        .overlay {
            if subjects.isEmpty {
                EmptyStateView(
                    title: loc("Keine Fächer"),
                    message: loc("Tragen Sie bei der Klasse die Fächer ein, die Sie dort unterrichten."),
                    symbol: AppTab.notes.symbol
                )
            }
        }
        .navigationTitle(AppTab.notes.title)
        .navigationBarTitleDisplayMode(.inline)
        .privacyModeToolbar()
    }
}

/// Foto/Initialen und voller Name, optional eine Zeile darunter (im Privatsphäre-Modus geschwärzt).
struct StudentNameRow: View {
    let student: Student
    var size: CGFloat = 40
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            StudentAvatar(student: student, size: size)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.fullName)
                    .font(size > 40 ? .title3.weight(.semibold) : .body.weight(.medium))
                    .sensitive()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .sensitive()
                }
            }
        }
    }
}

extension Student {
    /// Anzahl Beobachtungen über alle Fächer.
    var noteCount: Int { observations.count }
}

extension View {
    /// Privatsphäre-Modus rechts außen – für Unterseiten mit Schülerdaten (die Tab-Toolbar gilt dort nicht).
    func privacyModeToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PrivacyModeButton()
            }
        }
    }
}
