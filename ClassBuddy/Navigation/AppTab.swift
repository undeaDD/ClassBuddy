import SwiftUI

/// Alle Ziele der App. Reihenfolge der Cases = Standardreihenfolge in Sidebar/Tab-Bar.
enum AppTab: String, CaseIterable, Identifiable, Hashable, Codable {
    case dashboard
    case students
    case seating
    case settings

    var id: String { rawValue }

    /// Stabile ID für die (persistierte) Tab-Anpassung – nie ändern.
    var customizationID: String { "tab.\(rawValue)" }

    var title: String {
        switch self {
        case .dashboard: "Übersicht"
        case .students: "Schüler"
        case .seating: "Sitzplan"
        case .settings: "Einstellungen"
        }
    }

    var symbol: AppSymbol {
        switch self {
        case .dashboard: .system("square.grid.2x2")
        case .students: .system("person.3")
        case .seating: .system("table.furniture")
        case .settings: .system("gearshape")
        }
    }

    var summary: String {
        switch self {
        case .dashboard: "Dein Tag auf einen Blick."
        case .students: "Schülerinnen und Schüler der Klasse."
        case .seating: "Sitzplatzverwaltung: Sitzordnungen planen, speichern und wechseln."
        case .settings: "App-Sperre und Privatsphäre."
        }
    }
}
