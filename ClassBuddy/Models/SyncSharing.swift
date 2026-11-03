import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Teilen an Kollegen: alle Daten samt Kachel-Dateien und Schuleinstellungen (ohne Profil der Lehrkraft) als eine
/// `.classbuddy`-Datei, verschlüsselt mit dem Daten-Passwort. Der Empfänger gibt bei anderem Passwort das des
/// Absenders ein, bestätigt und ersetzt damit alle seine Daten; kein Zusammenführen.
nonisolated extension UTType {
    static let classBuddyPackage = UTType(exportedAs: "de.devsforge.classbuddy.package", conformingTo: .data)
}

extension SyncEngine {
    /// Gesamtpaket zum Weitergeben: keine Löschungen, kein Profil (Name, Foto) der Lehrkraft.
    static func sharePackage(
        in context: ModelContext, settings: SchoolSettings, appVersion: String = AppInfo.version
    ) throws -> SyncPackage {
        var package = try makePackage(since: nil, in: context, appVersion: appVersion)
        package.deletions = []
        var values = settings.values
        values.teacher = TeacherProfile()
        package.settings = SyncSettings(modifiedAt: .now, values: values)
        return package
    }

    /// Mit dem Daten-Passwort verschlüsselt; der Empfänger braucht das Passwort (getrennt weitergeben).
    static func encodeShare(_ package: SyncPackage, password: String = DataPassword.current) throws -> Data {
        try DataCrypto.seal(JSONEncoder().encode(package), password: password)
    }

    /// Wirft `DataCrypto.CryptoError.wrongPassword`, wenn das Passwort nicht passt.
    static func decodeShare(_ data: Data, password: String = DataPassword.current) throws -> SyncPackage {
        guard DataCrypto.isSealed(data) else { throw SyncError.unreadableShare }
        let json = try DataCrypto.open(data, password: password)
        do {
            return try JSONDecoder().decode(SyncPackage.self, from: json)
        } catch {
            throw SyncError.unreadableShare
        }
    }

    /// Alle Daten durch das Paket ersetzen. Die Löschungen werden festgehalten, damit gekoppelte eigene Geräte beim
    /// nächsten Abgleich ebenfalls ersetzen statt die alten Daten zurückzubringen.
    /// Schuleinstellungen nur mit `replacesSettings`; das eigene Profil bleibt immer.
    @discardableResult
    static func replaceAll(
        with package: SyncPackage, in context: ModelContext, settings: SchoolSettings, replacesSettings: Bool,
        appVersion: String = AppInfo.version
    ) throws -> SyncResult {
        try validate(package, appVersion: appVersion)
        try LocalDataStore.deleteRecords(in: context)
        // Kamen Einträge früher von hier, hätten ihre frischen Löschungen Vorrang: diese wieder entfernen.
        let incoming = Set(package.entries.map { SyncManifest.key($0.type, $0.id) })
        for deletion in try context.fetch(FetchDescriptor<DeletedRecord>())
        where incoming.contains(SyncManifest.key(deletion.recordType, deletion.recordID)) {
            context.delete(deletion)
        }
        try context.save()

        var contents = package
        contents.deletions = []
        contents.settings = nil
        let result = try apply(contents, in: context, appVersion: appVersion)
        if replacesSettings, var values = package.settings?.values {
            values.teacher = settings.values.teacher
            settings.values = values
        }
        return result
    }
}

/// `.classbuddy`-Datei für das Teilen-Menü (AirDrop, Mail, Dateien).
struct SharedPackageFile: Identifiable {
    let id = UUID()
    let url: URL

    /// Schreibt das Paket in den temporären Ordner, Name mit Datum.
    static func write(_ data: Data) throws -> SharedPackageFile {
        let name = "ClassBuddy-\(Date.now.formatted(.iso8601.year().month().day())).classbuddy"
        let directory = FileManager.default.temporaryDirectory.appending(path: "Share", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try data.write(to: url, options: .completeFileProtection)
        return SharedPackageFile(url: url)
    }
}

/// Empfangenes Paket, wartet auf Bestätigung (aus „Öffnen“ in Daten & Sync oder über AirDrop/Dateien geöffnet).
/// `locked`: mit einem anderen Daten-Passwort verschlüsselt, das Passwort wird zuerst abgefragt.
enum PendingSharedPackage: Identifiable {
    case ready(SyncPackage)
    case locked(Data)

    var id: String {
        switch self {
        case .ready(let package): "ready-\(package.deviceID)-\(package.createdAt.timeIntervalSince1970)"
        case .locked(let data): "locked-\(data.count)-\(data.hashValue)"
        }
    }

