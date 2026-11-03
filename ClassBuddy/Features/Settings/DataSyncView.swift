import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI
import VisionKit

/// Einstellungen → Daten & Sync: gekoppelte Geräte im selben Netz abgleichen, Geräte koppeln (QR-Code zeigen oder
/// scannen), an Kollegen weitergeben und das Excel-Backup (Export & Import).
struct DataSyncView: View {
    @Environment(LocalSyncService.self) private var localSync
    @Environment(ToastCenter.self) private var toasts
    @State private var isPairingPresented = false
    @State private var pairingPendingRemoval: LocalPairing?

    var body: some View {
        Form {
            Section {
                ForEach(localSync.pairings) { pairing in
                    deviceRow(pairing)
                }
                Button {
                    isPairingPresented = true
                } label: {
                    // Vorläufig SF Symbol, bis ein eigenes Icon gewählt ist.
                    Label("Gerät koppeln", systemImage: "qrcode")
                }
                .disabled(localSync.isBusy)
            } header: {
                Text("Geräte in der Nähe")
            } footer: {
                Text(Self.localFooter)
            }

            ShareSection()
            BackupSection()
        }
        .navigationTitle("Daten & Sync")
        .sheet(isPresented: $isPairingPresented, onDismiss: localSync.cancelPairing) {
            PairingSheet()
        }
        .onChange(of: localSync.state) { _, state in
            switch state {
            case .finished(let message):
                isPairingPresented = false
                toasts.success(message)
            case .failed(let message):
                toasts.error(message)
            default:
                break
            }
        }
        .confirmationDialog(
            "Kopplung entfernen?",
            isPresented: Binding(get: { pairingPendingRemoval != nil }, set: { if !$0 { pairingPendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pairingPendingRemoval
        ) { pairing in
            Button("Entfernen", role: .destructive) { localSync.remove(pairing) }
        } message: { pairing in
            Text("Die Daten bleiben auf beiden Geräten. Zum erneuten Abgleich mit \(pairing.peerName) muss neu gekoppelt werden.")
        }
    }

    private static var localFooter: String {
        loc("""
            Gleicht Ihre eigenen Geräte direkt über das WLAN ab, ohne Server und ohne Internet. ClassBuddy muss auf \
            beiden Geräten geöffnet sein, beide brauchen dieselbe App-Version.
            """)
    }

    private func deviceRow(_ pairing: LocalPairing) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pairing.peerName)
                    Text(pairing.lastSync.map { loc("Zuletzt \($0.formatted(.relative(presentation: .named)))") } ?? loc("Noch nicht abgeglichen"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "ipad.and.iphone")
            }
            Spacer()
            if case .syncing(let peer) = localSync.state, peer == pairing.peerName {
                ProgressView()
            } else {
                Button("Jetzt synchronisieren") { localSync.sync(pairing) }
                    .buttonStyle(.borderless)
                    .disabled(localSync.isBusy)
            }
        }
        .swipeActions {
            Button("Entfernen", destructiveIcon: .trash) { pairingPendingRemoval = pairing }
        }
        .contextMenu {
            Button("Entfernen", destructiveIcon: .trash) { pairingPendingRemoval = pairing }
        }
    }
}

/// Koppeln: dieses Gerät zeigt einen Code oder scannt den Code des anderen.
private struct PairingSheet: View {
    @Environment(LocalSyncService.self) private var localSync
    @Environment(\.dismiss) private var dismiss
    @State private var mode = Mode.show
    @State private var code: PairingCode?

