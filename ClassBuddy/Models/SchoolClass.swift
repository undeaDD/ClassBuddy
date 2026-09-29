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
    /// Zusatzzeile, z. B. Fach oder Rolle („Mathematik“, „Klassenleitung“).
    var subtitle: String
    /// Schuljahr, z. B. „2026/27“.
    var schoolYear: String
    var colorRaw: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        shortName: String,
        subtitle: String = "",
        schoolYear: String = SchoolClass.currentSchoolYear,
        color: ClassColor = .blue,
        createdAt: Date = .now
    ) {
        self.id = id
        self.shortName = shortName
        self.subtitle = subtitle
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
        [subtitle, schoolYear].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static var currentSchoolYear: String {
        let calendar = Calendar.current
        let now = Date.now
        let year = calendar.component(.year, from: now)
        // Schuljahr beginnt (grob) im August.
        let start = calendar.component(.month, from: now) >= 8 ? year : year - 1
        return "\(start)/\(String(start + 1).suffix(2))"
    }
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
        var subtitle: String
        var schoolYear: String
        var color: String
        var createdAt: Date
    }

    var snapshot: Snapshot {
        Snapshot(
            id: id,
            shortName: shortName,
            subtitle: subtitle,
            schoolYear: schoolYear,
            color: colorRaw,
            createdAt: createdAt
        )
    }
}
