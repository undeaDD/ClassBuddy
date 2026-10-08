import Foundation

/// Stundenplan für das Widget „Jetzt & Als Nächstes“ (App und Widget-Erweiterung teilen diese Datei).
/// Die App schreibt die kommenden Stunden als JSON in den App-Group-Container; das Widget liest nur das –
/// keine SwiftData-Datenbank, keine Schülerdaten (nur Klasse, Fach, Raum und Zeiten).
nonisolated enum WidgetSchedule {
    /// `group.<Bundle-ID der App>` (Config/Base.xcconfig: APP_GROUP_ID), in App und Widget gleich.
    static let appGroup = groupID(forBundleID: Bundle.main.bundleIdentifier ?? "de.devsforge.ClassBuddy")

    /// Das Widget hat die Bundle-ID `<App>.Widgets`; die Gruppe gehört zur App.
    static func groupID(forBundleID bundleID: String) -> String {
        let suffix = ".Widgets"
        let appID = bundleID.hasSuffix(suffix) ? String(bundleID.dropLast(suffix.count)) : bundleID
        return "group." + appID
    }
    static let widgetKind = "ScheduleWidget"

    struct Lesson: Codable, Hashable, Sendable {
        let start: Date
        let end: Date
        /// „3. Stunde“ (Nummer im Raster).
        let slotNumber: Int
        let className: String
        let subject: String
        let room: String?
        /// Klassenfarbe als RGB (0…1), damit das Widget die App-Farben nicht kennen muss.
        let red: Double
        let green: Double
        let blue: Double
    }

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "widget-schedule.json")
    }

    /// Schutzklasse bewusst „bis zur ersten Entsperrung“ statt „vollständig“ (App-Standard): Widgets werden
    /// auch bei gesperrtem Gerät gerendert. Der Inhalt ist unkritisch (siehe oben).
    static func save(_ lessons: [Lesson]) throws {
        guard let fileURL else { return }
        let data = try JSONEncoder().encode(lessons)
        // Bewusst ohne vollständigen Schutz (siehe oben): Widget rendert bei gesperrtem Gerät, Inhalt ohne Schülerdaten.
        // nosemgrep: swift.lang.storage.storage-protections.swift-data-protection
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load() -> [Lesson] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Lesson].self, from: data)) ?? []
    }

    /// Laufende Stunde und die danach folgenden (beendete fallen weg).
    static func upcoming(_ lessons: [Lesson], at date: Date) -> (current: Lesson?, next: [Lesson]) {
        let remaining = lessons.filter { $0.end > date }.sorted { $0.start < $1.start }
        guard let first = remaining.first, first.start <= date else { return (nil, remaining) }
        return (first, Array(remaining.dropFirst()))
    }
}
