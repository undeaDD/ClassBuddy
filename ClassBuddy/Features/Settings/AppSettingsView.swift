import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Erscheinungsbild der App (überschreibt die Systemeinstellung).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    static let storageKey = "app.appearance"

    /// Wert im Excel-Backup (immer Deutsch, unabhängig von der App-Sprache).
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    /// Anzeige in der App-Sprache.
    var displayTitle: String {
        switch self {
        case .system: loc("System")
        case .light: loc("Hell")
        case .dark: loc("Dunkel")
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

/// Schalter der App-Einstellungen (UserDefaults, gelten nur auf diesem Gerät).
enum AppPreference {
    /// iPhone-Tab-Leiste nur mit Icons.
    static let hidesTabLabels = "app.hidesTabLabels"
    /// Bildschirm bleibt an, solange die App im Vordergrund ist.
    static let keepsScreenAwake = "app.keepsScreenAwake"
    /// Tab-Leiste beim Runterscrollen verkleinern (Standard: an). Die Navigationsleiste nicht mehr, siehe `AppChromeModifier`.
    static let minimizesBarsOnScroll = "app.minimizesBarsOnScroll"
    /// Leichtes Vibrieren bei Taps, Klassenwechsel und Meldungen (Standard: aus).
    static let hapticFeedback = "app.hapticFeedback"
    /// Tab beim App-Start (Standard: Übersicht).
    static let startTab = "app.startTab"
    /// Timer-Ende nur mit Vibration statt Ton (nur iPhone, Standard: aus).
    static let timerVibratesOnly = "app.timerVibratesOnly"
    /// iPad: Tab-Leiste wie auf dem iPhone statt oben zentrierter Leiste mit Sidebar (Standard: aus).
    static let padUsesPhoneTabBar = "app.padUsesPhoneTabBar"
    /// Tipps für neue Nutzer (TipKit, Standard: an).
    static let showsTips = "app.showsTips"
    /// Schuleinstellungen mindestens einmal geöffnet (Einrichtungs-Tipp „Stundenraster und Pausen“).
    static let hasOpenedSchoolSettings = "app.hasOpenedSchoolSettings"
}

/// Einstellungen → App-Einstellungen: Darstellung, App-Sperre, lokale Daten.
struct AppSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(AppPreference.hidesTabLabels) private var hidesTabLabels = false
    @AppStorage(AppPreference.keepsScreenAwake) private var keepsScreenAwake = false
    @AppStorage(AppPreference.minimizesBarsOnScroll) private var minimizesBarsOnScroll = true
    @AppStorage(AppPreference.hapticFeedback) private var hapticFeedback = false
    @AppStorage(AppPreference.startTab) private var startTab: AppTab = .dashboard
    @AppStorage(AppPreference.timerVibratesOnly) private var timerVibratesOnly = false
    @AppStorage(AppPreference.padUsesPhoneTabBar) private var padUsesPhoneTabBar = false
    @AppStorage(AppPreference.showsTips) private var showsTips = true
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppAccent.storageKey) private var accent = AppAccent.defaultValue

    /// Erst `loc` umstellen, dann – nach dem Schließen des Menüs – speichern: Das baut die ganze
    /// Oberfläche neu auf (`.id` an der Wurzel), was bei noch offenem Menü hängen kann.
    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { language },
            set: { newValue in
                AppLanguage.current = newValue
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    language = newValue
                }
            }
        )
    }

    @State private var dataSize: Int64?
    @State private var isDeleteConfirmationPresented = false
    @State private var exportFile: SpreadsheetFile?
    @State private var isExporterPresented = false
    @State private var isImporterPresented = false
    @State private var pendingImport: Data?

    private static var deleteInfo: String {
        loc("Löscht alle Inhalte und Einstellungen. App-Sperre und Darstellung bleiben.")
    }

    private static var transferInfo: String {
        loc("Excel-Datei, bearbeitbar in Excel oder Numbers. Ein Import ersetzt alle Daten; Dokumente und Fotos fehlen.")
    }

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { security.isAppLockEnabled },
            set: { newValue in Task { await security.setAppLockEnabled(newValue) } }
        )
    }

    private var appearanceFooter: String {
        guard #available(iOS 26, *) else {
            return loc("UI Minimieren verkleinert die Tab-Leiste beim Scrollen.")
        }
        return UIDevice.current.userInterfaceIdiom == .pad
            ? loc("""
                Tab-Titel gibt es nur in der iPhone-Tab-Leiste. UI Minimieren verkleinert sie beim Scrollen. \
                Die iPhone-Tab-Leiste ersetzt die Leiste oben und die Seitenleiste.
                """)
            : loc("Tab-Titel gibt es nur auf dem iPhone. UI Minimieren verkleinert die Tab-Leiste beim Scrollen.")
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.title).tag(option)
                    }
                } label: {
                    Label("Sprache", icon: .translate)
                }
                .pickerStyle(.menu)
                Picker(selection: $startTab) {
                    ForEach(AppTab.startTabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                } label: {
                    Label("Start-Tab", symbol: AppTab.dashboard.symbol)
                }
                .pickerStyle(.menu)
                Toggle(isOn: $hapticFeedback) {
                    Label("Haptisches Feedback", icon: .sineWave)
                }
                // iPads können nicht vibrieren.
                if UIDevice.current.userInterfaceIdiom == .phone {
                    Toggle(isOn: $timerVibratesOnly) {
                        Label("Timer nur vibrieren", icon: .timer)
                    }
                }
                Toggle(isOn: $keepsScreenAwake) {
                    Label("Bildschirm wach halten", icon: .lockSlash)
                }
                Toggle(isOn: $showsTips) {
                    Label("Tipps anzeigen", icon: .helpCircle)
                }
            } header: {
                Text("Allgemein")
            } footer: {
                Text("Wach halten gilt, solange die App geöffnet ist.")
            }

            Section {
                Picker(selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.displayTitle).tag(option)
                    }
                } label: {
                    Label("Erscheinungsbild", icon: .palette)
                }
                .pickerStyle(.menu)
                AccentColorRow(selection: $accent)
                Toggle(isOn: $hidesTabLabels) {
                    Label("Tab-Titel ausblenden", icon: .label)
                }
                Toggle(isOn: $minimizesBarsOnScroll) {
                    Label("UI Minimieren", icon: .swipeLeftGesture)
                }
                // Vor iOS 26 gibt es auf dem iPad ohnehin nur die Tab-Leiste unten (`FloatingTabView`).
                if #available(iOS 26, *), UIDevice.current.userInterfaceIdiom == .pad {
                    Toggle(isOn: $padUsesPhoneTabBar) {
                        Label("iPhone-Tab-Leiste", icon: .bottomTabs)
                    }
                }
            } header: {
                Text("Darstellung")
            } footer: {
                Text(appearanceFooter)
            }

            IconThemeSection()

            Section {
                Toggle(isOn: appLockBinding) {
                    Label("Mit \(security.biometryName) sperren", icon: .fingerprintLockCircle)
                }
                .disabled(security.isAuthenticating)
            } header: {
                Text("App-Sperre")
            } footer: {
                Text("Beim Start und im Hintergrund. Ausschalten erfordert \(security.biometryName).")
            }

            Section {
                Button(action: export) {
                    SettingsActionLabel(title: loc("Exportieren"), icon: .shareIos)
                }
                Button {
                    isImporterPresented = true
                } label: {
                    SettingsActionLabel(title: loc("Importieren"), icon: .import)
                }
            } header: {
                Text("Export & Import")
            } footer: {
                Text(Self.transferInfo)
            }
            .disabled(security.isPrivacyModeOn)

            Section {
                LabeledContent {
                    if let dataSize {
                        Text(dataSize.formatted(.byteCount(style: .file)))
                    } else {
                        ProgressView()
                    }
                } label: {
                    Label("Belegter Speicher", icon: .data)
                }
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    SettingsActionLabel(title: loc("Alle lokalen Daten löschen"), icon: .trash, isDestructive: true)
                }
                .disabled(security.isPrivacyModeOn)
            } header: {
                Text("Daten")
            } footer: {
                Text(Self.deleteInfo)
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
            Text("Das kann nicht rückgängig gemacht werden. Exportieren Sie vorher, was Sie behalten möchten.")
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportFile,
            contentType: .xlsx,
            defaultFilename: "ClassBuddy-Export-\(Date.now.formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result {
                toasts.error(loc("Export fehlgeschlagen: \(error.localizedDescription)"))
            } else {
                toasts.success(loc("Export gespeichert"))
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.xlsx]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                pendingImport = try Data(contentsOf: url)
            } catch {
                toasts.error(loc("Datei konnte nicht gelesen werden: \(error.localizedDescription)"))
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
            Text("Alle Klassen, Schüler, Stunden, Termine, Kacheln, Ferien und Räume werden durch den Inhalt der Datei ersetzt.")
        }
    }

    private func export() {
        do {
            let data = try Backup.export(context: modelContext, settings: settings.values, appearance: appearance)
            exportFile = SpreadsheetFile(data: data)
            isExporterPresented = true
        } catch {
            toasts.error(loc("Export fehlgeschlagen: \(error.localizedDescription)"))
        }
    }

    private func importData(_ data: Data?) async {
        pendingImport = nil
        guard let data, await security.confirmDestructiveAction(reason: loc("Daten importieren und ersetzen")) else { return }
        do {
            let result = try Backup.import(data, context: modelContext, currentSettings: settings.values)
            settings.values = result.settings.values
            if let imported = result.settings.appearance { appearance = imported }
            if let imported = result.settings.accent { accent = imported }
            if let imported = result.settings.iconTheme { IconManager.shared.theme = imported }
            for (stat, value) in result.settings.funStats ?? [:] { stat.set(value) }
            if let imported = result.settings.language, imported != language {
                AppLanguage.current = imported
                language = imported
            }
            // Ausgewählte Klasse behalten, wenn es sie noch gibt.
            let classIDs = try modelContext.fetch(FetchDescriptor<SchoolClass>()).map(\.id)
            if let selected = app.selectedClassID, !classIDs.contains(selected) {
                app.selectedClassID = classIDs.first
            }
            app.calendarFocusClassID = nil
            toasts.success(result.summary.text)
        } catch {
            modelContext.rollback()
            toasts.error(loc("Import fehlgeschlagen: \(error.localizedDescription)"))
        }
        await refreshDataSize()
    }

    private func refreshDataSize() async {
        dataSize = await Task.detached { LocalDataStore.totalSize() }.value
    }

    private func deleteAllData() async {
        guard await security.confirmDestructiveAction(reason: loc("Alle lokalen Daten löschen")) else { return }
        do {
            try LocalDataStore.deleteAll(in: modelContext)
            settings.values = SchoolSettings.Values()
            app.selectedClassID = nil
            app.calendarFocusClassID = nil
            UserDefaults.standard.removeObject(forKey: AppTabView.customizationKey)
            UserDefaults.standard.removeObject(forKey: AppPreference.hasOpenedSchoolSettings)
            toasts.success(loc("Alle lokalen Daten wurden gelöscht"))
        } catch {
            toasts.error(loc("Löschen fehlgeschlagen: \(error.localizedDescription)"))
        }
        await refreshDataSize()
    }
}

