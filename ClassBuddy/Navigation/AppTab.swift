import SwiftUI

/// Alle Ziele der App. Reihenfolge der Cases = Standardreihenfolge in Sidebar/Tab-Bar.
enum AppTab: String, CaseIterable, Identifiable, Hashable, Codable {
    // Tab-Bar (oben)
    case dashboard
    case students
    case seating
    case grades
    case schedule

    // Sidebar: Unterricht
    case classbook
    case attendance
    case homework
    case lessonPlanning

    // Sidebar: Leistung
    case exams
    case observations
    case reports

    // Sidebar: Organisation
    case parents
    case events
    case documents
    case notes

    // System
    case settings
    case search

    var id: String { rawValue }

    /// Stabile ID für die (persistierte) Tab-Anpassung – nie ändern.
    var customizationID: String { "tab.\(rawValue)" }

    var title: String {
        switch self {
        case .dashboard: "Übersicht"
        case .students: "Schüler"
        case .seating: "Sitzplan"
        case .grades: "Noten"
        case .schedule: "Stundenplan"
        case .classbook: "Klassenbuch"
        case .attendance: "Anwesenheit"
        case .homework: "Hausaufgaben"
        case .lessonPlanning: "Unterrichtsplanung"
        case .exams: "Klassenarbeiten"
        case .observations: "Beobachtungen"
        case .reports: "Zeugnisse"
        case .parents: "Elternkontakte"
        case .events: "Termine"
        case .documents: "Dokumente"
        case .notes: "Notizen"
        case .settings: "Einstellungen"
        case .search: "Suche"
        }
    }

    var symbol: AppSymbol {
        switch self {
        case .dashboard: .system("square.grid.2x2")
        case .students: .system("person.3")
        case .seating: .system("table.furniture")
        case .grades: .system("chart.bar.doc.horizontal")
        case .schedule: .system("calendar.day.timeline.left")
        case .classbook: .system("book.closed")
        case .attendance: .system("checklist.checked")
        case .homework: .system("house.and.flag")
        case .lessonPlanning: .system("list.bullet.clipboard")
        case .exams: .system("doc.text.magnifyingglass")
        case .observations: .system("eye.square")
        case .reports: .system("rosette")
        case .parents: .system("figure.2.and.child.holdinghands")
        case .events: .system("calendar")
        case .documents: .system("folder")
        case .notes: .system("note.text")
        case .settings: .system("gearshape")
        case .search: .system("magnifyingglass")
        }
    }

    var section: AppTabSection? {
        switch self {
        case .dashboard, .students, .seating, .grades, .schedule, .settings, .search: nil
        case .classbook, .attendance, .homework, .lessonPlanning: .teaching
        case .exams, .observations, .reports: .performance
        case .parents, .events, .documents, .notes: .organisation
        }
    }

    var summary: String {
        switch self {
        case .dashboard: "Dein Tag auf einen Blick."
        case .students: "Alle Schülerinnen und Schüler der Klasse mit Profil und Kontaktdaten."
        case .seating: "Sitzplatzverwaltung: Sitzordnungen planen, speichern und wechseln."
        case .grades: "Mündliche und schriftliche Noten erfassen und auswerten."
        case .schedule: "Stundenplan der Klasse und deine eigenen Stunden."
        case .classbook: "Unterrichtsinhalte und Einträge pro Stunde."
        case .attendance: "Fehlzeiten, Verspätungen und Entschuldigungen."
        case .homework: "Hausaufgaben vergeben und abhaken."
        case .lessonPlanning: "Reihen- und Stundenplanung."
        case .exams: "Klassenarbeiten und Tests mit Notenspiegel."
        case .observations: "Pädagogische Beobachtungen zu einzelnen Schülern."
        case .reports: "Zeugnisbemerkungen und Notenkonferenzen vorbereiten."
        case .parents: "Elterngespräche, Kontakte und Protokolle."
        case .events: "Termine, Ausflüge und Fristen."
        case .documents: "Dateien und Vorlagen zur Klasse."
        case .notes: "Freie Notizen."
        case .settings: "App-Sperre, Datenschutz und Export."
        case .search: "Alles durchsuchen."
        }
    }

    var plannedFeatures: [String] {
        switch self {
        case .seating: [
            "Raumlayout mit Tischen per Drag & Drop (auch mit dem Apple Pencil)",
            "Mehrere Sitzordnungen pro Klasse (z. B. Klassenarbeit, Gruppenarbeit)",
            "Zufällige / regelbasierte Verteilung",
            "Schnellerfassung von Anwesenheit direkt im Sitzplan",
        ]
        case .students: ["Schülerliste mit Suche", "Profile mit Foto", "Import aus CSV"]
        case .grades: ["Notenbuch pro Fach", "Gewichtungen", "Durchschnitte & Tendenzen"]
        case .attendance: ["Tagesansicht", "Entschuldigungen", "Statistik pro Schüler"]
        default: []
        }
    }
}

enum AppTabSection: String, CaseIterable, Identifiable {
    case teaching
    case performance
    case organisation

    var id: String { rawValue }
    var customizationID: String { "section.\(rawValue)" }

    var title: String {
        switch self {
        case .teaching: "Unterricht"
        case .performance: "Leistung"
        case .organisation: "Organisation"
        }
    }

    var tabs: [AppTab] { AppTab.allCases.filter { $0.section == self } }
}

extension AppTab {
    /// Tabs, die standardmäßig in der oberen Tab-Bar erscheinen.
    static let tabBarTabs: [AppTab] = [.dashboard, .students, .seating, .grades, .schedule]
}
