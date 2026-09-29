import SwiftUI

/// App-weiter UI-Zustand (Navigation, ausgewählte Klasse, Sheets).
@Observable
final class AppModel {
    var selectedTab: AppTab = .dashboard
    var isClassPickerPresented = false
    var isNewClassSheetPresented = false

    var selectedClassID: UUID? {
        didSet { UserDefaults.standard.set(selectedClassID?.uuidString, forKey: Self.selectedClassKey) }
    }

    private static let selectedClassKey = "app.selectedClassID"

    init() {
        selectedClassID = UserDefaults.standard.string(forKey: Self.selectedClassKey).flatMap(UUID.init)
    }

    func open(_ tab: AppTab) {
        selectedTab = tab
    }
}
