import Foundation
import SwiftData
import SwiftUI

/// Eine Klasse / ein Kurs. Lokal per SwiftData gespeichert.
/// Für den späteren JSON-Export gibt es `SchoolClass.Snapshot` (Codable).
@Model
final class SchoolClass {
    @Attribute(.unique) var id: UUID
    /// Kurzbezeichnung im Kreis, z. B. „7b“ oder „Q1“.
    var shortName: String
    /// Fächer, die du in dieser Klasse unterrichtest (Reihenfolge = Anzeige).
    var subjects: [String] = []
    /// Schuljahr, z. B. „2026/27“.
    var schoolYear: String
    var colorRaw: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Student.schoolClass)
    var students: [Student] = []

    @Relationship(deleteRule: .cascade, inverse: \Lesson.schoolClass)
    var lessons: [Lesson] = []

    @Relationship(deleteRule: .cascade, inverse: \DashboardLink.schoolClass)
    var dashboardLinks: [DashboardLink] = []

    /// Reihenfolge der Übersichts-Kacheln (Kachel-IDs, siehe `DashboardView`).
    var dashboardOrder: [String] = []

    init(
        id: UUID = UUID(),
        shortName: String,
        subjects: [String] = [],
        schoolYear: String = SchoolClass.currentSchoolYear,
        color: ClassColor = .blue,
        createdAt: Date = .now
    ) {
        self.id = id
        self.shortName = shortName
        self.subjects = subjects
        self.schoolYear = schoolYear
        self.colorRaw = color.rawValue
        self.createdAt = createdAt
    }

    var color: ClassColor {
        get { ClassColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    var title: String { "Klasse \(shortName)" }

    var detailLine: String {
        [subjects.joined(separator: ", "), schoolYear].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var sortedStudents: [Student] {
        students.sorted(using: [KeyPathComparator(\.lastName), KeyPathComparator(\.firstName)])
    }

    static var currentSchoolYear: String {
        let calendar = Calendar.current
        let now = Date.now
        let year = calendar.component(.year, from: now)
        // Schuljahr beginnt (grob) im August.
        let start = calendar.component(.month, from: now) >= 8 ? year : year - 1
        return "\(start)/\(String(start + 1).suffix(2))"
    }

    /// Vorschläge im Klassen-Editor; eigene Fächer sind jederzeit möglich.
    static let suggestedSubjects = [
        "Deutsch", "Mathematik", "Englisch", "Französisch", "Latein", "Spanisch",
        "Biologie", "Chemie", "Physik", "Informatik",
        "Geschichte", "Erdkunde", "Politik", "Wirtschaft",
        "Religion", "Ethik", "Philosophie", "Kunst", "Musik", "Sport",
    ]
}

enum ClassColor: String, CaseIterable, Codable, Identifiable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        }
    }
}

// MARK: - Export

extension SchoolClass {
    /// Stabile, versionierbare Export-Repräsentation (JSON).
    struct Snapshot: Codable, Hashable {
        var id: UUID
        var shortName: String
        var subjects: [String]
        var schoolYear: String
        var color: String
        var createdAt: Date
        var students: [Student.Snapshot]
    }

    var snapshot: Snapshot {
        Snapshot(
            id: id,
            shortName: shortName,
            subjects: subjects,
            schoolYear: schoolYear,
            color: colorRaw,
            createdAt: createdAt,
            students: sortedStudents.map(\.snapshot)
        )
    }
}
