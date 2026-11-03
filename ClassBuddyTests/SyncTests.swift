import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

/// Zwei getrennte Datenbanken („Geräte“), die Pakete austauschen.
@Suite("Sync: Pakete schreiben und übernehmen")
@MainActor
struct SyncTests {
    private static let version = "1.0.0 (99)"

    init() {
        AppLanguage.current = .german
        SyncTracking.start()
    }

    /// Container festhalten: Ein Kontext ohne seinen Container stürzt beim nächsten Zugriff ab.
    private static var containers: [ModelContainer] = []

    private static func makeDevice() throws -> ModelContext {
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

    /// Paket über JSON (wie beim echten Weg zwischen Geräten) von `source` nach `target`.
    @discardableResult
    private static func sync(from source: ModelContext, to target: ModelContext, since: Date? = nil) throws -> SyncResult {
        let package = try SyncEngine.makePackage(since: since, in: source, appVersion: version)
        let data = try JSONEncoder().encode(package)
        return try SyncEngine.apply(JSONDecoder().decode(SyncPackage.self, from: data), in: target, appVersion: version)
    }

    @Test("Erster Abgleich überträgt alles samt Beziehungen")
    func firstSync() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        deviceA.insert(schoolClass)
        let student = Student(firstName: "Emma", lastName: "Schneider", photo: Data([1, 2, 3]), schoolClass: schoolClass)
        deviceA.insert(student)
        let room = Room(name: "R 204")
        deviceA.insert(room)
        let points = [GridPoint(0, 0), GridPoint(eighths: 12, 4), GridPoint(0, 2), GridPoint(0, 0)]
        let table = RoomElement(kind: .table, points: points, room: room)
        deviceA.insert(table)
        deviceA.insert(SeatAssignment(element: table, student: student))
        deviceA.insert(StudentObservation(subject: "Mathematik", kind: .rating, scale: .sevenStep, value: 2, student: student))
        try deviceA.save()

        let result = try Self.sync(from: deviceA, to: deviceB)
        #expect(result.inserted == 6)
        let copied = try #require(try deviceB.fetch(FetchDescriptor<Student>()).first)
        #expect(copied.id == student.id && copied.fullName == "Emma Schneider" && copied.photo == Data([1, 2, 3]))
        #expect(copied.schoolClass?.shortName == "7b")
        #expect(copied.observations.first?.value == 2)
        #expect(copied.seatAssignments.first?.element?.points == table.points)
        #expect(copied.lastModified == student.lastModified)
    }

    @Test("Neuerer Stand gewinnt, älterer bleibt liegen")
    func newerWins() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice()
        let student = Student(firstName: "Emma", lastName: "Schneider")
        deviceA.insert(student)
        try deviceA.save()
        try Self.sync(from: deviceA, to: deviceB)

        let copy = try #require(try deviceB.fetch(FetchDescriptor<Student>()).first)
        copy.notes = "von B"
        try deviceB.save()
        let changeOnB = copy.lastModified