    private enum Mode: Hashable {
        case show, scan
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Koppeln", selection: $mode) {
                    Text("Code zeigen").tag(Mode.show)
                    Text("Code scannen").tag(Mode.scan)
                }
                .pickerStyle(.segmented)
                switch mode {
                case .show: showCode
                case .scan: scanner
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Gerät koppeln")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                        .toolbarGroupBackground()
                }
            }
        }
        .presentationDetents([.large])
        // Erst beim Zeigen erzeugen (nicht während des Zeichnens): Das Gerät wartet dann auf das andere.
        .task { code = localSync.makePairingCode() }
    }

    private var showCode: some View {
        VStack(spacing: 16) {
            if let code {
                QRCodeImage(text: code.text)
                    .frame(maxWidth: 280)
            }
            Text("Öffnen Sie auf dem anderen Gerät Einstellungen › Daten & Sync › Gerät koppeln › Code scannen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if case .syncing = localSync.state {
                ProgressView("Gleiche ab …")
            }
        }
    }

    @ViewBuilder
    private var scanner: some View {
        if DataScannerViewController.isSupported {
            QRScanner { text in
                guard let code = PairingCode(text: text) else { return }
                localSync.cancelPairing()
                localSync.pair(with: code)
                dismiss()
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxHeight: 420)
            Text("Richten Sie die Kamera auf den Code des anderen Geräts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            ContentUnavailableView(
                "Kamera nicht verfügbar", systemImage: "camera",
                description: Text("Scannen Sie den Code mit dem anderen Gerät.")
            )
        }
    }
}

/// QR-Code aus Text (Core Image, scharf vergrößert).
private struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityLabel("Kopplungscode")
        }
    }

    private static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Kamera, die den ersten QR-Code meldet (VisionKit).
private struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var isDone = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !isDone else { return }
            for case .barcode(let barcode) in items {
                guard let text = barcode.payloadStringValue, PairingCode(text: text) != nil else { continue }
                isDone = true
                onCode(text)
                return
            }
        }
    }
}

/// Excel-Backup (aus den App-Einstellungen hierher verschoben): Export und Import samt Rückfrage.
private struct BackupSection: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppAccent.storageKey) private var accent = AppAccent.defaultValue
    @State private var exportFile: SpreadsheetFile?
    @State private var isExporterPresented = false
    @State private var isImporterPresented = false
    @State private var pendingImport: Data?

    private static var transferInfo: String {
        loc("Excel-Datei, bearbeitbar in Excel oder Numbers. Ein Import ersetzt alle Daten; Dokumente und Fotos fehlen.")
    }

    var body: some View {
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
            // Ältere Backups: Bewertung je Fach in eigene Bewertung der Klasse übernehmen.
            SubjectSettings.migrate(school: settings.values, in: modelContext)
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
    }
}

/// An Kollegen weitergeben: alle Daten als `.classbuddy`-Datei (AirDrop, Mail, Dateien) bzw. ein Paket öffnen.
private struct ShareSection: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @State private var shareFile: SharedPackageFile?
    @State private var isImporterPresented = false

    var body: some View {
        Section {
            Button(action: share) {
                SettingsActionLabel(title: loc("Weitergeben"), icon: .shareIos)
            }
            Button {
                isImporterPresented = true
            } label: {
                SettingsActionLabel(title: loc("Paket öffnen"), icon: .import)
            }
        } header: {
            Text("An Kollegen weitergeben")
        } footer: {
            Text(Self.footer)
        }
        .disabled(security.isPrivacyModeOn)
        .sheet(item: $shareFile) { file in
            ActivitySheet(items: [file.url])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.classBuddyPackage]) { result in
            do {
                app.pendingSharedPackage = try SharedPackageImport.load(try result.get())
            } catch {
                toasts.error(error.localizedDescription)
            }
        }
    }

    private static var footer: String {
        loc("""
            Alle Klassen, Schüler, Notizen, Räume und Kacheln samt Schuleinstellungen als eine Datei, ohne Ihr Profil. \
            Wer das Paket öffnet, ersetzt damit alle eigenen Daten. Beide brauchen dieselbe App-Version.
            """)
    }

    private func share() {
        do {
            let package = try SyncEngine.sharePackage(in: modelContext, settings: settings)
            shareFile = try SharedPackageFile.write(SyncEngine.encodeShare(package))
        } catch {
            toasts.error(loc("Paket konnte nicht erstellt werden: \(error.localizedDescription)"))
        }
    }
}
