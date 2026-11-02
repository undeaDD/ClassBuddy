import Foundation
import SwiftData

/// Paket mit allen Änderungen eines Geräts seit einem Zeitpunkt (unabhängig vom Weg: lokal, iCloud, Cloud-Ordner,
/// Datei). Gilt nur zwischen gleicher App-Version samt Build.
struct SyncPackage: Codable {
    static let currentFormat = 1

    var format = Self.currentFormat
    /// App-Version samt Build, z. B. „1.0.0 (12)“.
    var appVersion: String
    var deviceID: String
    var createdAt: Date
    /// Änderungen ab diesem Zeitpunkt; `nil` = alles.
    var since: Date?
    var entries: [SyncEntry]
    var deletions: [SyncDeletion]
    /// Dateien der Dokument- und Bild-Kacheln, nach Pfad in `LinkFileStore`.
    var files: [String: Data]
}

/// Ein Eintrag im Paket; `payload` ist das `Payload` des Typs (siehe `SyncPayloads`).
struct SyncEntry {
    var type: String
    var id: String
    var lastModified: Date
    var payload: any Codable
}

extension SyncEntry: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, lastModified, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        guard let recordType = SyncEngine.recordType(named: type) else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unbekannter Typ \(type)")
        }
        payload = try recordType.decodePayload(from: container.superDecoder(forKey: .payload))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(lastModified, forKey: .lastModified)
        try payload.encode(to: container.superEncoder(forKey: .payload))
    }
}

struct SyncDeletion: Codable, Equatable {
    var type: String
    var id: String
    var deletedAt: Date
}

/// Was beim Übernehmen eines Pakets passiert ist.
struct SyncResult: Equatable {
    var inserted = 0
    var updated = 0
    var deleted = 0
    /// Lokal neuer, darum behalten.
    var keptLocal = 0
}

enum SyncError: LocalizedError, Equatable {
    case versionMismatch(remote: String, local: String)
    case unsupportedFormat(Int)

    var errorDescription: String? {
        switch self {
        case .versionMismatch(let remote, let local):
            loc("Das andere Gerät hat ClassBuddy \(remote), dieses \(local). Bitte ClassBuddy auf allen Geräten aktualisieren.")
        case .unsupportedFormat:
            loc("Dieses Paket stammt aus einer anderen ClassBuddy-Version. Bitte ClassBuddy auf allen Geräten aktualisieren.")
        }
    }
}

/// Paket schreiben und übernehmen. Zusammenführen je Eintrag: Der neuere Stand (`lastModified`) gewinnt, ein Löschen
/// gewinnt gegen ältere Änderungen. Beim Übernehmen bleiben die Zeitstempel des anderen Geräts erhalten.
enum SyncEngine {
    /// Alle Typen in der Reihenfolge, in der sie übernommen werden: Jeder verweist nur auf Typen davor.
    static let recordTypes: [any SyncCodable.Type] = [
        SchoolClass.self, Room.self, Student.self, RoomElement.self, Lesson.self, CalendarEntry.self, Holiday.self,
        DashboardLink.self, BoardPhoto.self, Checklist.self, SubjectSettings.self, Assessment.self, SeatAssignment.self,
        ChecklistCheck.self, StudentObservation.self, Absence.self, AssessmentResult.self, PeriodGrade.self,
    ]

    static func recordType(named name: String) -> (any SyncCodable.Type)? {
        recordTypes.first { $0.syncRecordType == name }
    }

