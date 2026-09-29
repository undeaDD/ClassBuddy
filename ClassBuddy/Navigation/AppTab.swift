import SwiftUI

/// Alle Ziele der App. Reihenfolge der Cases = Standardreihenfolge in Sidebar/Tab-Bar.
enum AppTab: String, CaseIterable, Identifiable, Hashable, Codable {
    case dashboard
    case calendar
    case students
    case settings

    var id: String { rawValue }

    /// Stabile ID für die (persistierte) Tab-Anpassung – nie ändern.
    var customizationID: String { "tab.\(rawValue)" }

    var title: String {
        switch self {
        case .dashboard: "Übersicht"
        case .calendar: "Kalender"
        case .students: "Schüler"
        case .settings: "Einstellungen"
        }
    }

    var symbol: AppSymbol {
        switch self {
        case .dashboard: .system("square.grid.2x2")
        case .calendar: .system("calendar")
        case .students: .system("person.3")
        case .settings: .system("gearshape")
        }
    }

    /// Standardmäßig in der oberen Tab-Bar; alle anderen nur in der Sidebar
    /// (lassen sich dort per Drag & Drop in die Tab-Bar ziehen).
    var isInTabBarByDefault: Bool {
        switch self {
        case .dashboard, .calendar: true
        case .students, .settings: false
        }
    }
}
