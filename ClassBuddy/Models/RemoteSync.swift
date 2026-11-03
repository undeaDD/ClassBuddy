import CloudKit
import CryptoKit
import Foundation
import SwiftData

// Abgleich über einen Speicher, den alle eigenen Geräte erreichen (Cloud-Ordner, iCloud): Jedes Gerät legt dort
// eine eigene Datei mit seinem ganzen Stand ab, verschlüsselt mit dem Daten-Passwort, und übernimmt die Dateien der
// anderen (Zusammenführen wie beim lokalen Sync, neuerer Stand gewinnt). Der Anbieter sieht nichts Lesbares.

/// Was ein Abgleich über Dateien ergeben hat.
struct RemoteSyncReport: Equatable {
    var result = SyncResult()
    var devices = 0
    var problems: [String] = []

    var message: String {
        let changes = result.inserted + result.updated + result.deleted
        var text = devices == 0
            ? loc("Abgeglichen, noch keine anderen Geräte.")
            : changes == 0
                ? loc("Abgeglichen, alles war schon aktuell.")
                : loc("Abgeglichen: \(result.inserted) neu, \(result.updated) aktualisiert, \(result.deleted) gelöscht.")
        if result.settingsUpdated { text += " " + loc("Einstellungen übernommen.") }
        return ([text] + problems).joined(separator: " ")
    }
}

enum RemoteSync {
    /// Eigener Stand als verschlüsselte Datei.
    /// Lesen aus der Datenbank auf dem Main Thread, Verschlüsseln (PBKDF2, AES) im Hintergrund.
    static func ownFile(
        in context: ModelContext, settings: SchoolSettings, deviceName: String, password: String
    ) async throws -> Data {
        var package = try SyncEngine.makePackage(since: nil, in: context, settings: settings)
        package.deviceName = deviceName
        let json = try JSONEncoder().encode(package)
        return try await Task.detached { try DataCrypto.seal(json, password: password) }.value
    }

    /// Fingerabdruck des eigenen Stands: Nur bei Änderungen muss die Datei neu geschrieben werden.
    static func fingerprint(in context: ModelContext, settings: SchoolSettings, password: String) throws -> String {
        let manifest = try SyncEngine.manifest(in: context, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var data = try encoder.encode(manifest)
        data += Data(password.utf8) + Data(AppInfo.version.utf8)
        return SHA256Digest.hex(data)
    }

    /// Dateien der anderen Geräte übernehmen; eigene (gleiche Geräte-ID) werden übersprungen.
    /// Entschlüsseln im Hintergrund, Übernehmen auf dem Main Thread (SwiftData).
    static func merge(
        _ files: [Data], in context: ModelContext, settings: SchoolSettings, password: String
    ) async -> RemoteSyncReport {
        let opened = await Task.detached {
            files.map { file in Result { try DataCrypto.open(file, password: password) } }
        }.value
        var report = RemoteSyncReport()
        var wrongPassword = 0
        for file in opened {
            do {
                let json = try file.get()
                let package = try JSONDecoder().decode(SyncPackage.self, from: json)
                guard package.deviceID != SyncEngine.deviceID else { continue }
                let result = try SyncEngine.apply(package, in: context, settings: settings)
                report.devices += 1
                report.result.inserted += result.inserted
                report.result.updated += result.updated
                report.result.deleted += result.deleted
                report.result.keptLocal += result.keptLocal
                report.result.settingsUpdated = report.result.settingsUpdated || result.settingsUpdated
            } catch DataCrypto.CryptoError.wrongPassword {
                wrongPassword += 1
            } catch let error as SyncError {
                report.problems.append(error.localizedDescription)
            } catch {
                context.rollback()
                report.problems.append(loc("Eine Datei war unvollständig und wurde übersprungen."))
            }
        }
        if wrongPassword > 0 {
            report.problems.append(loc("\(wrongPassword) Geräte nutzen ein anderes Daten-Passwort. Es muss auf allen Geräten gleich sein."))
        }
        return report
    }
}

enum SHA256Digest {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Zustand eines Abgleichs für die Anzeige.
enum RemoteSyncState: Equatable {
    case idle
    case syncing
    case finished(String)
    case failed(String)
}

// MARK: Cloud-Ordner

/// Eigener Cloud-Ordner (Google Drive, Nextcloud, OneDrive, Dropbox, iCloud Drive …) über die Dateien-App.
/// Nur von Hand („Jetzt synchronisieren“). Je Gerät eine Datei „ClassBuddy-<Gerät>.cbsync“.
@MainActor
@Observable
final class CloudFolderSync {
    private(set) var folderName: String?
    private(set) var lastSync: Date?
    private(set) var state = RemoteSyncState.idle