    var package: SyncPackage? {
        if case .ready(let package) = self { return package }
        return nil
    }
}

/// Teilen-Menü des Systems (AirDrop, Mail, In Dateien sichern).
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Bestätigung für ein empfangenes Kollegen-Paket (aus „Paket öffnen“ oder über AirDrop/Dateien geöffnet).
/// Liegt an der Wurzel der App, damit sie auch beim Öffnen von außen erscheint.
struct SharedPackageImport: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts

    @State private var enteredPassword = ""

    static func load(_ url: URL) throws -> PendingSharedPackage {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try unlock(Data(contentsOf: url), password: DataPassword.current)
    }

    static func unlock(_ data: Data, password: String) throws -> PendingSharedPackage {
        do {
            let package = try SyncEngine.decodeShare(data, password: password)
            try SyncEngine.validate(package, appVersion: AppInfo.version)
            return .ready(package)
        } catch DataCrypto.CryptoError.wrongPassword {
            return .locked(data)
        }
    }

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                guard url.isFileURL else { return }
                do {
                    app.pendingSharedPackage = try Self.load(url)
                } catch {
                    toasts.error(error.localizedDescription)
                }
            }
            .alert("Passwort des Pakets", isPresented: lockedBinding) {
                SecureField("Daten-Passwort", text: $enteredPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Öffnen") { unlockEntered() }
                Button("Abbrechen", role: .cancel) { enteredPassword = "" }
            } message: {
                Text(loc("""
                    Das Paket ist mit einem anderen Daten-Passwort geschützt. Bitte das Passwort der Person eingeben, \
                    die es weitergegeben hat.
                    """))
            }
            .confirmationDialog(
                "Paket übernehmen?",
                isPresented: Binding(
                    get: { app.pendingSharedPackage?.package != nil && !security.isLocked },
                    set: { if !$0 { app.pendingSharedPackage = nil } }
                ),
                titleVisibility: .visible,
                presenting: app.pendingSharedPackage?.package
            ) { package in
                Button("Daten und Schuleinstellungen ersetzen", role: .destructive) {
                    Task { await replace(with: package, replacesSettings: true) }
                }
                Button("Nur Daten ersetzen", role: .destructive) {
                    Task { await replace(with: package, replacesSettings: false) }
                }
            } message: { package in
                Text(message(for: package))
            }
    }

    private var lockedBinding: Binding<Bool> {
        Binding(
            get: {
                if case .locked = app.pendingSharedPackage { return !security.isLocked }
                return false
            },
            set: { if !$0, case .locked = app.pendingSharedPackage { app.pendingSharedPackage = nil } }
        )
    }

    private func unlockEntered() {
        guard case .locked(let data) = app.pendingSharedPackage else { return }
        let password = enteredPassword
        enteredPassword = ""
        do {
            let unlocked = try Self.unlock(data, password: password)
            if case .locked = unlocked {
                toasts.error(DataCrypto.CryptoError.wrongPassword.localizedDescription)
                app.pendingSharedPackage = nil
            } else {
                // Nach dem Schließen der Abfrage, sonst erscheint die Bestätigung nicht.
                app.pendingSharedPackage = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    app.pendingSharedPackage = unlocked
                }
            }
        } catch {
            app.pendingSharedPackage = nil
            toasts.error(error.localizedDescription)
        }
    }

    private func message(for package: SyncPackage) -> String {
        let classes = package.entries.count { $0.type == SchoolClass.syncRecordType }
        let students = package.entries.count { $0.type == Student.syncRecordType }
        return loc("""
            Das Paket enthält \(classes) Klassen mit \(students) Schülern. Alle Daten auf diesem Gerät werden ersetzt, \
            gekoppelte Geräte übernehmen das beim nächsten Abgleich. Ihr Profil bleibt.
            """)
    }

    private func replace(with package: SyncPackage, replacesSettings: Bool) async {
        app.pendingSharedPackage = nil
        guard await security.confirmDestructiveAction(reason: loc("Daten durch das Paket ersetzen")) else { return }
        do {
            let result = try SyncEngine.replaceAll(
                with: package, in: modelContext, settings: settings, replacesSettings: replacesSettings
            )
            SubjectSettings.migrate(school: settings.values, in: modelContext)
            let classIDs = try modelContext.fetch(FetchDescriptor<SchoolClass>()).map(\.id)
            if app.selectedClassID.map({ !classIDs.contains($0) }) ?? true {
                app.selectedClassID = classIDs.first
            }
            app.calendarFocusClassID = nil
            toasts.success(loc("Paket übernommen: \(result.inserted) Einträge."))
        } catch {
            modelContext.rollback()
            toasts.error(loc("Übernehmen fehlgeschlagen: \(error.localizedDescription)"))
        }
    }
}
