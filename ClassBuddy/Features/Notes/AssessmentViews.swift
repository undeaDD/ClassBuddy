import Charts
import SwiftData
import SwiftUI

/// Leistungen einer Klasse, nach Fach gruppiert (neueste zuerst): Titel, Art, Datum, Durchschnitt, eingetragene Noten.
struct AssessmentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var schoolSettings
    let schoolClass: SchoolClass
    @Binding var editorRoute: AssessmentEditorRoute?

    @State private var pendingDeletion: Assessment?

    var body: some View {
        let subjects = schoolClass.subjects.filter { subject in schoolClass.assessments.contains { $0.subject == subject } }
        List {
            ForEach(subjects, id: \.self) { subject in
                Section(SchoolClass.displayName(ofSubject: subject)) {
                    ForEach(schoolClass.assessments.filter { $0.subject == subject }.sorted { $0.date > $1.date }) { assessment in
                        NavigationLink {
                            AssessmentDetailView(assessment: assessment)
                                .hidesTabBar()
                        } label: {
                            AssessmentRow(assessment: assessment, system: system(for: subject))
                        }
                        .swipeActions {
                            if !security.isPrivacyModeOn {
                                Button("Löschen", icon: .trash, role: .destructive) { pendingDeletion = assessment }
                                    .tint(.red)
                                Button("Bearbeiten", icon: .editPencil) { editorRoute = .edit(assessment) }
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if subjects.isEmpty {
                EmptyStateView(
                    title: loc("Noch keine Leistungen"),
                    message: loc("Legen Sie über + oben rechts eine Klassenarbeit, einen Test oder ein Referat an."),
                    symbol: AppTab.notes.symbol
                )
            }
        }
        .confirmationDialog(
            "Leistung löschen?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { assessment in
            Button("Löschen", role: .destructive) {
                modelContext.delete(assessment)
                try? modelContext.save()
            }
        } message: { _ in
            Text("Alle Noten dieser Leistung werden entfernt. Das kann nicht rückgängig gemacht werden.")
        }
    }

    private func system(for subject: String) -> GradeSystem {
        schoolClass.recordSettings(for: subject, schoolType: schoolSettings.values.schoolType).gradeSystem
    }
}

/// Zeile einer Leistung: Titel, Art · Datum; rechts Durchschnitt und eingetragene Noten.
private struct AssessmentRow: View {
    let assessment: Assessment
    let system: GradeSystem

    var body: some View {
        let grades = assessment.grades
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(assessment.title).font(.body.weight(.medium))
                Text("\(assessment.typeName) · \(assessment.date.appDate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(GradeScale.average(grades, system: system).map { loc("Ø \($0.formatted(.number.precision(.fractionLength(1))))") } ?? "–")
                    .font(.subheadline.weight(.semibold))
                    .sensitive()
                Text(loc("\(grades.count) von \(assessment.schoolClass?.students.count ?? 0)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Eine Leistung: Notenspiegel und Durchschnitt, darunter alle Schüler mit Note (bzw. Rohpunkten) oder „fehlt“.
struct AssessmentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var schoolSettings
    let assessment: Assessment

    @State private var editorRoute: AssessmentEditorRoute?

    private var system: GradeSystem {
        assessment.schoolClass?.recordSettings(for: assessment.subject, schoolType: schoolSettings.values.schoolType).gradeSystem ?? .grades
    }

    private var students: [Student] { assessment.schoolClass?.sortedStudents ?? [] }
    private var canEdit: Bool { !security.isPrivacyModeOn }

    var body: some View {
        List {
            Section {
                summary
            }
            Section {
                ForEach(students) { student in
                    studentRow(student)
                }
            } footer: {
                Text("Nach links wischen: „fehlt“ (nachschreiben) bzw. Note entfernen.")
            }
        }
        .navigationTitle(assessment.title)
        .appNavigationSubtitle("\(assessment.typeName) · \(schoolSettings.values.areaName(assessment.area))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Bearbeiten", icon: .editPencil) { editorRoute = .edit(assessment) }
                    .disabled(!canEdit)
                    .toolbarGroupBackground()
            }
            AppToolbarSpacer(placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                PrivacyModeButton()
                    .toolbarGroupBackground()
            }
        }
        .sheet(item: $editorRoute) { AssessmentEditorView(route: $0) }
    }

    private var summary: some View {
        let grades = assessment.grades
        let missing = assessment.results.filter(\.isMissing).count
        let distribution = GradeScale.distribution(grades, system: system)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                let average = GradeScale.average(grades, system: system)
                summaryValue(loc("Durchschnitt"), average.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–")
                summaryValue(loc("Eingetragen"), "\(grades.count)/\(students.count)")
                summaryValue(loc("Fehlt"), "\(missing)")
            }
            if !grades.isEmpty {
                Chart(distribution, id: \.label) { item in
                    BarMark(x: .value("Note", item.label), y: .value("Anzahl", item.amount), width: .ratio(0.6))
                        .cornerRadius(4)
                        .foregroundStyle(.tint)
                        .annotation(position: .top) {
                            if item.amount != 0 { Text("\(item.amount)").font(.caption2).foregroundStyle(.secondary) }
                        }
                }
                .chartYAxis(.hidden)
                .frame(height: 120)
                .sensitiveBlur()
            }
            Text(assessment.date.appDate
                + (assessment.maxPoints.map { " · " + loc("Höchstpunktzahl \($0.formatted())") } ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func summaryValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold)).monospacedDigit().sensitive()
        }
    }

    @ViewBuilder
    private func studentRow(_ student: Student) -> some View {
        let result = assessment.result(for: student)
        HStack(spacing: 12) {
            StudentAvatar(student: student, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.fullName).sensitive()
                if result?.isMissing == true {
                    Text("Fehlt – nachschreiben").font(.caption).foregroundStyle(.orange)
                } else if result?.grade.isEmpty ?? true, student.wasAbsent(on: assessment.date) {
                    Text("War an dem Tag abwesend").font(.caption).foregroundStyle(.orange)
                } else if let result, let edited = result.editedAt {
                    Text(loc("Geändert am \(edited.appDate) (vorher \(result.previousGrade))"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if let maxPoints = assessment.maxPoints {
                PointsField(points: result?.rawPoints, maxPoints: maxPoints) { setPoints($0, for: student) }
                    .disabled(!canEdit)
            }
            GradeMenu(grade: result?.grade ?? "", system: system) { setGrade($0, for: student) }
                .disabled(!canEdit)
        }
        .swipeActions {
            if canEdit {
                Button(result?.isMissing == true ? "Fehlt aufheben" : "Fehlt", icon: .userXmark) { toggleMissing(student) }
                    .tint(.orange)
                Button("Note entfernen", icon: .trash, role: .destructive) { setGrade("", for: student) }
                    .tint(.red)
            }
        }
    }

    // MARK: Ändern

    private func setGrade(_ grade: String, for student: Student) {
        assessment.ensureResult(for: student, in: modelContext).setGrade(grade)
        try? modelContext.save()
    }

    /// Rohpunkte speichern und die Note nach dem Notenschlüssel vorschlagen.
    private func setPoints(_ points: Double?, for student: Student) {
        let result = assessment.ensureResult(for: student, in: modelContext)
        result.rawPoints = points
        if let points, let maxPoints = assessment.maxPoints, let grade = GradingKey.grade(raw: points, max: maxPoints, system: system) {
            result.setGrade(grade)
        }
        try? modelContext.save()
    }

    private func toggleMissing(_ student: Student) {
        let result = assessment.ensureResult(for: student, in: modelContext)
        result.isMissing.toggle()
        if result.isMissing { result.grade = "" }
        try? modelContext.save()
    }
}

/// Rohpunkte eines Schülers (Eingabe übernimmt beim Bestätigen bzw. Verlassen des Felds).
private struct PointsField: View {
    let points: Double?
    let maxPoints: Double
    let onCommit: (Double?) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("Pkt.", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
            Text("/ \(maxPoints.formatted())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
            .focused($isFocused)
            .sensitive()
            .onAppear { text = points.map { $0.formatted() } ?? "" }
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onSubmit(commit)
            .accessibilityLabel(loc("Punkte von \(maxPoints.formatted())"))
    }

    private func commit() {
        let value = Double(text.replacingOccurrences(of: ",", with: ".")).map { min(max($0, 0), maxPoints) }
        guard value != points else { return }
        onCommit(value)
    }
}

// MARK: - Akte: Leistungen eines Schülers

/// Abschnitte „Leistungen“ in der Schülerakte: alle Leistungen des Fachs mit Note, dazu die selbst eingetragenen Noten.
struct StudentAssessmentSections: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var schoolSettings
    let student: Student
    let subject: String
    let system: GradeSystem

    private var schoolYear: String { student.schoolClass?.schoolYear ?? "" }

    var body: some View {
        let assessments = student.assessments(in: subject)
        ForEach(AssessmentArea.allCases) { area in
            let items = assessments.filter { $0.area == area }
            if !items.isEmpty {
                Section(schoolSettings.values.areaName(area)) {
                    ForEach(items) { assessment in
                        NavigationLink {
                            AssessmentDetailView(assessment: assessment)
                                .hidesTabBar()
                        } label: {
                            row(assessment)
                        }
                    }
                }
            }
        }
        if assessments.isEmpty {
            Section {
                Text("Noch keine Leistungen in diesem Fach. Anlegen im Tab „Bewertungen“ unter „Leistungen“.")
                    .foregroundStyle(.secondary)
            }
        }
        if system != .none {
            Section {
                ForEach(GradePeriod.allCases) { period in
                    periodRow(period)
                }
            } header: {
                Text(loc("Noten \(schoolYear)"))
            }
        }
    }

    private func row(_ assessment: Assessment) -> some View {
        let result = assessment.result(for: student)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(assessment.title)
                Text("\(assessment.typeName) · \(assessment.date.appDate)"
                    + (result?.rawPoints.map { " · " + loc("\($0.formatted()) von \((assessment.maxPoints ?? 0).formatted()) Punkten") } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(result?.isMissing == true ? loc("fehlt") : (result?.grade.isEmpty == false ? result?.grade ?? "–" : "–"))
                .font(result?.isMissing == true ? .subheadline : .title3.weight(.bold))
                .foregroundStyle(result?.isMissing == true ? Color.orange : Color.primary)
                .sensitive()
        }
    }

    private func periodRow(_ period: GradePeriod) -> some View {
        let key = PeriodGradeKey(subject: subject, schoolYear: schoolYear, period: period)
        let existing = student.periodGrade(key)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(period.title)
                if let existing, let edited = existing.editedAt {
                    Text(loc("Geändert am \(edited.appDate) (vorher \(existing.previousGrade))"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            GradeMenu(grade: existing?.grade ?? "", system: system, placeholder: loc("eintragen")) { grade in
                student.setPeriodGrade(grade, for: key, in: modelContext)
                try? modelContext.save()
            }
            .disabled(security.isPrivacyModeOn)
        }
    }
}
