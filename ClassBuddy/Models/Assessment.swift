import Foundation
import SwiftData

// Leistungen (Etappe 2): Klassenarbeiten, Tests, Referate … je Klasse + Fach mit Note bzw. Punkten je Schüler,
// dazu die von der Lehrkraft selbst eingetragenen Quartals- und Halbjahresnoten. Die App rechnet keine Zeugnisnoten aus.

// MARK: - Bereiche und Leistungsarten

/// Beurteilungsbereich; die Namen unterscheiden sich je Bundesland und lassen sich umbenennen.
nonisolated enum AssessmentArea: String, Codable, CaseIterable, Identifiable {
    case written, other

    var id: String { rawValue }

    /// Vorgabe je Bundesland (ISO-Code wie „DE-NW“).
    func defaultName(federalState: String?) -> String {
        switch (self, federalState) {
        case (.written, "DE-BY"): loc("Große Leistungsnachweise")
        case (.other, "DE-BY"): loc("Kleine Leistungsnachweise")
        case (.written, "DE-NW"): loc("Schriftliche Arbeiten")
        case (.other, "DE-NW"): loc("Sonstige Mitarbeit")
        case (.other, "DE-BW"): loc("Mündlich-praktische Leistungen")
        case (.written, _): loc("Schriftliche Leistungen")
        case (.other, _): loc("Sonstige Leistungen")
        }
    }
}

/// Leistungsart (Klassenarbeit, Referat …): Name und Bereich, ausblendbar. Eigene Arten lassen sich hinzufügen.
nonisolated struct AssessmentType: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var area: AssessmentArea
    var isHidden = false

    static var defaults: [AssessmentType] {
        [
            AssessmentType(name: loc("Klassenarbeit"), area: .written),
            AssessmentType(name: loc("Klausur"), area: .written),
            AssessmentType(name: loc("Test"), area: .other),
            AssessmentType(name: loc("Referat"), area: .other),
            AssessmentType(name: loc("Poster"), area: .other),
            AssessmentType(name: loc("Vortrag"), area: .other),
            AssessmentType(name: loc("Heft"), area: .other),
        ]
    }
}

// MARK: - Noten

