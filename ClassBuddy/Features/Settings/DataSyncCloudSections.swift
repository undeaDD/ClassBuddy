import SwiftData
import SwiftUI

/// Daten & Sync › iCloud: Ein- und Ausschalten, Stand, „Jetzt synchronisieren“. Gleicht beim Öffnen automatisch ab.
struct ICloudSection: View {
    @Environment(ICloudSync.self) private var iCloud
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { iCloud.isEnabled }, set: { enable($0) })) {
                // Vorläufig SF Symbol, bis ein eigenes Icon gewählt ist.
                Label("Mit iCloud abgleichen", systemImage: "icloud")
            }
            if iCloud.isEnabled {
                SyncStatusRow(
                    lastSync: iCloud.lastSync, isBusy: iCloud.isBusy,
                    action: { Task { await iCloud.sync(context: modelContext, settings: settings, deviceName: deviceName) } }
                )
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(Self.footer)
        }
        .onChange(of: iCloud.state) { _, state in
            switch state {
            case .finished(let message): toasts.success(message)
            case .failed(let message): toasts.error(message)
            default: break
            }
        }
    }

    private var deviceName: String { LocalSyncService.deviceName(teacher: settings.values.teacher) }

    private static var footer: String {
        loc("""
            Automatisch bei jedem Öffnen der App und auf Wunsch von Hand. Gleicht Ihre eigenen Geräte über Ihr \
            iCloud ab, verschlüsselt mit dem Daten-Passwort: Apple sieht nichts Lesbares. Alle Geräte brauchen \
            dieselbe Apple-ID, dasselbe Daten-Passwort und dieselbe App-Version.
            """)
    }

    private func enable(_ isOn: Bool) {
        iCloud.setEnabled(isOn)
        if isOn { Task { await iCloud.sync(context: modelContext, settings: settings, deviceName: deviceName) } }
    }
}

/// Daten & Sync › Cloud-Ordner: Ordner wählen (Dateien-App), „Jetzt synchronisieren“, Ordner entfernen. Nur von Hand.
struct CloudFolderSection: View {
    @Environment(CloudFolderSync.self) private var cloudFolder
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @State private var isPickerPresented = false
    @State private var isRemovalConfirmationPresented = false

    var body: some View {
        Section {
            if let folderName = cloudFolder.folderName {
                // Vorläufig SF Symbol, bis ein eigenes Icon gewählt ist.
                Label(folderName, systemImage: "folder")
                SyncStatusRow(
                    lastSync: cloudFolder.lastSync, isBusy: cloudFolder.isBusy,
                    action: { Task { await cloudFolder.sync(context: modelContext, settings: settings, deviceName: deviceName) } }
                )
                Button("Anderen Ordner wählen") { isPickerPresented = true }
                    .disabled(cloudFolder.isBusy)
                Button("Ordner entfernen", role: .destructive) { isRemovalConfirmationPresented = true }
                    .disabled(cloudFolder.isBusy)
            } else {
                Button("Ordner wählen", systemImage: "folder.badge.plus") { isPickerPresented = true }
            }
        } header: {
            Text("Cloud-Ordner")
        } footer: {
            Text(Self.footer)
        }
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { cloudFolder.choose(url) }
        }
        .confirmationDialog("Ordner entfernen?", isPresented: $isRemovalConfirmationPresented, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) { cloudFolder.remove() }
        } message: {
            Text("ClassBuddy gleicht dann nicht mehr über diesen Ordner ab. Die Dateien darin und Ihre Daten bleiben.")
        }
        .onChange(of: cloudFolder.state) { _, state in
            switch state {
            case .finished(let message): toasts.success(message)
            case .failed(let message): toasts.error(message)
            default: break
            }
        }
    }

    private var deviceName: String { LocalSyncService.deviceName(teacher: settings.values.teacher) }

    private static var footer: String {
        loc("""
            Nur von Hand. Wählen Sie einen Ordner in Google Drive, Nextcloud, OneDrive, Dropbox oder iCloud Drive \
            (die App des Anbieters muss installiert und in der Dateien-App eingeschaltet sein) und auf jedem Gerät \
            denselben Ordner. Jedes Gerät legt dort eine eigene Datei ab, verschlüsselt mit dem Daten-Passwort: Der \
            Anbieter sieht nichts Lesbares. Alle Geräte brauchen dasselbe Daten-Passwort und dieselbe App-Version.
            """)
    }
}

