import SwiftData
import SwiftUI
import UIKit

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
            UserDefaults.standard.removeObject(forKey: "navigation.tabCustomization")
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
    }
}
