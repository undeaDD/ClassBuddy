import Foundation
import SwiftData

/// Zuletzt angelegter Schüler, Checkliste bzw. Termin für „Zuletzt angelegt“ in den Neu-Formularen,
/// auch nach dem Schließen und Neustart (Kennung in UserDefaults). Gelöschte Einträge zählen nicht:
/// Die Kennung wird beim Lesen nachgeschlagen und verworfen, wenn es den Eintrag nicht mehr gibt.
enum LastCreated {
    enum Kind: String, CaseIterable {
        case student
        case checklist
        case calendarEntry

        var defaultsKey: String { "lastCreated.\(rawValue)" }
    }

    static func record(_ id: UUID, as kind: Kind, defaults: UserDefaults = .standard) {
        defaults.set(id.uuidString, forKey: kind.defaultsKey)
    }

    static func id(of kind: Kind, defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: kind.defaultsKey).flatMap(UUID.init(uuidString:))
    }

    static func student(in context: ModelContext, defaults: UserDefaults = .standard) -> Student? {
        lookup(.student, defaults: defaults) { id in
            try? context.fetch(FetchDescriptor<Student>(predicate: #Predicate { $0.id == id })).first
        }
    }

    static func checklist(in context: ModelContext, defaults: UserDefaults = .standard) -> Checklist? {
        lookup(.checklist, defaults: defaults) { id in
            try? context.fetch(FetchDescriptor<Checklist>(predicate: #Predicate { $0.id == id })).first
        }
    }

    static func calendarEntry(in context: ModelContext, defaults: UserDefaults = .standard) -> CalendarEntry? {
        lookup(.calendarEntry, defaults: defaults) { id in
            try? context.fetch(FetchDescriptor<CalendarEntry>(predicate: #Predicate { $0.id == id })).first
        }
    }

    /// Anzeige eines Termins: Titel, ohne Titel Datum und Uhrzeit.
    static func displayTitle(of entry: CalendarEntry) -> String {
        entry.title.isEmpty ? entry.start.appDateTime : entry.title
    }

    private static func lookup<T>(_ kind: Kind, defaults: UserDefaults, fetch: (UUID) -> T?) -> T? {
        guard let id = id(of: kind, defaults: defaults) else { return nil }
        guard let model = fetch(id) else {
            defaults.removeObject(forKey: kind.defaultsKey)
            return nil
        }
        return model
    }
}