    /// Gerätekennung für Pakete (einmal erzeugt, bleibt).
    static var deviceID: String {
        let key = "sync.deviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    // MARK: Schreiben

    static func makePackage(since: Date?, in context: ModelContext, appVersion: String = AppInfo.version) throws -> SyncPackage {
        var entries: [SyncEntry] = []
        for type in recordTypes {
            entries += try type.entries(since: since, in: context)
        }
        let deletions = try context.fetch(FetchDescriptor<DeletedRecord>())
            .filter { deletion in since.map { deletion.deletedAt > $0 } ?? true }
            .map { SyncDeletion(type: $0.recordType, id: $0.recordID, deletedAt: $0.deletedAt) }
        var files: [String: Data] = [:]
        for entry in entries where entry.type == DashboardLink.syncRecordType {
            guard let link = entry.payload as? DashboardLink.Payload,
                  DashboardLink.Kind(rawValue: link.kindRaw)?.isStoredFile == true,
                  let data = try? Data(contentsOf: LinkFileStore.directory.appending(path: link.location))
            else { continue }
            files[link.location] = data
        }
        return SyncPackage(
            appVersion: appVersion, deviceID: deviceID, createdAt: .now, since: since,
            entries: entries, deletions: deletions, files: files
        )
    }

    // MARK: Übernehmen

    @discardableResult
    static func apply(_ package: SyncPackage, in context: ModelContext, appVersion: String = AppInfo.version) throws -> SyncResult {
        guard package.format == SyncPackage.currentFormat else { throw SyncError.unsupportedFormat(package.format) }
        guard package.appVersion == appVersion else {
            throw SyncError.versionMismatch(remote: package.appVersion, local: appVersion)
        }
        SyncTracking.isApplyingRemoteChanges = true
        defer { SyncTracking.isApplyingRemoteChanges = false }

        var result = SyncResult()
        let references = SyncReferences()
        for type in recordTypes {
            try type.registerAll(in: context, references: references)
        }
        let localDeletions = try context.fetch(FetchDescriptor<DeletedRecord>())
        var deletedAt = Dictionary(localDeletions.map { ("\($0.recordType)/\($0.recordID)", $0.deletedAt) }, uniquingKeysWith: max)
        applyDeletions(package.deletions, in: context, references: references, deletedAt: &deletedAt, result: &result)

        let byType = Dictionary(grouping: package.entries, by: \.type)
        for type in recordTypes {
            for entry in byType[type.syncRecordType] ?? [] {
                // Lokal gelöscht, nachdem es drüben zuletzt geändert wurde: gelöscht lassen.
                if let deleted = deletedAt["\(entry.type)/\(entry.id)"], deleted >= entry.lastModified { continue }
                type.merge(entry, in: context, references: references, result: &result)
            }
        }

        writeFiles(package.files)
        try context.save()
        return result
    }

    /// Löschungen zuerst: lokal nur, wenn der Eintrag dort nicht später geändert wurde. Jede wird auch hier
    /// festgehalten, damit sie an weitere Geräte weitergeht.
    private static func applyDeletions(
        _ deletions: [SyncDeletion], in context: ModelContext, references: SyncReferences,
        deletedAt: inout [String: Date], result: inout SyncResult
    ) {
        for deletion in deletions {
            let key = "\(deletion.type)/\(deletion.id)"
            guard deletedAt[key].map({ $0 < deletion.deletedAt }) ?? true else { continue }
            let type = recordType(named: deletion.type)
            if type?.delete(id: deletion.id, ifOlderThan: deletion.deletedAt, in: context, references: references) == true {
                result.deleted += 1
            }
            deletedAt[key] = deletion.deletedAt
            context.insert(DeletedRecord(recordType: deletion.type, recordID: deletion.id, deletedAt: deletion.deletedAt))
        }
    }

    /// Dateien der Kacheln, die hier noch fehlen (Pfade enthalten eine eigene UUID, gleiche Pfade = gleiche Datei).
    private static func writeFiles(_ files: [String: Data]) {
        for (path, data) in files {
            let url = LinkFileStore.directory.appending(path: path)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}

// MARK: Je Typ

extension SyncCodable {
    static func decodePayload(from decoder: Decoder) throws -> any Codable {
        try Payload(from: decoder)
    }

    static func entries(since: Date?, in context: ModelContext) throws -> [SyncEntry] {
        try context.fetch(FetchDescriptor<Self>())
            .filter { record in since.map { record.lastModified > $0 } ?? true }
            .map { SyncEntry(type: syncRecordType, id: $0.syncID, lastModified: $0.lastModified, payload: $0.payload) }
    }

    static func registerAll(in context: ModelContext, references: SyncReferences) throws {
        try context.fetch(FetchDescriptor<Self>()).forEach(references.register)
    }

    /// Neu anlegen oder, wenn drüben neuer, überschreiben; Zeitstempel vom anderen Gerät.
    static func merge(_ entry: SyncEntry, in context: ModelContext, references: SyncReferences, result: inout SyncResult) {
        guard let payload = entry.payload as? Payload else { return }
        if let existing: Self = references.find(entry.id) {
            guard entry.lastModified > existing.lastModified else {
                result.keptLocal += 1
                return
            }
            existing.apply(payload, references: references)
            existing.lastModified = entry.lastModified
            result.updated += 1
        } else if let record = makeEmpty(syncID: entry.id) {
            context.insert(record)
            record.apply(payload, references: references)
            record.lastModified = entry.lastModified
            references.register(record)
            result.inserted += 1
        }
    }

    /// Löschen, falls vorhanden und lokal nicht später geändert.
    static func delete(id: String, ifOlderThan date: Date, in context: ModelContext, references: SyncReferences) -> Bool {
        guard let existing: Self = references.find(id), existing.lastModified <= date else { return false }
        context.delete(existing)
        return true
    }
}
