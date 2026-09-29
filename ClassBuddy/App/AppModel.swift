import SwiftUI

/// App-weiter UI-Zustand (Navigation, ausgewählte Klasse, Sheets).
@Observable
final class AppModel {
    var selectedTab: AppTab = .dashboard
    var isClassPickerPresented = false

    /// Optionaler Kalender-Fokus: nur Stunden dieser Klasse farbig, alle anderen neutral.
    var calendarFocusClassID: UUID?
    /// Woche, die der Kalender beim nächsten Anzeigen zeigen soll.
    var calendarJumpDate: Date?

    var selectedClassID: UUID? {
        didSet { UserDefaults.standard.set(selectedClassID?.uuidString, forKey: Self.selectedClassKey) }
    }

    private static let selectedClassKey = "app.selectedClassID"

    init() {
        selectedClassID = UserDefaults.standard.string(forKey: Self.selectedClassKey).flatMap(UUID.init)
    }

    /// Tab wechseln. Ist das Klassen-Popover offen, wird es zuerst geschlossen:
    /// Die Tab-Leiste bleibt bei offenem Popover antippbar, und Popover-Schließen
    /// plus Tab-Wechsel im selben Moment bringt UIKit zum Absturz.
    func open(_ tab: AppTab) {
        guard tab != selectedTab else { return }
        guard isClassPickerPresented else {
            selectedTab = tab
            return
        }
        isClassPickerPresented = false
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            selectedTab = tab
        }
    }

    /// Kalender öffnen, gefiltert auf eine Klasse, an einem bestimmten Datum.
    func openCalendar(focusing classID: UUID?, at date: Date? = nil) {
        calendarFocusClassID = classID
        calendarJumpDate = date
        open(.calendar)
    }
}