/// Eine Note im Notensystem der Klasse + Fach, als Text gespeichert („2−“ bzw. „13“).
nonisolated enum GradeScale {
    /// Auswahl je Notensystem, beste zuerst.
    static func values(for system: GradeSystem) -> [String] {
        switch system {
        case .grades:
            ["1+", "1", "1−", "2+", "2", "2−", "3+", "3", "3−", "4+", "4", "4−", "5+", "5", "5−", "6"]
        case .points:
            (0...15).reversed().map(String.init)
        case .none:
            []
        }
    }

    /// Ganze Note bzw. Punkte für den Notenspiegel.
    static func bucket(_ grade: String, system: GradeSystem) -> String? {
        let text = grade.trimmingCharacters(in: .whitespaces)
        switch system {
        case .grades: return text.first.map(String.init)
        case .points: return Int(text).map(String.init)
        case .none: return nil
        }
    }

    /// Notenspiegel: Anzahl je ganzer Note bzw. Punktzahl (in Reihenfolge der Skala).
    static func distribution(_ grades: [String], system: GradeSystem) -> [(label: String, amount: Int)] {
        let buckets: [String] = switch system {
        case .grades: ["1", "2", "3", "4", "5", "6"]
        case .points: (0...15).reversed().map(String.init)
        case .none: []
        }
        let counts = Dictionary(grouping: grades.compactMap { bucket($0, system: system) }, by: { $0 }).mapValues(\.count)
        return buckets.map { ($0, counts[$0] ?? 0) }
    }

    /// Durchschnitt einer Arbeit (dort üblich), auf eine Nachkommastelle gerundet.
    static func average(_ grades: [String], system: GradeSystem) -> Double? {
        let values: [Double] = switch system {
        case .grades: grades.compactMap { bucket($0, system: system) }.compactMap(Double.init)
        case .points: grades.compactMap { Int($0) }.map(Double.init)
        case .none: []
        }
        guard !values.isEmpty else { return nil }
        return (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10
    }
}

/// Notenschlüssel für Rohpunkte: Prozent der Höchstpunktzahl → Notenpunkte nach der Abitur-Tabelle
/// (95 % = 15 … 20 % = 1), daraus die Note mit Tendenz (15 = 1+, 14 = 1, 13 = 1− … 0 = 6).
nonisolated enum GradingKey {
    /// Untergrenzen in Prozent für 15 … 1 Punkte.
    static let thresholds: [Double] = [95, 90, 85, 80, 75, 70, 65, 60, 55, 50, 45, 40, 33, 27, 20]

    static func points(raw: Double, max: Double) -> Int? {
        guard max > 0, raw >= 0 else { return nil }
        // Mathematisch gerundet auf ganze Prozent (aufrunden ab ,5).
        let percent = (raw / max * 100).rounded(.toNearestOrAwayFromZero)
        guard let index = thresholds.firstIndex(where: { percent >= $0 }) else { return 0 }
        return 15 - index
    }

    static func grade(fromPoints points: Int) -> String {
        guard points > 0 else { return "6" }
        let base = 6 - (points + 2) / 3
        switch points % 3 {
        case 0: return "\(base)+"
        case 2: return "\(base)"
        default: return "\(base)−"
        }
    }

    static func grade(raw: Double, max: Double, system: GradeSystem) -> String? {
        guard let points = points(raw: raw, max: max) else { return nil }
        switch system {
        case .grades: return grade(fromPoints: points)
        case .points: return String(points)
        case .none: return nil
        }
    }
}

// MARK: - Leistungen

/// Eine Leistung einer Klasse in einem Fach (z. B. „Klassenarbeit 2“), mit Ergebnissen je Schüler.
@Model
final class Assessment {
    @Attribute(.unique) var id: UUID
    var subject: String
    var title: String
    /// Name der Leistungsart zum Zeitpunkt des Anlegens (bleibt erhalten, wenn die Art umbenannt wird).
    var typeName: String
    var areaRaw: String
    var date: Date
    /// Höchstpunktzahl, wenn mit Rohpunkten bewertet wird (sonst `nil`).
    var maxPoints: Double?
    var createdAt: Date
    var schoolClass: SchoolClass?

    @Relationship(deleteRule: .cascade, inverse: \AssessmentResult.assessment)
    var results: [AssessmentResult] = []

    init(
        id: UUID = UUID(), subject: String, title: String, typeName: String, area: AssessmentArea, date: Date = .now,
        maxPoints: Double? = nil, createdAt: Date = .now, schoolClass: SchoolClass?
    ) {
        self.id = id
        self.subject = subject
        self.title = title
        self.typeName = typeName
        self.areaRaw = area.rawValue
        self.date = date
        self.maxPoints = maxPoints
        self.createdAt = createdAt
        self.schoolClass = schoolClass
    }

    var area: AssessmentArea {
        get { AssessmentArea(rawValue: areaRaw) ?? .other }
        set { areaRaw = newValue.rawValue }
    }

    func result(for student: Student) -> AssessmentResult? {
        results.first { $0.student?.id == student.id }
    }

    /// Ergebnis anlegen bzw. holen.
    func ensureResult(for student: Student, in context: ModelContext) -> AssessmentResult {
        if let existing = result(for: student) { return existing }
        let result = AssessmentResult(assessment: self, student: student)
        context.insert(result)
        return result
    }

    /// Noten der Schüler, die noch in der Klasse sind (ohne „fehlt“).
    var grades: [String] {
        let ids = Set((schoolClass?.students ?? []).map(\.id))
        return results.filter { !$0.isMissing && !$0.grade.isEmpty && ids.contains($0.student?.id ?? UUID()) }.map(\.grade)
    }
}

/// Ergebnis eines Schülers: Note bzw. Punkte, optional Rohpunkte, oder „fehlt“ (nachschreiben).
@Model
final class AssessmentResult {
    @Attribute(.unique) var id: UUID
    var grade: String
    var rawPoints: Double?
    var isMissing: Bool
    var note: String
    var editedAt: Date?
    var previousGrade: String
    var assessment: Assessment?
    var student: Student?

    init(
        id: UUID = UUID(), grade: String = "", rawPoints: Double? = nil, isMissing: Bool = false,
        assessment: Assessment?, student: Student?
    ) {
        self.id = id
        self.grade = grade
        self.rawPoints = rawPoints
        self.isMissing = isMissing
        self.note = ""
        self.previousGrade = ""
        self.assessment = assessment
        self.student = student
    }

    /// Note setzen; eine bereits vergebene Note wird beim Ändern vermerkt.
    func setGrade(_ newGrade: String, at now: Date = .now) {
        guard newGrade != grade else { return }
        if !grade.isEmpty {
            if previousGrade.isEmpty { previousGrade = grade }
            editedAt = now
        }
        grade = newGrade
        if !newGrade.isEmpty { isMissing = false }
    }
}

// MARK: - Selbst eingetragene Noten

/// Abschnitt des Schuljahrs, für den die Lehrkraft eine Note einträgt.
nonisolated enum GradePeriod: String, Codable, CaseIterable, Identifiable {
    case quarter1, half1, quarter3, half2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quarter1: loc("1. Quartal")
        case .half1: loc("1. Halbjahr")
        case .quarter3: loc("3. Quartal")
        case .half2: loc("2. Halbjahr")
        }
    }
}

