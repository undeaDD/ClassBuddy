import SwiftData
import SwiftUI

@main
struct ClassBuddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel()
    @State private var security = AppSecurity()
    @State private var schoolSettings = SchoolSettings()
    @State private var toasts = ToastCenter()
    @State private var timer = ClassTimer()
    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                // Sprachwechsel: Oberfläche neu aufbauen, damit auch Texte aus Code (`loc`) neu berechnet werden.
                .id(language)
                .environment(\.locale, language.locale)
                .environment(app)
                .environment(security)
                .environment(schoolSettings)
                .environment(toasts)
                .environment(timer)
                .onAppear {
                    timer.onFinish = { [toasts] in toasts.success(loc("Timer abgelaufen")) }
                    HomeScreenAction.register()
                }
        }
        // Rein lokale Speicherung, kein iCloud-Sync.
        .modelContainer(for: [SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self, DashboardLink.self])
    }
}
