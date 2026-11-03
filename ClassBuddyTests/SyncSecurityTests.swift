import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

/// Daten-Passwort, Verschlüsselung (eigene Dateien und Excel), Compound File, Einstellungs-Sync und Berichte.
@Suite("Sync: Passwort, Verschlüsselung, Dateien")
@MainActor
struct SyncSecurityTests {
    init() {
        AppLanguage.current = .german
        SyncTracking.start()
    }

    private static var containers: [ModelContainer] = []

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self, DashboardLink.self,
            Room.self, RoomElement.self, SeatAssignment.self, BoardPhoto.self, Checklist.self, ChecklistCheck.self,
            SubjectSettings.self, StudentObservation.self, Absence.self, Assessment.self, AssessmentResult.self,
            PeriodGrade.self, DeletedRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        containers.append(container)
        return container.mainContext
    }

    private static func makeSettings() throws -> SchoolSettings {
        SchoolSettings(defaults: try #require(UserDefaults(suiteName: "SyncSecurityTests.\(UUID())")))
    }

    // MARK: Daten-Passwort und DataCrypto

    @Test("Gleiche Daten ergeben jedes Mal eine andere verschlüsselte Datei (zufälliges Salt)")
    func sealIsRandomized() throws {
        let data = Data("Emma Schneider".utf8)
        #expect(try DataCrypto.seal(data, password: "passwort-1") != DataCrypto.seal(data, password: "passwort-1"))
    }

    @Test("Abgeschnittene Datei wird abgelehnt")
    func openRejectsTruncated() throws {
        let sealed = try DataCrypto.seal(Data("Notiz".utf8), password: "passwort-1")
        #expect(throws: DataCrypto.CryptoError.wrongPassword) { try DataCrypto.open(sealed.prefix(30), password: "passwort-1") }
    }

    @Test("Veränderte Datei wird abgelehnt (GCM-Prüfung)")
    func openRejectsTampering() throws {
        var sealed = try DataCrypto.seal(Data("Note 2".utf8), password: "passwort-1")
        sealed[sealed.count - 1] ^= 0xFF
        #expect(throws: DataCrypto.CryptoError.wrongPassword) { try DataCrypto.open(sealed, password: "passwort-1") }
    }

    @Test("Unverschlüsseltes JSON gilt nicht als verschlüsselt")
    func plainIsNotSealed() {
        #expect(!DataCrypto.isSealed(Data(#"{"format":1}"#.utf8)))
        #expect(!DataCrypto.isSealed(Data()))
    }

    @Test("Erzeugtes Passwort: 4 Gruppen à 5 gut lesbare Zeichen")
    func generatedPasswordFormat() {
        let groups = DataPassword.generate().split(separator: "-")
        #expect(groups.count == 4 && groups.allSatisfy { $0.count == 5 })
        let allowed = Set("abcdefghjkmnpqrstuvwxyz23456789")
        #expect(groups.joined().allSatisfy(allowed.contains))
    }

    @Test("Erzeugte Passwörter wiederholen sich nicht")
    func generatedPasswordsDiffer() {
        #expect(Set((0..<20).map { _ in DataPassword.generate() }).count == 20)
    }

    @Test("Mindestlänge zählt ohne Leerzeichen am Rand")
    func passwordValidation() {
        #expect(!DataPassword.isValid("   abc   "))
        #expect(!DataPassword.isValid("1234567"))
        #expect(DataPassword.isValid("12345678"))
        #expect(DataPassword.isValid("  Lehrer Passwort  "))
    }

    // MARK: Excel-Verschlüsselung

    @Test("Segmentgrenzen: genau 4096 und 4097 Bytes")
    func officeSegmentBoundaries() throws {
        for count in [4096, 4097, 8192] {
            let data = Data((0..<count).map { UInt8(truncatingIfNeeded: $0) })
            #expect(try OfficeEncryption.decrypt(OfficeEncryption.encrypt(data, password: "grenze"), password: "grenze") == data)
        }
    }

    @Test("Passwort mit Umlauten und Emoji")
    func officeUnicodePassword() throws {
        let data = Data(repeating: 42, count: 5000)
        let password = "Schüler Ölgemälde ✏️ ß"
        let encrypted = try OfficeEncryption.encrypt(data, password: password)
        #expect(try OfficeEncryption.decrypt(encrypted, password: password) == data)
        #expect(throws: OfficeEncryption.OfficeError.wrongPassword) {
            try OfficeEncryption.decrypt(encrypted, password: "Schuler Olgemalde ✏️ ß")
        }
    }

    @Test("Unverschlüsselte .xlsx lässt sich nicht entschlüsseln")
    func officeRejectsPlainFile() {
        let xlsx = XLSX.write([XLSXSheet(name: "Test", rows: [["A"]])])
        #expect(throws: (any Error).self) { try OfficeEncryption.decrypt(xlsx, password: "egal") }
    }

    @Test("Kurze oder fremde Daten gelten nicht als verschlüsselt")
    func officeDetection() {
        #expect(!OfficeEncryption.isEncrypted(Data([0xD0, 0xCF, 0x11, 0xE0])))
        #expect(!OfficeEncryption.isEncrypted(Data(repeating: 0, count: 1024)))
    }

    // MARK: Compound File

    @Test("Kleine und große Ströme im Wurzelordner hin und zurück")
    func compoundFileRoundTrip() throws {
        let small = Data((0..<100).map { UInt8($0) })
        let big = Data((0..<10_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let file = try CompoundFile(CompoundFile.write([
            CompoundFile.Entry(path: ["Klein"], data: small),
            CompoundFile.Entry(path: ["Groß"], data: big),
        ]))
        #expect(file.stream(named: "Klein") == small)
        #expect(file.stream(named: "Groß") == big)
    }

    @Test("Ströme in Unterordnern und fehlende Ströme werden im Wurzelordner nicht gefunden")
    func compoundFileNestedStreams() throws {
        let file = try CompoundFile(CompoundFile.write([
            CompoundFile.Entry(path: ["Ordner", "Innen"], data: Data([1, 2, 3])),
            CompoundFile.Entry(path: ["Außen"], data: Data([4])),
        ]))
        #expect(file.stream(named: "Innen") == nil)
        #expect(file.stream(named: "Fehlt") == nil)
        #expect(file.stream(named: "Außen") == Data([4]))
    }

    @Test("Ausgabe: Signatur und ganze 512-Byte-Sektoren")
    func compoundFileLayout() {
        let data = CompoundFile.write([CompoundFile.Entry(path: ["A"], data: Data(repeating: 1, count: 5000))])
        #expect(CompoundFile.isCompoundFile(data))
        #expect(data.count % 512 == 0)
    }

    @Test("Kaputte Daten werden abgelehnt")
    func compoundFileRejectsGarbage() {
        #expect(throws: (any Error).self) { try CompoundFile(Data(repeating: 7, count: 2048)) }
    }

    // MARK: Berichte und Zusammenführen

    @Test("Bericht ohne andere Geräte")
    func reportWithoutDevices() {
        #expect(RemoteSyncReport().message == "Abgeglichen, noch keine anderen Geräte.")
    }

    @Test("Bericht nennt Änderungen, Einstellungen und Probleme")
    func reportWithChanges() {
        var report = RemoteSyncReport()
        report.devices = 2
        report.result.inserted = 3
        report.result.settingsUpdated = true
        report.problems = ["Hinweis."]
        #expect(report.message.hasPrefix("Abgeglichen: 3 neu, 0 aktualisiert, 0 gelöscht."))
        #expect(report.message.contains("Einstellungen übernommen.") && report.message.hasSuffix("Hinweis."))
    }

    @Test("Unvollständige Datei wird übersprungen und gemeldet")
    func mergeSkipsCorruptFile() async throws {
        let context = try Self.makeContext()
        let corrupt = try DataCrypto.seal(Data("kein Paket".utf8), password: "passwort-1")
        let report = await RemoteSync.merge([corrupt], in: context, settings: try Self.makeSettings(), password: "passwort-1")
        #expect(report.devices == 0)
        #expect(report.problems == ["Eine Datei war unvollständig und wurde übersprungen."])
    }

    // MARK: Einstellungen

    @Test("Gleiche Werte setzen ändert den Zeitstempel nicht")
    func settingsUnchangedKeepStamp() throws {
        let settings = try Self.makeSettings()
        settings.values = settings.values
        #expect(settings.modifiedAt == .distantPast)
        settings.values.lessonDuration = 50
        #expect(settings.modifiedAt > .distantPast)
    }

    @Test("Übernommener Stand: älterer abgelehnt, neuerer behält seinen Zeitstempel")
    func settingsApplySynced() throws {
        let settings = try Self.makeSettings()
        var values = SchoolSettings.Values()
        values.lessonDuration = 90
        #expect(!settings.applySynced(SyncSettings(modifiedAt: .distantPast, values: values)))
        let stamp = Date(timeIntervalSince1970: 1_000)
        #expect(settings.applySynced(SyncSettings(modifiedAt: stamp, values: values)))
        #expect(settings.modifiedAt == stamp && settings.values.lessonDuration == 90)
    }

    @Test("Vor dem Sync gespeicherte Einstellungen gewinnen gegen ein frisches Gerät")
    func settingsWithoutStamp() throws {
        let defaults = try #require(UserDefaults(suiteName: "SyncSecurityTests.\(UUID())"))
        defaults.set(try JSONEncoder().encode(SchoolSettings.Values()), forKey: "school.settings")
        #expect(SchoolSettings(defaults: defaults).modifiedAt == Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test("Paket seit Zeitpunkt: Einstellungen nur, wenn danach geändert")
    func packageSettingsSince() throws {
        let context = try Self.makeContext()
        let settings = try Self.makeSettings()
        settings.values.lessonDuration = 60
        let later = settings.modifiedAt.addingTimeInterval(60)
        #expect(try SyncEngine.makePackage(since: later, in: context, settings: settings).settings == nil)
        #expect(try SyncEngine.makePackage(since: nil, in: context, settings: settings).settings?.values.lessonDuration == 60)
    }

    // MARK: Kollegen-Paket

    @Test("Paket öffnen: falsches Passwort fragt nach, richtiges ist bereit")
    func sharedPackageUnlock() async throws {
        let context = try Self.makeContext()
        context.insert(Student(firstName: "Mia", lastName: "Kraus"))
        try context.save()
        let package = try SyncEngine.sharePackage(in: context, settings: try Self.makeSettings())
        let file = try SyncEngine.encodeShare(package, password: "absender-passwort")
        #expect(try await SharedPackageImport.unlock(file, password: "anderes-passwort").package == nil)
        let ready = try await SharedPackageImport.unlock(file, password: "absender-passwort")
        #expect(ready.package?.entries.contains { $0.type == Student.syncRecordType } == true)
    }
}
