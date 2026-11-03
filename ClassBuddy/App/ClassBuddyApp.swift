import SwiftData
import SwiftUI
import TipKit

@main
struct ClassBuddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel()
    @State private var security = AppSecurity()
    @State private var schoolSettings = SchoolSettings()
    @State private var toasts = ToastCenter()
    @State private var timer = ClassTimer()
    @State private var purchases = PurchaseStore()
    @State private var localSync = LocalSyncService()
    @State private var cloudFolder = CloudFolderSync()
    @State private var iCloud = ICloudSync()
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppAccent.storageKey) private var accent = AppAccent.defaultValue

    init() {
        AppTips.configure()
        SyncTracking.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Sprachwechsel: Oberfläche neu aufbauen, damit auch Texte aus Code (`loc`) neu berechnet werden.
                .id(language)
                .environment(\.locale, language.locale)
                // Akzentfarbe: `.tint` für SwiftUI, `\.appAccent` wo eine `Color` nötig ist, Fenster für UIKit.
                .tint(AppAccent.color(for: accent))
                .environment(\.appAccent, AppAccent.color(for: accent))
                .onChange(of: accent, initial: true) { _, accent in AppAccent.apply(accent) }
                .environment(app)
                .environment(security)
                .environment(schoolSettings)
                .environment(toasts)
                .environment(timer)
                .environment(purchases)
                .environment(localSync)
                .environment(cloudFolder)
                .environment(iCloud)
                .onAppear {
                    timer.onFinish = { [toasts] in toasts.success(loc("Timer abgelaufen")) }
                    HomeScreenAction.register()
                }
        }
        .modelContainer(Self.container)
    }

    /// Lokale Speicherung; `lastModified` und `DeletedRecord` dienen dem Abgleich zwischen Geräten (`SyncTracking`).
    /// Ohne SwiftData-CloudKit-Spiegelung: Die App hat iCloud für den eigenen, verschlüsselten Sync (`ICloudSync`),
    /// SwiftData würde sonst selbst spiegeln wollen und den Speicher nicht laden.
    private static let container: ModelContainer = {
        let schema = Schema([
            SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self, DashboardLink.self,
            Room.self, RoomElement.self, SeatAssignment.self, BoardPhoto.self,
            Checklist.self, ChecklistCheck.self, SubjectSettings.self, StudentObservation.self, Absence.self,
            Assessment.self, AssessmentResult.self, PeriodGrade.self, DeletedRecord.self,
        ])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        } catch {
            fatalError("Datenbank konnte nicht geladen werden: \(error)")
        }
    }()
}