    private static let bookmarkKey = "sync.cloudFolder.bookmark"
    private static let nameKey = "sync.cloudFolder.name"
    private static let lastSyncKey = "sync.cloudFolder.lastSync"
    nonisolated static let fileExtension = "cbsync"

    init() {
        folderName = UserDefaults.standard.string(forKey: Self.nameKey)
        lastSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    var isBusy: Bool { state == .syncing }

    func choose(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData()
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: Self.nameKey)
            folderName = url.lastPathComponent
            lastSync = nil
            UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
            state = .idle
        } catch {
            state = .failed(loc("Der Ordner lässt sich nicht verwenden: \(error.localizedDescription)"))
        }
    }

    /// Ordner nicht mehr verwenden; die Dateien darin bleiben.
    func remove() {
        [Self.bookmarkKey, Self.nameKey, Self.lastSyncKey].forEach(UserDefaults.standard.removeObject)
        folderName = nil
        lastSync = nil
        state = .idle
    }

    func sync(context: ModelContext, settings: SchoolSettings, deviceName: String) async {
        guard !isBusy, let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        state = .syncing
        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            state = .failed(loc("Der Ordner ist nicht mehr erreichbar. Bitte neu wählen."))
            return
        }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        if isStale, let fresh = try? folder.bookmarkData() { UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey) }

        let password = DataPassword.current
        let ownName = "ClassBuddy-\(SyncEngine.deviceID.prefix(8)).\(Self.fileExtension)"
        do {
            let files = try await Task.detached { try Self.readFiles(in: folder, except: ownName) }.value
            let report = await RemoteSync.merge(files, in: context, settings: settings, password: password)
            let own = try await RemoteSync.ownFile(in: context, settings: settings, deviceName: deviceName, password: password)
            try await Task.detached { try Self.write(own, to: folder.appending(path: ownName)) }.value
            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: Self.lastSyncKey)
            state = .finished(report.message)
        } catch {
            state = .failed(loc("Abgleich mit dem Ordner fehlgeschlagen: \(error.localizedDescription)"))
        }
    }

    /// Alle .cbsync-Dateien außer der eigenen; noch nicht geladene (iCloud Drive: „.Name.icloud“) werden geladen.
    private nonisolated static func readFiles(in folder: URL, except ownName: String) throws -> [Data] {
        var names = Set<String>()
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
            if name.hasSuffix(".\(fileExtension)") {
                names.insert(name)
            } else if name.hasPrefix("."), name.hasSuffix(".\(fileExtension).icloud") {
                names.insert(String(name.dropFirst().dropLast(".icloud".count)))
            }
        }
        names.remove(ownName)
        return try names.sorted().map { name in
            let url = folder.appending(path: name)
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return try coordinatedRead(url)
        }
    }

    private nonisolated static func coordinatedRead(_ url: URL) throws -> Data {
        var coordinatorError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    private nonisolated static func write(_ data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var result: Result<Void, Error> = .success(())
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writeURL in
            result = Result { try data.write(to: writeURL, options: .atomic) }
        }
        if let coordinatorError { throw coordinatorError }
        try result.get()
    }
}

// MARK: iCloud

