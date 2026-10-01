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

    /// Termine der Klasse; beim Löschen der Klasse bleiben sie ohne Klasse erhalten.
    @Relationship(deleteRule: .nullify, inverse: \CalendarEntry.schoolClass)
    var calendarEntries: [CalendarEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \DashboardLink.schoolClass)
    var dashboardLinks: [DashboardLink] = []

    /// Reihenfolge der Übersichts-Kacheln (Kachel-IDs, siehe `DashboardView`).
    var dashboardOrder: [String] = []
    /// Ausgeblendete Übersichts-Kacheln (nur im Anordnen-Modus sichtbar).
    var dashboardHidden: [String] = []
    /// Kacheln, die diese Klasse schon kennt – neue, standardmäßig ausgeblendete
    /// Kacheln werden beim ersten Auftauchen in `dashboardHidden` eingetragen.
    var dashboardKnownCards: [String] = []
    /// Entfernte eingebaute Kacheln (weder sichtbar noch unter „Ausgeblendet“, über die Galerie wieder hinzufügbar).
    var dashboardRemoved: [String] = []

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

    /// Vordefinierte Farbe (bei eigener Farbe: Blau als Rückfall).
    var color: ClassColor {
        get { ClassColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    /// Angezeigte Farbe: vordefiniert oder eigene Farbe (`colorRaw` = „#RRGGBB“).
    var displayColor: Color {
        Self.displayColor(for: colorRaw)
    }

    /// `colorRaw` → Farbe (Name einer `ClassColor` oder Hex-Wert).
    static func displayColor(for colorRaw: String) -> Color {
        ClassColor(rawValue: colorRaw)?.color ?? Color(hex: colorRaw) ?? ClassColor.blue.color
    }

    /// Gültiger Farbwert für den Import: vordefinierter Name oder `#RRGGBB`, sonst Blau.
    static func sanitizedColorRaw(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if ClassColor(rawValue: trimmed) != nil { return trimmed }
        if let custom = Color(hex: trimmed) { return custom.hexString }
        return ClassColor.blue.rawValue
    }

    var title: String { loc("Klasse \(shortName)") }

    /// Kürzel für den runden Klassen-Button in der Toolbar: höchstens 3 Zeichen.
    var buttonName: String { String(shortName.prefix(3)) }

    var detailLine: String {
        [subjects.map(Self.displayName(ofSubject:)).joined(separator: ", "), schoolYear].filter { !$0.isEmpty }.joined(separator: " · ")
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

    /// Fächer werden auf Deutsch gespeichert; vorgeschlagene Fächer erscheinen in der App-Sprache,
    /// eigene Fächer so, wie sie eingegeben wurden.
    static func displayName(ofSubject subject: String) -> String {
        subjectNames[subject].map(loc) ?? subject
    }

    private static let subjectNames: [String: LocalizedStringResource] = [
        "Deutsch": "Deutsch",
        "Mathematik": "Mathematik",
        "Englisch": "Englisch",
        "Französisch": "Französisch",
        "Latein": "Latein",
        "Spanisch": "Spanisch",
        "Biologie": "Biologie",
        "Chemie": "Chemie",
        "Physik": "Physik",
        "Informatik": "Informatik",
        "Geschichte": "Geschichte",
        "Erdkunde": "Erdkunde",
        "Politik": "Politik",
        "Wirtschaft": "Wirtschaft",
        "Religion": "Religion",
        "Ethik": "Ethik",
        "Philosophie": "Philosophie",
        "Kunst": "Kunst",
        "Musik": "Musik",
        "Sport": "Sport",
    ]
}

nonisolated enum ClassColor: String, CaseIterable, Codable, Identifiable {
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