/// Wofür die Note gilt: einen Bereich oder das ganze Fach.
nonisolated enum GradeScope: String, Codable, CaseIterable, Identifiable {
    case written, other, total

    var id: String { rawValue }

    init(area: AssessmentArea) {
        self = area == .written ? .written : .other
    }
}

/// Von der Lehrkraft eingetragene Note (Quartal, Halbjahr) eines Schülers in einem Fach; änderbar mit Vermerk.
@Model
final class PeriodGrade {
    @Attribute(.unique) var id: UUID
    var subject: String
    var schoolYear: String
    var periodRaw: String
    var scopeRaw: String
    var grade: String
    var editedAt: Date?
    var previousGrade: String
    var student: Student?

    init(
        id: UUID = UUID(), subject: String, schoolYear: String, period: GradePeriod, scope: GradeScope, grade: String,
        student: Student?
    ) {
        self.id = id
        self.subject = subject
        self.schoolYear = schoolYear
        self.periodRaw = period.rawValue
        self.scopeRaw = scope.rawValue
        self.grade = grade
        self.previousGrade = ""
        self.student = student
    }

    var period: GradePeriod { GradePeriod(rawValue: periodRaw) ?? .half1 }
    var scope: GradeScope { GradeScope(rawValue: scopeRaw) ?? .total }
}

/// Welche selbst eingetragene Note: Fach, Schuljahr, Abschnitt, Bereich.
nonisolated struct PeriodGradeKey: Hashable {
    var subject: String
    var schoolYear: String
    var period: GradePeriod
    var scope: GradeScope = .total
}

extension Student {
    func periodGrade(_ key: PeriodGradeKey) -> PeriodGrade? {
        periodGrades.first {
            $0.subject == key.subject && $0.schoolYear == key.schoolYear && $0.periodRaw == key.period.rawValue
                && $0.scopeRaw == key.scope.rawValue
        }
    }

    /// Note setzen (leer = löschen); eine geänderte Note wird mit dem vorherigen Wert vermerkt.
    func setPeriodGrade(_ grade: String, for key: PeriodGradeKey, in context: ModelContext, at now: Date = .now) {
        if let existing = periodGrade(key) {
            guard !grade.isEmpty else { return context.delete(existing) }
            guard existing.grade != grade else { return }
            if existing.previousGrade.isEmpty { existing.previousGrade = existing.grade }
            existing.grade = grade
            existing.editedAt = now
        } else if !grade.isEmpty {
            context.insert(PeriodGrade(
                subject: key.subject, schoolYear: key.schoolYear, period: key.period, scope: key.scope, grade: grade, student: self
            ))
        }
    }

    /// Leistungen des Schülers in einem Fach (über die Klasse), neueste zuerst.
    func assessments(in subject: String) -> [Assessment] {
        (schoolClass?.assessments ?? []).filter { $0.subject == subject }.sorted { $0.date > $1.date }
    }

    /// War der Schüler am Tag der Leistung (in irgendeiner Stunde) abwesend?
    func wasAbsent(on date: Date) -> Bool {
        absences.contains { $0.kind == .absent && Calendar.school.isDate($0.day, inSameDayAs: date) }
    }
}
