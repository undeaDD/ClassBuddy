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
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @AppStorage(AppAccent.storageKey) private var accent = AppAccent.defaultValue

    init() {
        AppTips.configure()
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
                .onAppear {
                    timer.onFinish = { [toasts] in toasts.success(loc("Timer abgelaufen")) }
                    HomeScreenAction.register()
                }
        }
        // Rein lokale Speicherung, kein iCloud-Sync.
        .modelContainer(for: [
            SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self, DashboardLink.self,
            Room.self, RoomElement.self, SeatAssignment.self, BoardPhoto.self,
            Checklist.self, ChecklistCheck.self, SubjectSettings.self, StudentObservation.self, Absence.self,
            Assessment.self, AssessmentResult.self, PeriodGrade.self,
        ])
    }
}
