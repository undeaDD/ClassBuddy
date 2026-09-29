import SwiftData
import SwiftUI

@main
struct ClassBuddyApp: App {
    @State private var app = AppModel()
    @State private var security = AppSecurity()
    @State private var schoolSettings = SchoolSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(security)
                .environment(schoolSettings)
        }
        // Rein lokale Speicherung, kein iCloud-Sync.
        .modelContainer(for: [SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self])
    }
}
