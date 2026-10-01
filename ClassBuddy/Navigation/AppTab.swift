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
        case .dashboard: loc("Übersicht")
        case .calendar: "Kalender"
        case .students: loc("Schüler")
        case .rooms: loc("Räume")
        case .settings: loc("Einstellungen")
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

    /// Seite hängt von der ausgewählten Klasse ab → Klassen-Button oben links in der Toolbar.
    /// Neue Seiten ohne Klassenbezug (Einstellungen, Hilfe …) hier ausnehmen.
    var usesClassSelection: Bool {
        switch self {
        case .dashboard, .calendar, .students, .rooms: true
        case .settings, .feedback: false
        }
    }

    /// Privatsphäre-Modus-Button oben rechts – nur auf Seiten mit Klassen- bzw. Schülerdaten.
    var showsPrivacyMode: Bool { usesClassSelection }

    /// Tabs, die nur eine Aktion auslösen und nie ausgewählt werden.
    var isAction: Bool { self == .feedback }

    /// Gruppe in Sidebar (iPad) bzw. „Mehr“-Seite (iPhone).
    var section: AppTabSection {
        switch self {
        case .dashboard, .calendar, .students: .main
        case .rooms: .schoolClass
        case .feedback, .settings: .other
        }
    }

    /// Hauptseiten: immer in der unteren Tab-Leiste (iPhone / schmales Fenster).
    var isInTabBar: Bool { section == .main }

    /// Fest in der oberen, zentrierten Tab-Leiste (iPad); dazu kommt dort nur der gerade aktive Tab.
    var isInPadTabBar: Bool { self == .dashboard || self == .calendar }
}

/// Gruppen in Sidebar (iPad) und auf der „Mehr“-Seite (iPhone). Feste Reihenfolge, nicht anpassbar.
enum AppTabSection: String, CaseIterable, Identifiable {
    /// Hauptseiten ohne Gruppentitel, zusätzlich in der Tab-Leiste.
    case main
    case schoolClass
    case other

    var id: String { rawValue }

    /// Stabile ID für die (persistierte) Tab-Anpassung – nie ändern.
    var customizationID: String { "section.\(rawValue)" }

    var title: String {
        switch self {
        case .main: ""
        case .schoolClass: "Klasse"
        case .other: loc("Sonstige")
        }
    }

    /// Tabs der Gruppe in Standardreihenfolge (= Reihenfolge der `AppTab`-Cases).
    var tabs: [AppTab] { AppTab.allCases.filter { $0.section == self } }

    /// Gruppen mit Titel (alles außer den Hauptseiten).
    static let titled: [AppTabSection] = [.schoolClass, .other]
}
