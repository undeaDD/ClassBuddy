import SwiftUI

/// Alle Ziele der App. Reihenfolge der Cases = Standardreihenfolge in Sidebar/Tab-Bar.
enum AppTab: String, CaseIterable, Identifiable, Hashable, Codable {
    case dashboard
    case calendar
    case students
    case rooms
    /// Kein echter Tab: öffnet eine Feedback-Mail, die Auswahl bleibt unverändert.
    case feedback
    case settings

    var id: String { rawValue }

    /// Stabile ID für die (persistierte) Tab-Anpassung – nie ändern.
    var customizationID: String { "tab.\(rawValue)" }

    var title: String {
        switch self {
        case .dashboard: "Übersicht"
        case .calendar: "Kalender"
        case .students: "Schüler"
        case .rooms: "Räume"
        case .settings: "Einstellungen"
        case .feedback: "Feedback"
        }
    }

    var symbol: AppSymbol {
        switch self {
        case .dashboard: .custom(.homeAlt)
        case .calendar: .custom(.calendar)
        case .students: .custom(.community)
        case .rooms: .custom(.floorLayout)
        case .settings: .custom(.settings)
        case .feedback: .custom(.sendMail)
        }
    }

    /// Tabs, die nur eine Aktion auslösen und nie ausgewählt werden.
    var isAction: Bool { self == .feedback }

    /// Gruppe in der Sidebar.
    var section: AppTabSection {
        switch self {
        case .dashboard, .calendar, .rooms: .general
        case .students: .schoolClass
        case .feedback, .settings: .other
        }
    }

    /// Nur diese Tabs erscheinen in der oberen, zentrierten Tab-Leiste.
    var isInTabBar: Bool { self == .dashboard || self == .calendar }
}

/// Einklappbare Gruppen in der Sidebar.
enum AppTabSection: String, CaseIterable, Identifiable {
    case general
    case schoolClass
    case other

    var id: String { rawValue }

    /// Stabile ID für die (persistierte) Tab-Anpassung – nie ändern.
    var customizationID: String { "section.\(rawValue)" }

    var title: String {
        switch self {
        case .general: "Allgemein"
        case .schoolClass: "Klasse"
        case .other: "Sonstige"
        }
    }

    /// Tabs der Gruppe in Standardreihenfolge (= Reihenfolge der `AppTab`-Cases).
    var tabs: [AppTab] { AppTab.allCases.filter { $0.section == self } }
}
