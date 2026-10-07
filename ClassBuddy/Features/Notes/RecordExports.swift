import SwiftUI

// Notenübersicht als Tabellenmodell (für Ansicht, PDF und Excel) und die PDF-Exporte der Schülerakte.

/// Tabelle Schüler × Spalten einer Klasse in einem Fach. Die App rechnet nichts aus, sie zeigt nur Eingetragenes.
struct GradeOverviewTable {
    enum Group: String, CaseIterable, Identifiable {
        case observations, assessments, absences, grades
        var id: String { rawValue }

        var title: String {
            switch self {
            case .observations: loc("Beobachtungen")
            case .assessments: loc("Leistungen")
            case .absences: loc("Fehlzeiten")
            case .grades: loc("Noten")
            }
        }
    }

    enum Kind {
        case observationCount, observationRecent, assessment(Assessment), absences, period(GradePeriod)
    }

    struct Column: Identifiable {
        let id: String
        let title: String
        var subtitle = ""
        let group: Group
        let kind: Kind
    }

    let schoolClass: SchoolClass
    let subject: String
    let students: [Student]
    let columns: [Column]

    init(schoolClass: SchoolClass, subject: String, groups: Set<Group> = Set(Group.allCases), students: [Student]? = nil) {
        self.schoolClass = schoolClass
        self.subject = subject
        self.students = students ?? schoolClass.sortedStudents
        var columns: [Column] = []
        if groups.contains(.observations) {
            columns.append(Column(
                id: "obs.count", title: loc("Anzahl"), subtitle: loc("Beobachtungen"), group: .observations, kind: .observationCount
            ))
            columns.append(Column(
                id: "obs.recent", title: loc("Zuletzt"), subtitle: loc("neueste zuerst"), group: .observations, kind: .observationRecent
            ))
        }
        if groups.contains(.assessments) {
            for assessment in schoolClass.assessments.filter({ $0.subject == subject }).sorted(by: { $0.date < $1.date }) {
                columns.append(Column(
                    id: "assessment.\(assessment.id)", title: assessment.title,
                    subtitle: assessment.date.appDate,
                    group: .assessments, kind: .assessment(assessment)
                ))
            }
        }
        if groups.contains(.absences) {
            columns.append(Column(id: "absences", title: loc("Fehlst."), subtitle: loc("abw. / versp."), group: .absences, kind: .absences))
        }
        if groups.contains(.grades) {
            for period in GradePeriod.allCases {
                columns.append(Column(id: "period.\(period.rawValue)", title: period.title, group: .grades, kind: .period(period)))
            }
        }
        self.columns = columns
    }

    func text(_ student: Student, _ column: Column) -> String {
        switch column.kind {
        case .observationCount:
            return "\(student.observations(in: subject).count)"
        case .observationRecent:
            return student.observations(in: subject).filter { $0.kind == .rating }.prefix(5).map(\.label).joined(separator: " · ")
        case .assessment(let assessment):
            guard let result = assessment.result(for: student) else { return "" }
            return result.isMissing ? loc("fehlt") : result.grade
        case .absences:
            let absences = student.absences.filter { $0.subject == subject }
            let absent = absences.filter { $0.kind == .absent }.count
            return "\(absent) / \(absences.count - absent)"
        case .period(let period):
            let key = PeriodGradeKey(subject: subject, schoolYear: schoolClass.schoolYear, period: period)
            return student.periodGrade(key)?.grade ?? ""
        }
    }

    var header: [String] {
        [loc("Schüler")] + columns.map { $0.subtitle.isEmpty ? $0.title : "\($0.title) (\($0.subtitle))" }
    }

    var rows: [[String]] {
        students.map { student in [student.fullName] + columns.map { text(student, $0) } }
    }

    var title: String { "\(schoolClass.title) · \(SchoolClass.displayName(ofSubject: subject))" }

    /// Excel-Datei mit einem Blatt.
    func excelFile() -> URL? {
        let data = XLSX.write([XLSXSheet(name: loc("Übersicht"), rows: [header] + rows)])
        let url = URL.temporaryDirectory.appending(path: loc("Notenübersicht \(Self.fileName(title)).xlsx"))
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    func pdfFile() -> URL? {
        TablePDF.make(
            title: loc("Notenübersicht"), subtitle: title, header: header, rows: rows,
            fileName: loc("Notenübersicht \(Self.fileName(title)).pdf")
        )
    }

    /// Mitarbeitsliste wie auf Papier: Schüler × Tage mit Bewertungen, Zellen mit den Werten des Tages.
    func participationPDF() -> URL? {
        let calendar = Calendar.school
        let ratings = students.flatMap { $0.observations(in: subject) }.filter { $0.kind == .rating }
        let days = Set(ratings.map { calendar.startOfDay(for: $0.date) }).sorted()
        let header = [loc("Schüler")] + days.map(\.appDate)
        let rows = students.map { student in
            [student.fullName] + days.map { day in
                student.observations(in: subject)
                    .filter { $0.kind == .rating && calendar.isDate($0.date, inSameDayAs: day) }
                    .sorted { $0.date < $1.date }
                    .map(\.label)
                    .joined(separator: " ")
            }
        }
        return TablePDF.make(
            title: loc("Mitarbeitsliste"), subtitle: title, header: header, rows: rows, maxColumns: 16,
            fileName: loc("Mitarbeitsliste \(Self.fileName(title)).pdf")
        )
    }

    static func fileName(_ text: String) -> String {
        text.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " · ", with: " ")
    }
}

