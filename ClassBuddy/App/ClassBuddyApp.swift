import SwiftData
import SwiftUI

@main
struct ClassBuddyApp: App {
    @State private var app = AppModel()
    @State private var security = AppSecurity()
    @State private var schoolSettings = SchoolSettings()
    @State private var toasts = ToastCenter()
    @State private var timer = ClassTimer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(security)
                .environment(schoolSettings)
                .environment(toasts)
                .environment(timer)
                .onAppear {
                    timer.onFinish = { [toasts] in toasts.success("Timer abgelaufen") }
                }
        }
        // Rein lokale Speicherung, kein iCloud-Sync.
        .modelContainer(for: [SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self, DashboardLink.self])
    }
}