/// Letzter Abgleich und „Jetzt synchronisieren“.
private struct SyncStatusRow: View {
    let lastSync: Date?
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(lastSync.map { loc("Zuletzt \($0.formatted(.relative(presentation: .named)))") } ?? loc("Noch nicht abgeglichen"))
                .foregroundStyle(.secondary)
            Spacer()
            if isBusy {
                ProgressView()
            } else {
                Button("Jetzt synchronisieren", action: action)
                    .buttonStyle(.borderless)
            }
        }
    }
}

/// Daten-Passwort: anzeigen, kopieren, ändern oder neu erzeugen. Gilt für Excel-Backup, Kollegen-Paket und jeden Sync.
struct DataPasswordSection: View {
    @Environment(LocalSyncService.self) private var localSync
    @Environment(AppSecurity.self) private var security
    @Environment(ToastCenter.self) private var toasts
    @State private var password = DataPassword.current
    @State private var isRevealed = false
    @State private var isEditing = false
    @State private var draft = ""
    @State private var pendingChange: String?

    var body: some View {
        Section {
            HStack {
                Text(isRevealed ? password : String(repeating: "•", count: 12))
                    .monospaced()
                    .textSelection(.enabled)
                    .privacySensitive()
                Spacer()
                // Vorläufig SF Symbols, bis eigene Icons gewählt sind.
                Button(isRevealed ? "Verbergen" : "Anzeigen", systemImage: isRevealed ? "eye.slash" : "eye") {
                    isRevealed.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                Button("Kopieren", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = password
                    toasts.success(loc("Passwort kopiert"))
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
            Button("Passwort ändern", systemImage: "pencil") {
                draft = password
                isEditing = true
            }
            Button("Neues Passwort erzeugen", systemImage: "arrow.clockwise") {
                pendingChange = DataPassword.generate()
            }
        } header: {
            Text("Daten-Passwort")
        } footer: {
            Text(Self.footer)
        }
        .disabled(security.isPrivacyModeOn)
        .alert("Passwort ändern", isPresented: $isEditing) {
            TextField("Neues Passwort", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Weiter") {
                let candidate = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard candidate != password else { return }
                guard DataPassword.isValid(candidate) else {
                    toasts.error(loc("Das Passwort braucht mindestens \(DataPassword.minimumLength) Zeichen."))
                    return
                }
                pendingChange = candidate
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Mindestens \(DataPassword.minimumLength) Zeichen.")
        }
        .confirmationDialog(
            "Daten-Passwort ändern?",
            isPresented: Binding(get: { pendingChange != nil }, set: { if !$0 { pendingChange = nil } }),
            titleVisibility: .visible,
            presenting: pendingChange
        ) { newPassword in
            Button("Ändern", role: .destructive) { change(to: newPassword) }
        } message: { _ in
            Text(Self.changeWarning)
        }
    }

    private static var footer: String {
        loc("""
            Schützt Excel-Backups, Pakete für Kollegen und jeden Abgleich. Ihre eigenen Geräte brauchen dasselbe \
            Passwort. Bitte notieren Sie es: Ohne das Passwort lassen sich Backups nicht mehr öffnen.
            """)
    }

    private static var changeWarning: String {
        loc("""
            Tragen Sie das neue Passwort danach auf allen eigenen Geräten ein, sonst gleichen sie sich nicht mehr ab. \
            Ältere Backups und Pakete öffnen weiterhin nur mit dem bisherigen Passwort.
            """)
    }

    private func change(to newPassword: String) {
        DataPassword.set(newPassword)
        password = newPassword
        localSync.reloadKeys()
        toasts.success(loc("Daten-Passwort geändert"))
    }
}