/// Tabelle als PDF (A4 quer, hell, mit Fußzeile): viele Zeilen → mehrere Seiten, viele Spalten → weitere Seiten
/// mit wiederholter Namensspalte.
enum TablePDF {
    static func make(
        title: String, subtitle: String, header: [String], rows: [[String]], maxColumns: Int = 12, fileName: String
    ) -> URL? {
        let page = CGSize(width: 842, height: 595)
        let rowsPerPage = 22
        let valueColumns = max(header.count - 1, 0)
        let columnChunks = stride(from: 0, to: max(valueColumns, 1), by: maxColumns).map { start in
            Array(start..<min(start + maxColumns, valueColumns))
        }
        let rowChunks = stride(from: 0, to: max(rows.count, 1), by: rowsPerPage).map {
            Array(rows[min($0, rows.count)..<min($0 + rowsPerPage, rows.count)])
        }

        let url = URL.temporaryDirectory.appending(path: fileName)
        var box = CGRect(origin: .zero, size: page)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for columns in columnChunks {
            for chunk in rowChunks {
                let content = VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.title2.bold())
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                        GridRow {
                            Text(header.first ?? "").fontWeight(.semibold)
                            ForEach(columns, id: \.self) { index in
                                Text(header[index + 1]).fontWeight(.semibold).lineLimit(2)
                            }
                        }
                        Divider()
                        ForEach(Array(chunk.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                Text(row.first ?? "").lineLimit(1)
                                ForEach(columns, id: \.self) { index in
                                    Text(index + 1 < row.count ? row[index + 1] : "").lineLimit(1).minimumScaleFactor(0.6)
                                }
                            }
                            Divider()
                        }
                    }
                    .font(.system(size: columns.count > 10 ? 8 : 10))
                    Spacer(minLength: 0)
                    SeatingPlanPDF.footer
                }
                .padding(32)
                .frame(width: page.width, height: page.height, alignment: .topLeading)
                .background(.white)
                .environment(\.colorScheme, .light)

                ImageRenderer(content: content).render { _, draw in
                    pdf.beginPDFPage(nil)
                    draw(pdf)
                    pdf.endPDFPage()
                }
            }
        }
        pdf.closePDF()
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }
}

/// Zusammenfassung eines Schülers in einem Fach für Elterngespräche (A4 hoch).
enum StudentRecordPDF {
    static func make(student: Student, subject: String) -> URL? {
        let page = CGSize(width: 595, height: 842)
        let content = StudentRecordPDFPage(student: student, subject: subject)
            .frame(width: page.width, height: page.height, alignment: .topLeading)
            .background(.white)
            .environment(\.colorScheme, .light)
        let url = URL.temporaryDirectory.appending(path: loc("Schülerakte \(GradeOverviewTable.fileName(student.fullName)).pdf"))
        let renderer = ImageRenderer(content: content)
        var box = CGRect(origin: .zero, size: page)
        renderer.render { _, draw in
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }
}

/// Inhalt des Schüler-PDFs: Beobachtungen, Leistungen, Fehlzeiten, selbst eingetragene Noten.
private struct StudentRecordPDFPage: View {
    let student: Student
    let subject: String

    var body: some View {
        let observations = student.observations(in: subject)
        let ratings = observations.filter { $0.kind == .rating }
        let absences = student.absences.filter { $0.subject == subject }
        let absent = absences.filter { $0.kind == .absent }.count
        VStack(alignment: .leading, spacing: 14) {
            Text(student.fullName).font(.title.bold())
            Text([student.schoolClass?.title, SchoolClass.displayName(ofSubject: subject), schoolYear]
                .compactMap { $0 }
                .joined(separator: " · "))
                .font(.title3)
                .foregroundStyle(.secondary)
            section(loc("Beobachtungen")) {
                Text(loc("\(observations.count) Einträge · Bewertungen: \(ratings.prefix(12).map(\.label).joined(separator: " · "))"))
                ForEach(observations.filter { !$0.note.isEmpty }.prefix(8)) { observation in
                    Text("\(observation.date.appDate): \(observation.note)")
                }
            }
            section(loc("Leistungen")) {
                assessments
            }
            section(loc("Fehlzeiten")) {
                Text(loc("\(absent) Stunden abwesend · \(absences.count - absent)× verspätet"))
            }
            if !periods.isEmpty {
                section(loc("Noten")) {
                    ForEach(periods, id: \.0) { period in
                        HStack {
                            Text(period.0)
                            Spacer()
                            Text(period.1).fontWeight(.semibold)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Text(loc("Erstellt am \(Date.now.appDate)")).font(.caption).foregroundStyle(.secondary)
            SeatingPlanPDF.footer
        }
        .font(.system(size: 11))
        .padding(40)
    }

    private var schoolYear: String { student.schoolClass?.schoolYear ?? "" }

    private var periods: [(String, String)] {
        GradePeriod.allCases.compactMap { period in
            student.periodGrade(PeriodGradeKey(subject: subject, schoolYear: schoolYear, period: period)).map { (period.title, $0.grade) }
        }
    }

    @ViewBuilder
    private var assessments: some View {
        let items = student.assessments(in: subject)
        if items.isEmpty { Text("–") }
        ForEach(items) { assessment in
            let result = assessment.result(for: student)
            HStack {
                Text("\(assessment.title) (\(assessment.typeName), \(assessment.date.appDate))")
                Spacer()
                Text(result?.isMissing == true ? loc("fehlt") : (result?.grade ?? "–")).fontWeight(.semibold)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            content()
        }
    }
}