/// Lokale Ablage der App: Dokumente in Application Support, der SwiftData-Store im App-Group-Container
/// (SwiftData legt ihn dort ab, sobald die App eine App Group hat, hier für das Widget).
enum LocalDataStore {
    /// Gesamtgröße aller Dateien in Application Support und im App-Group-Container.
    nonisolated static func totalSize() -> Int64 {
        let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSchedule.appGroup)
        return ([URL.applicationSupportDirectory] + [group].compactMap { $0 }).reduce(0) { $0 + size(of: $1) }
    }

    nonisolated static func size(of root: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Löscht alle Datensätze und kopierten Dokumente.
    static func deleteAll(in context: ModelContext) throws {
        // Einzeln: Sammel-Löschen scheitert, sobald Schüler mit Beziehungen existieren.
        try context.deleteEach(
            SeatAssignment.self, BoardPhoto.self, ChecklistCheck.self, Checklist.self, StudentObservation.self, Absence.self,
            SubjectSettings.self, AssessmentResult.self, Assessment.self, PeriodGrade.self, Student.self, Lesson.self,
            DashboardLink.self, CalendarEntry.self, Holiday.self, SchoolClass.self, RoomElement.self, Room.self
        )
        try context.save()
        try? FileManager.default.removeItem(at: LinkFileStore.directory)
        FaviconStore.removeAll()
    }
}

nonisolated extension UTType {
    static let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
}

extension ModelContext {
    /// Alle Datensätze der Typen einzeln löschen (Löschregeln greifen, anders als beim Sammel-Löschen).
    func deleteEach(_ types: any PersistentModel.Type...) throws {
        for type in types {
            try deleteAll(of: type)
        }
    }

    private func deleteAll<T: PersistentModel>(of type: T.Type) throws {
        try fetch(FetchDescriptor<T>()).forEach(delete)
    }
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
