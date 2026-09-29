import SwiftUI

/// Alle Ziele der App. Reihenfolge der Cases = Standardreihenfolge in Sidebar/Tab-Bar.
enum AppTab: String, CaseIterable, Identifiable, Hashable, Codable {
    case dashboard
    case seating

    var id: String { rawValue }

    /// Stabile ID für die (persistierte) Tab-Anpassung – nie ändern.
    var customizationID: String { "tab.\(rawValue)" }

    var title: String {
        switch self {
        case .dashboard: "Übersicht"
        case .seating: "Sitzplan"
        }
    }

    var symbol: AppSymbol {
        switch self {
        case .dashboard: .system("square.grid.2x2")
        case .seating: .system("table.furniture")
        }
    }

    var summary: String {
        switch self {
        case .dashboard: "Dein Tag auf einen Blick."
        case .seating: "Sitzplatzverwaltung: Sitzordnungen planen, speichern und wechseln."
        }
    }
}
