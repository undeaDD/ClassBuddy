import SwiftData
import SwiftUI

@main
struct ClassBuddyApp: App {
    @State private var app = AppModel()
    @State private var security = AppSecurity()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(security)
        }
        // Rein lokale Speicherung, kein iCloud-Sync.
        .modelContainer(for: [SchoolClass.self])
    }
}
