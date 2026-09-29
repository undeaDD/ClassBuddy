import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Erscheinungsbild der App (überschreibt die Systemeinstellung).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    static let storageKey = "app.appearance"

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Setzt den Stil direkt an den Fenstern – wirkt sofort, auch auf Sheets/Popover,
    /// und „System“ greift zuverlässig wieder.
    func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

/// Einstellungen → App-Einstellungen: Darstellung, App-Sperre, lokale Daten.
struct AppSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    @State private var dataSize: Int64?
    @State private var isDeleteConfirmationPresented = false
    @State private var deleteMessage: String?
    @State private var exportFile: SpreadsheetFile?
    @State private var isExporterPresented = false
    @State private var isImporterPresented = false
    @State private var pendingImport: Data?
    @State private var transferMessage: String?

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { security.isAppLockEnabled },
            set: { newValue in Task { await security.setAppLockEnabled(newValue) } }
        )
    }

    var body: some View {
        Form {
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle(isOn: appLockBinding) {
                    Label("Mit \(security.biometryName) sperren", image: .fingerprintLockCircle)
                }
                .disabled(security.isAuthenticating)
            } header: {
                Text("App-Sperre")
            } footer: {
                Text("Sperrt die App beim Start und beim Wechsel in den Hintergrund. Ausschalten erfordert \(security.biometryName).")
            }

            Section {
                Button("Exportieren (Excel)", systemImage: "square.and.arrow.up", action: export)
                Button("Importieren (Excel)", image: .cloudDownload) {
                    isImporterPresented = true
                }
            } header: {
                Text("Export & Import")
            } footer: {
                Text(transferMessage ?? "Eine .xlsx-Datei mit einem Blatt je Bereich: Klassen, Schüler, Stunden, Termine, Kacheln, Ferien, Schule, Schultag, Pausen, Profil, App. In Excel/Numbers bearbeitbar. Ein Import ersetzt alle Daten. Dokumente (Dateien) sind nicht enthalten.")
            }
            .disabled(security.isPrivacyModeOn)

            Section {
                LabeledContent("Belegter Speicher") {
                    if let dataSize {
                        Text(dataSize.formatted(.byteCount(style: .file)))
                    } else {
                        ProgressView()
                    }
                }
                Button("Alle lokalen Daten löschen", image: .trash, role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
                .disabled(security.isPrivacyModeOn)
            } header: {
                Text("Daten")
            } footer: {
                Text(deleteMessage ?? "Löscht Klassen, Schüler, Stunden, Termine, Ferien, Kacheln und Dokumente sowie Profil- und Schuleinstellungen. App-Sperre und Darstellung bleiben erhalten.")
            }
        }
        .navigationTitle("App-Einstellungen")
        .task { await refreshDataSize() }
        .confirmationDialog(
            "Alle lokalen Daten löschen?",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Alles löschen", role: .destructive) {
                Task { await deleteAllData() }
            }
        } message: {
            Text("Das kann nicht rückgängig gemacht werden. Exportiere vorher, was du behalten möchtest.")
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportFile,
            contentType: .xlsx,
            defaultFilename: "ClassBuddy-Export-\(Date.now.formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result {
                transferMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
            } else {
                transferMessage = "Export gespeichert."
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.xlsx]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                pendingImport = try Data(contentsOf: url)
            } catch {
                transferMessage = "Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Daten importieren?",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            titleVisibility: .visible
        ) {
            Button("Importieren und ersetzen", role: .destructive) {
                let data = pendingImport
                Task { await importData(data) }
            }
        } message: {
            Text("Alle vorhandenen Klassen, Schüler, Stunden, Termine, Kacheln und Ferien werden durch den Inhalt der Datei ersetzt.")
        }
    }

    private func export() {
        do {
            let data = try Backup.export(context: modelContext, settings: settings.values, appearance: appearance)
            exportFile = SpreadsheetFile(data: data)
            isExporterPresented = true
        } catch {
            transferMessage = "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func importData(_ data: Data?) async {
        pendingImport = nil
        guard let data, await security.confirmDestructiveAction(reason: "Daten importieren und ersetzen") else { return }
        do {
            let result = try Backup.import(data, context: modelContext, currentSettings: settings.values)
            settings.values = result.settings.values
            if let imported = result.settings.appearance { appearance = imported }
            // Ausgewählte Klasse behalten, wenn es sie noch gibt.
            let classIDs = try modelContext.fetch(FetchDescriptor<SchoolClass>()).map(\.id)
            if let selected = app.selectedClassID, !classIDs.contains(selected) {
                app.selectedClassID = classIDs.first
            }
            app.calendarFocusClassID = nil
            transferMessage = result.summary.text
        } catch {
            modelContext.rollback()
            transferMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
        await refreshDataSize()
    }

    private func refreshDataSize() async {
        dataSize = await Task.detached { LocalDataStore.totalSize() }.value
    }

    private func deleteAllData() async {
        guard await security.confirmDestructiveAction(reason: "Alle lokalen Daten löschen") else { return }
        do {
            try LocalDataStore.deleteAll(in: modelContext)
            settings.values = SchoolSettings.Values()
            app.selectedClassID = nil
            app.calendarFocusClassID = nil
            UserDefaults.standard.removeObject(forKey: AppTabView.customizationKey)
            deleteMessage = "Alle lokalen Daten wurden gelöscht."
        } catch {
            deleteMessage = "Löschen fehlgeschlagen: \(error.localizedDescription)"
        }
        await refreshDataSize()
    }
}

/// Lokale Ablage der App (SwiftData-Store + Dokumente in Application Support).
enum LocalDataStore {
    /// Gesamtgröße aller Dateien in Application Support.
    nonisolated static func totalSize() -> Int64 {
        let root = URL.applicationSupportDirectory
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Löscht alle Datensätze und kopierten Dokumente.
    static func deleteAll(in context: ModelContext) throws {
        try context.delete(model: Student.self)
        try context.delete(model: Lesson.self)
        try context.delete(model: DashboardLink.self)
        try context.delete(model: CalendarEntry.self)
        try context.delete(model: Holiday.self)
        try context.delete(model: SchoolClass.self)
        try context.save()
        try? FileManager.default.removeItem(at: LinkFileStore.directory)
        FaviconStore.removeAll()
    }
}

nonisolated extension UTType {
    static let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
}

/// .xlsx-Datei für den Export-Dialog („Sichern in Dateien“).
nonisolated struct SpreadsheetFile: FileDocument {
    static let readableContentTypes: [UTType] = [.xlsx]
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
