#if DEBUG
import SwiftData
import SwiftUI

/// Nur in Debug-Builds: schneller Zugriff auf schwer erreichbare Screens und Zustände
/// sowie Testdaten zum Ausprobieren.
struct DebugMenuView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Query private var classes: [SchoolClass]

    @State private var isLockPreviewPresented = false
    @State private var isPrivacyCoverPresented = false

    private var hasDummyData: Bool {
        classes.contains { DummyData.classIDs.contains($0.id) }
    }

    var body: some View {
        Form {
            Section {
                DebugActionRow(title: loc("Testdaten einfügen"), icon: .plus) {
                    insertDummyData()
                }
                .disabled(hasDummyData)
                DebugActionRow(title: loc("Testdaten entfernen"), icon: .trash) {
                    removeDummyData()
                }
                .disabled(!hasDummyData)
                DebugActionRow(title: loc("Demo-Klassenzimmer zurücksetzen"), icon: .floorLayout) {
                    RoomDemo.reset(in: modelContext)
                    toasts.success(loc("Demo-Klassenzimmer zurückgesetzt"))
                }
            } header: {
                Text("Testdaten")
            } footer: {
                Text("""
                    4 Klassen mit Schülern, ein Stundenplan (wöchentlich und einmalig) und Termine in der aktuellen Woche. \
                    Nur einmal einfügbar – erst nach dem Entfernen (oder „Alle lokalen Daten löschen“) wieder.
                    """)
            }

            Section("Sperre & Privatsphäre") {
                DebugActionRow(title: loc("App jetzt sperren"), icon: .lock) {
                    guard security.isAppLockEnabled else {
                        toasts.error(loc("App-Sperre ist in den App-Einstellungen ausgeschaltet."))
                        return
                    }
                    security.lock()
                }
                DebugActionRow(title: loc("Sperrbildschirm mit Fehlermeldung"), icon: .fingerprintLockCircle) {
                    isLockPreviewPresented = true
                }
                DebugActionRow(title: loc("Privatsphäre-Abdeckung"), icon: .eyeClosed) {
                    isPrivacyCoverPresented = true
                }
            }

            WeatherDiagnosticsSection()

            Section("Leerzustände") {
                NavigationLink {
                    EmptyStateView(
                        title: loc("Keine Klasse ausgewählt"),
                        message: loc("Legen Sie oben links Ihre erste Klasse an."),
                        symbol: .custom(.userXmark)
                    )
                } label: {
                    Label("Keine Klasse ausgewählt", icon: .userXmark)
                }
                NavigationLink {
                    EmptyStateView(
                        title: loc("Noch keine Schüler"),
                        message: loc("Fügen Sie über + oben rechts die Schülerinnen und Schüler der Klasse 7b hinzu."),
                        symbol: AppTab.students.symbol
                    )
                } label: {
                    Label("Noch keine Schüler", symbol: AppTab.students.symbol)
                }
                NavigationLink {
                    EmptyStateView(
                        title: AppTab.rooms.title,
                        message: loc("Hier verwalten Sie bald Ihre Räume und deren Sitzordnungen."),
                        symbol: AppTab.rooms.symbol
                    )
                } label: {
                    Label("Räume (Platzhalter)", symbol: AppTab.rooms.symbol)
                }
                NavigationLink {
                    SearchEmptyStateView(text: "Xylophon")
                } label: {
                    Label("Suche ohne Treffer", icon: .search)
                }
            }

            Section("Toasts") {
                DebugActionRow(title: loc("Erfolg"), icon: .toastSuccess) { toasts.success(loc("Export gespeichert")) }
                DebugActionRow(title: loc("Hinweis"), icon: .toastWarning) { toasts.info(loc("Keine Änderungen gefunden")) }
                DebugActionRow(title: loc("Fehler"), icon: .toastError) { toasts.error(loc("Import fehlgeschlagen: Datei beschädigt")) }
            }
        }
        .navigationTitle("Debug-Menü")
        .fullScreenCover(isPresented: $isLockPreviewPresented) {
            LockScreenView(previewError: loc("Authentifizierung fehlgeschlagen."))
                .overlay(alignment: .topTrailing) {
                    closeButton { isLockPreviewPresented = false }
                }
        }
        .fullScreenCover(isPresented: $isPrivacyCoverPresented) {
            PrivacyCoverView()
                .overlay(alignment: .topTrailing) {
                    closeButton { isPrivacyCoverPresented = false }
                }
        }
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Schließen", icon: .xmark)
                .labelStyle(.iconOnly)
                .padding(6)
        }
        .appGlassButtonStyle()
        .padding()
    }

    private func insertDummyData() {
        guard !hasDummyData else { return }
        let firstClass = DummyData.insert(into: modelContext, slotCount: settings.slots.count)
        do {
            try modelContext.save()
            app.selectedClassID = firstClass.id
            toasts.success(loc("Testdaten eingefügt"))
        } catch {
            toasts.error(loc("Testdaten fehlgeschlagen: \(error.localizedDescription)"))
        }
    }

    private func removeDummyData() {
        // Erst abwählen, dann löschen: sonst liest die Übersicht noch Werte der gelöschten Klasse (Absturz).
        if let selected = app.selectedClassID, DummyData.classIDs.contains(selected) {
            app.selectedClassID = classes.first { !DummyData.classIDs.contains($0.id) }?.id
        }
        DummyData.remove(from: modelContext, classes: classes)
        do {
            try modelContext.save()
            toasts.success(loc("Testdaten entfernt"))
        } catch {
            toasts.error(loc("Entfernen fehlgeschlagen: \(error.localizedDescription)"))
        }
    }
}

/// Aktionszeile: Text in Textfarbe (auch bei Löschen), nur das Icon in der Akzentfarbe.
private struct DebugActionRow: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let icon: AppIcon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title).foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            } icon: {
                Image(icon: icon)
            }
        }
    }
}

/// Woher das Wetter auf der Übersicht zuletzt kam – und warum nicht von Apple (WeatherKit-Fehler).
private struct WeatherDiagnosticsSection: View {
    @State private var source: WeatherService.Source?
    @State private var appleError: String?

    var body: some View {
        Section {
            LabeledContent("Letzte Quelle", value: source.map { $0 == .apple ? "Apple (WeatherKit)" : "Open-Meteo" } ?? "–")
            if let appleError {
                Text(verbatim: appleError)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Wetter")
        } footer: {
            Text("Wird beim nächsten Laden der Wetter-Kachel aktualisiert (höchstens alle 30 Minuten).")
        }
        .task {
            source = await WeatherService.diagnostics.lastSource
            appleError = await WeatherService.diagnostics.lastAppleError
        }
    }
}
#endif