        // A hat nichts Neueres: B behält seinen Stand; B nach A überträgt die Notiz.
        #expect(try Self.sync(from: deviceA, to: deviceB).keptLocal == 1)
        #expect(copy.notes == "von B")
        #expect(try Self.sync(from: deviceB, to: deviceA, since: student.lastModified).updated == 1)
        #expect(student.notes == "von B")
        #expect(student.lastModified == changeOnB)
    }

    @Test("Löschen kommt an und wird weitergereicht, eine spätere Änderung gewinnt gegen das Löschen")
    func deletions() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice(), deviceC = try Self.makeDevice()
        let first = Student(firstName: "Ben", lastName: "Adler")
        let second = Student(firstName: "Lea", lastName: "Adler")
        deviceA.insert(first)
        deviceA.insert(second)
        try deviceA.save()
        try Self.sync(from: deviceA, to: deviceB)
        try Self.sync(from: deviceA, to: deviceC)

        deviceA.delete(first)
        deviceA.delete(second)
        try deviceA.save()
        // Auf C wurde Lea danach noch geändert.
        let leaOnC = try #require(try deviceC.fetch(FetchDescriptor<Student>()).first { $0.firstName == "Lea" })
        leaOnC.notes = "noch da"
        try deviceC.save()

        #expect(try Self.sync(from: deviceA, to: deviceB).deleted == 2)
        #expect(try deviceB.fetch(FetchDescriptor<Student>()).isEmpty)
        // B reicht die Löschungen an C weiter; Lea bleibt dort, weil später geändert.
        #expect(try Self.sync(from: deviceB, to: deviceC).deleted == 1)
        #expect(try deviceC.fetch(FetchDescriptor<Student>()).map(\.firstName) == ["Lea"])
        // Lea kommt mit ihrem neueren Stand auf B zurück, Ben bleibt gelöscht.
        try Self.sync(from: deviceC, to: deviceB)
        #expect(try deviceB.fetch(FetchDescriptor<Student>()).map(\.firstName) == ["Lea"])
    }

    @Test("Übernehmen stempelt nicht neu und hinterlässt keine eigenen Löschungen")
    func applyKeepsTimestamps() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice()
        let schoolClass = SchoolClass(shortName: "5a")
        deviceA.insert(schoolClass)
        try deviceA.save()
        try Self.sync(from: deviceA, to: deviceB)
        let copy = try #require(try deviceB.fetch(FetchDescriptor<SchoolClass>()).first)
        #expect(copy.lastModified == schoolClass.lastModified)
        // Nichts Neues seit dem letzten Stand von A: leeres Paket.
        let package = try SyncEngine.makePackage(since: schoolClass.lastModified, in: deviceB, appVersion: Self.version)
        #expect(package.entries.isEmpty && package.deletions.isEmpty)
    }

    @Test("Abgleich über das Manifest: nur Fehlendes und Neueres, in beide Richtungen und über ein drittes Gerät")
    func manifestExchange() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice(), deviceC = try Self.makeDevice()
        func exchange(_ first: ModelContext, _ second: ModelContext) throws {
            let toSecond = try SyncEngine.makePackage(for: SyncEngine.manifest(in: second), in: first, appVersion: Self.version)
            let toFirst = try SyncEngine.makePackage(for: SyncEngine.manifest(in: first), in: second, appVersion: Self.version)
            try SyncEngine.apply(toSecond, in: second, appVersion: Self.version)
            try SyncEngine.apply(toFirst, in: first, appVersion: Self.version)
        }
        deviceA.insert(Student(firstName: "Emma", lastName: "A"))
        try deviceA.save()
        deviceB.insert(Student(firstName: "Ben", lastName: "B"))
        try deviceB.save()
        try exchange(deviceA, deviceB)
        #expect(Set(try deviceA.fetch(FetchDescriptor<Student>()).map(\.firstName)) == ["Emma", "Ben"])
        #expect(Set(try deviceB.fetch(FetchDescriptor<Student>()).map(\.firstName)) == ["Emma", "Ben"])
        // Nichts mehr offen: das nächste Paket ist leer.
        let empty = try SyncEngine.makePackage(for: SyncEngine.manifest(in: deviceB), in: deviceA, appVersion: Self.version)
        #expect(empty.entries.isEmpty && empty.deletions.isEmpty)

        // B gibt beides an C weiter, obwohl C nie mit A verbunden war.
        try exchange(deviceB, deviceC)
        #expect(Set(try deviceC.fetch(FetchDescriptor<Student>()).map(\.firstName)) == ["Emma", "Ben"])
        // Eine Löschung auf C kommt über B bei A an.
        let emmaOnC = try #require(try deviceC.fetch(FetchDescriptor<Student>()).first { $0.firstName == "Emma" })
        deviceC.delete(emmaOnC)
        try deviceC.save()
        try exchange(deviceC, deviceB)
        try exchange(deviceB, deviceA)
        #expect(try deviceA.fetch(FetchDescriptor<Student>()).map(\.firstName) == ["Ben"])
    }

    @Test("Kopplungscode: Text hin und zurück, fremde oder kaputte Codes werden abgelehnt")
    func pairingCode() throws {
        let code = PairingCode.make(name: "iPad von Dominic")
        #expect(code.secret.count == 32)
        #expect(PairingCode(text: code.text) == code)
        #expect(PairingCode(text: "https://example.com") == nil)
        #expect(PairingCode(text: "classbuddy-pair:kaputt") == nil)
        let weak = PairingCode(id: UUID().uuidString, secret: Data([1, 2, 3]), name: "x")
        #expect(PairingCode(text: weak.text) == nil)
    }

    @Test("Einstellungen: der neuere Stand kommt als Ganzes an, der ältere bleibt liegen")
    func settingsSync() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice()
        let settingsA = SchoolSettings(defaults: try #require(UserDefaults(suiteName: "SyncTests.A.\(UUID())")))
        let settingsB = SchoolSettings(defaults: try #require(UserDefaults(suiteName: "SyncTests.B.\(UUID())")))
        settingsA.values.lessonDuration = 60
        settingsA.values.teacher.firstName = "Dominic"

        func exchange() throws -> SyncResult {
            let toB = try SyncEngine.makePackage(
                for: SyncEngine.manifest(in: deviceB, settings: settingsB), in: deviceA, settings: settingsA, appVersion: Self.version
            )
            return try SyncEngine.apply(toB, in: deviceB, settings: settingsB, appVersion: Self.version)
        }
        #expect(try exchange().settingsUpdated)
        #expect(settingsB.values == settingsA.values && settingsB.modifiedAt == settingsA.modifiedAt)
        // Nichts Neues: kein Einstellungs-Eintrag mehr im Paket.
        let empty = try SyncEngine.makePackage(
            for: SyncEngine.manifest(in: deviceB, settings: settingsB), in: deviceA, settings: settingsA, appVersion: Self.version
        )
        #expect(empty.settings == nil)

        // B ändert danach: A schickt seinen älteren Stand, B behält seinen.
        settingsB.values.lessonDuration = 45
        let stale = try SyncEngine.makePackage(since: nil, in: deviceA, settings: settingsA, appVersion: Self.version)
        #expect(try !SyncEngine.apply(stale, in: deviceB, settings: settingsB, appVersion: Self.version).settingsUpdated)
        #expect(settingsB.values.lessonDuration == 45)
    }

    @Test("Teilen an Kollegen: ersetzt alle Daten, Profil bleibt, Löschungen gehen an eigene Geräte")
    func shareReplacesEverything() throws {
        let colleague = try Self.makeDevice(), receiver = try Self.makeDevice(), receiverPad = try Self.makeDevice()
        let colleagueSettings = SchoolSettings(defaults: try #require(UserDefaults(suiteName: "SyncTests.C.\(UUID())")))
        let receiverSettings = SchoolSettings(defaults: try #require(UserDefaults(suiteName: "SyncTests.R.\(UUID())")))
        colleagueSettings.values.lessonDuration = 60
        colleagueSettings.values.teacher.firstName = "Kollegin"
        receiverSettings.values.teacher.firstName = "Dominic"

        let shared = SchoolClass(shortName: "9c")
        colleague.insert(shared)
        colleague.insert(Student(firstName: "Mia", lastName: "Kraus", schoolClass: shared))
        try colleague.save()
        receiver.insert(Student(firstName: "Ben", lastName: "Alt"))
        try receiver.save()
        try Self.sync(from: receiver, to: receiverPad)

        let package = try SyncEngine.sharePackage(in: colleague, settings: colleagueSettings, appVersion: Self.version)
        #expect(package.settings?.values.teacher.firstName == "")
        let file = try SyncEngine.encodeShare(package, password: "kollegin-passwort")
        #expect(throws: DataCrypto.CryptoError.wrongPassword) { try SyncEngine.decodeShare(file, password: "falsch-falsch") }
        let decoded = try SyncEngine.decodeShare(file, password: "kollegin-passwort")
        try SyncEngine.replaceAll(
            with: decoded, in: receiver, settings: receiverSettings, replacesSettings: true, appVersion: Self.version
        )
        #expect(try receiver.fetch(FetchDescriptor<Student>()).map(\.firstName) == ["Mia"])
        #expect(try receiver.fetch(FetchDescriptor<Student>()).first?.schoolClass?.shortName == "9c")
        #expect(receiverSettings.values.lessonDuration == 60 && receiverSettings.values.teacher.firstName == "Dominic")

        // Das eigene iPad übernimmt beim nächsten Abgleich: Ben gelöscht, Mia neu.
        try Self.sync(from: receiver, to: receiverPad)
        #expect(try receiverPad.fetch(FetchDescriptor<Student>()).map(\.firstName) == ["Mia"])

        // Ein zweites Mal dasselbe Paket: frische Löschungen blockieren die gleichen Einträge nicht.
        try SyncEngine.replaceAll(
            with: decoded, in: receiver, settings: receiverSettings, replacesSettings: false, appVersion: Self.version
        )
        #expect(try receiver.fetch(FetchDescriptor<Student>()).map(\.firstName) == ["Mia"])
        #expect(throws: SyncError.unreadableShare) { try SyncEngine.decodeShare(Data("kaputt".utf8), password: "egal-egal") }
    }

    @Test("Daten-Passwort: verschlüsseln, falsches Passwort, lokaler Schlüssel hängt am Passwort")
    func dataPassword() throws {
        let password = DataPassword.generate()
        #expect(password.count == 23 && DataPassword.isValid(password))
        #expect(!DataPassword.isValid("kurz"))
        let sealed = try DataCrypto.seal(Data("Emma".utf8), password: password)
        #expect(DataCrypto.isSealed(sealed) && !sealed.contains(Data("Emma".utf8)))
        #expect(try DataCrypto.open(sealed, password: password) == Data("Emma".utf8))
        #expect(throws: DataCrypto.CryptoError.wrongPassword) { try DataCrypto.open(sealed, password: password + "x") }
        let secret = Data(repeating: 7, count: 32)
        let key = LocalSyncService.sessionKey(secret: secret, password: "a-passwort")
        #expect(key == LocalSyncService.sessionKey(secret: secret, password: "a-passwort"))
        #expect(key != LocalSyncService.sessionKey(secret: secret, password: "b-passwort"))
        let code = PairingCode(id: UUID().uuidString, secret: secret, name: "iPad", password: password)
        #expect(PairingCode(text: code.text)?.password == password)
    }

    @Test("Cloud-Ordner und iCloud: eine verschlüsselte Datei je Gerät, Zusammenführen, falsches Passwort meldet sich")
    func remoteFiles() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice()
        let settings = SchoolSettings(defaults: try #require(UserDefaults(suiteName: "SyncTests.F.\(UUID())")))
        deviceA.insert(Student(firstName: "Emma", lastName: "A"))
        try deviceA.save()
        deviceB.insert(Student(firstName: "Ben", lastName: "B"))
        try deviceB.save()

        // Fremde Geräte-ID simulieren: Paket von B mit anderer Kennung.
        var packageB = try SyncEngine.makePackage(since: nil, in: deviceB, appVersion: AppInfo.version)
        packageB.deviceID = "anderes-geraet"
        let fileB = try DataCrypto.seal(JSONEncoder().encode(packageB), password: "gemeinsam-123")
        let report = RemoteSync.merge([fileB], in: deviceA, settings: settings, password: "gemeinsam-123")
        #expect(report.devices == 1 && report.result.inserted == 1 && report.problems.isEmpty)
        #expect(Set(try deviceA.fetch(FetchDescriptor<Student>()).map(\.firstName)) == ["Emma", "Ben"])

        let wrong = RemoteSync.merge([fileB], in: deviceA, settings: settings, password: "anderes-passwort")
        #expect(wrong.devices == 0 && wrong.problems.count == 1)
        // Eigene Datei wird übersprungen.
        let own = try RemoteSync.ownFile(in: deviceA, settings: settings, deviceName: "iPad", password: "gemeinsam-123")
        #expect(RemoteSync.merge([own], in: deviceA, settings: settings, password: "gemeinsam-123").devices == 0)
        // Fingerabdruck ändert sich nur mit dem Stand oder dem Passwort.
        let first = try RemoteSync.fingerprint(in: deviceA, settings: settings, password: "gemeinsam-123")
        #expect(try RemoteSync.fingerprint(in: deviceA, settings: settings, password: "gemeinsam-123") == first)
        #expect(try RemoteSync.fingerprint(in: deviceA, settings: settings, password: "neues-passwort") != first)
    }

    @Test("Excel-Verschlüsselung: Agile Encryption hin und zurück, falsches Passwort, große Datei")
    func officeEncryption() throws {
        let xlsx = XLSX.write([XLSXSheet(name: "Klassen", rows: [["Kürzel"], ["7b"], ["9c"]])])
        let encrypted = try OfficeEncryption.encrypt(xlsx, password: "Lehrer-Passwort 1")
        #expect(OfficeEncryption.isEncrypted(encrypted) && !OfficeEncryption.isEncrypted(xlsx))
        #expect(try OfficeEncryption.decrypt(encrypted, password: "Lehrer-Passwort 1") == xlsx)
        #expect(throws: OfficeEncryption.OfficeError.wrongPassword) {
            try OfficeEncryption.decrypt(encrypted, password: "lehrer-passwort 1")
        }
        // Über 7 MB: braucht DIFAT-Sektoren.
        let large = Data((0..<8_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        #expect(try OfficeEncryption.decrypt(OfficeEncryption.encrypt(large, password: "x"), password: "x") == large)
    }

    @Test("Andere App-Version wird abgelehnt")
    func versionMismatch() throws {
        let deviceA = try Self.makeDevice(), deviceB = try Self.makeDevice()
        let package = try SyncEngine.makePackage(since: nil, in: deviceA, appVersion: "1.0.0 (11)")
        #expect(throws: SyncError.versionMismatch(remote: "1.0.0 (11)", local: Self.version)) {
            try SyncEngine.apply(package, in: deviceB, appVersion: Self.version)
        }
    }
}
