import Foundation
import SwiftData

// Grundlage für Sync und Teilen (Plan „Sync und Teilen“ in der Aufgabenliste): Jedes Sichern stempelt die geänderten Einträge mit
// `lastModified`, jedes Löschen hinterlässt einen `DeletedRecord`. Beides ergänzt das Schema nur (neues Feld mit
// Standardwert, neue Tabelle): SwiftData übernimmt bestehende Daten beim ersten Start ohne eigene Migration.

/// Eintrag, der zwischen Geräten abgeglichen wird.
protocol SyncRecord: AnyObject {
    /// Letzte Änderung; ältere Einträge (vor dem Sync) haben `.distantPast`.
    var lastModified: Date { get set }
    /// Geräteübergreifend gleiche ID.
    var syncID: String { get }
    /// Name des Eintragstyps im Sync (fest, nie ändern).
    static var syncRecordType: String { get }
}

/// Gelöschter Eintrag, damit das Löschen auch auf den anderen Geräten ankommt.
/// Feld `recordType` statt `entity`: Der Name ist bei Core Data intern belegt (Absturz beim Sichern).
@Model
final class DeletedRecord {
    var recordType: String = ""
    var recordID: String = ""
    var deletedAt: Date = Date.distantPast

    init(recordType: String, recordID: String, deletedAt: Date = .now) {
        self.recordType = recordType
        self.recordID = recordID
        self.deletedAt = deletedAt
    }
}

/// Beobachtet alle Sicherungen: vorher `lastModified` setzen, danach Löschungen als `DeletedRecord` festhalten
/// (Einfügen während des Sicherns verträgt SwiftData nicht, darum erst danach mit einer zweiten Sicherung).
/// Die App hat nur den Haupt-Kontext, die Benachrichtigungen kommen also auf dem Main Thread.
enum SyncTracking {
    private static var observers: [any NSObjectProtocol] = []
    private static var pendingDeletions: [(type: String, id: String)] = []
    /// Beim Übernehmen von Änderungen anderer Geräte: deren Zeitstempel behalten, Löschungen nicht erneut melden.
    static var isApplyingRemoteChanges = false

    /// Einmal beim App-Start.
    static func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: ModelContext.willSave, object: nil, queue: nil) { notification in
                nonisolated(unsafe) let context = notification.object as? ModelContext
                MainActor.assumeIsolated { if let context { willSave(context) } }
            },
            center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { notification in
                nonisolated(unsafe) let context = notification.object as? ModelContext
                MainActor.assumeIsolated { if let context { didSave(context) } }
            },
        ]
    }

    private static func willSave(_ context: ModelContext) {
        guard !isApplyingRemoteChanges else { return }
        let now = Date.now
        for case let record as any SyncRecord in context.insertedModelsArray + context.changedModelsArray {
            record.lastModified = now
        }
        for case let record as any SyncRecord in context.deletedModelsArray {
            pendingDeletions.append((type(of: record).syncRecordType, record.syncID))
        }
    }

    private static func didSave(_ context: ModelContext) {
        guard !pendingDeletions.isEmpty else { return }
        let deletions = pendingDeletions
        pendingDeletions = []
        // Container ohne diese Tabelle (z. B. in Tests mit wenigen Modellen): nichts festhalten.
        guard context.container.schema.entities.contains(where: { $0.name == String(describing: DeletedRecord.self) }) else { return }
        for deletion in deletions {
            context.insert(DeletedRecord(recordType: deletion.type, recordID: deletion.id))
        }
        try? context.save()
    }
}

// MARK: Eintragstypen

extension SchoolClass: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "SchoolClass"
}

extension Student: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "Student"
}

extension Lesson: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "Lesson"
}

extension CalendarEntry: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "CalendarEntry"
}

extension Holiday: SyncRecord {
    var syncID: String { id }
    static let syncRecordType = "Holiday"
}

extension DashboardLink: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "DashboardLink"
}

extension Room: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "Room"
}

extension RoomElement: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "RoomElement"
}

extension SeatAssignment: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "SeatAssignment"
}

extension BoardPhoto: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "BoardPhoto"
}

extension Checklist: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "Checklist"
}

extension ChecklistCheck: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "ChecklistCheck"
}

extension SubjectSettings: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "SubjectSettings"
}

extension StudentObservation: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "StudentObservation"
}

extension Absence: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "Absence"
}

extension Assessment: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "Assessment"
}

extension AssessmentResult: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "AssessmentResult"
}

extension PeriodGrade: SyncRecord {
    var syncID: String { id.uuidString }
    static let syncRecordType = "PeriodGrade"
}