/// iCloud (private Datenbank des Nutzers, eigene Zone): je Gerät ein Eintrag mit der verschlüsselten Datei als
/// Anhang. Läuft automatisch beim Öffnen der App (höchstens alle paar Minuten) und auf Wunsch von Hand.
@MainActor
@Observable
final class ICloudSync {
    static let containerID = "iCloud.de.devsforge.ClassBuddy"
    private static let enabledKey = "sync.icloud.enabled"
    private static let lastSyncKey = "sync.icloud.lastSync"
    private static let fingerprintKey = "sync.icloud.fingerprint"
    private static let recordType = "DevicePackage"
    private static let minimumInterval: TimeInterval = 5 * 60

    private(set) var isEnabled: Bool
    private(set) var lastSync: Date?
    private(set) var state = RemoteSyncState.idle

    private let zoneID = CKRecordZone.ID(zoneName: "ClassBuddy", ownerName: CKCurrentUserDefaultName)
    private var container: CKContainer { CKContainer(identifier: Self.containerID) }

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        lastSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    var isBusy: Bool { state == .syncing }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        // Neu einschalten: eigene Datei in jedem Fall hochladen.
        UserDefaults.standard.removeObject(forKey: Self.fingerprintKey)
        if !enabled { state = .idle }
    }

    /// Beim Öffnen der App: nur wenn eingeschaltet und der letzte Abgleich ein paar Minuten her ist.
    func syncOnOpen(context: ModelContext, settings: SchoolSettings, deviceName: String) async {
        guard isEnabled, lastSync.map({ Date.now.timeIntervalSince($0) > Self.minimumInterval }) ?? true else { return }
        await sync(context: context, settings: settings, deviceName: deviceName)
    }

    func sync(context: ModelContext, settings: SchoolSettings, deviceName: String) async {
        guard isEnabled, !isBusy else { return }
        state = .syncing
        do {
            guard try await container.accountStatus() == .available else {
                state = .failed(loc("Bitte auf diesem Gerät in den iOS-Einstellungen bei iCloud anmelden."))
                return
            }
            let database = container.privateCloudDatabase
            _ = try? await database.save(CKRecordZone(zoneID: zoneID))

            let password = DataPassword.current
            let files = try await fetchFiles(from: database)
            let report = await RemoteSync.merge(files, in: context, settings: settings, password: password)

            let fingerprint = try RemoteSync.fingerprint(in: context, settings: settings, password: password)
            if fingerprint != UserDefaults.standard.string(forKey: Self.fingerprintKey) {
                let own = try await RemoteSync.ownFile(in: context, settings: settings, deviceName: deviceName, password: password)
                try await upload(own, deviceName: deviceName, to: database)
                UserDefaults.standard.set(fingerprint, forKey: Self.fingerprintKey)
            }
            lastSync = .now
            UserDefaults.standard.set(lastSync, forKey: Self.lastSyncKey)
            state = .finished(report.message)
        } catch {
            state = .failed(loc("Abgleich mit iCloud fehlgeschlagen: \(error.localizedDescription)"))
        }
    }

    private func fetchFiles(from database: CKDatabase) async throws -> [Data] {
        var files: [Data] = []
        var token: CKServerChangeToken?
        var moreComing = true
        while moreComing {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            for (id, result) in changes.modificationResultsByID where id.recordName != SyncEngine.deviceID {
                guard let record = try? result.get().record, record.recordType == Self.recordType,
                      let url = (record["package"] as? CKAsset)?.fileURL, let data = try? Data(contentsOf: url)
                else { continue }
                files.append(data)
            }
            token = changes.changeToken
            moreComing = changes.moreComing
        }
        return files
    }

    private func upload(_ data: Data, deviceName: String, to database: CKDatabase) async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "icloud-\(UUID().uuidString).\(CloudFolderSync.fileExtension)")
        try data.write(to: url, options: .completeFileProtection)
        defer { try? FileManager.default.removeItem(at: url) }
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: SyncEngine.deviceID, zoneID: zoneID))
        record["package"] = CKAsset(fileURL: url)
        record["appVersion"] = AppInfo.version
        record.encryptedValues["deviceName"] = deviceName
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }
}
