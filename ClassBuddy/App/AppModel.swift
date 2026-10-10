import SwiftUI

/// App-weiter UI-Zustand (Navigation, ausgewählte Klasse, Sheets).
@Observable
final class AppModel {
    var selectedTab: AppTab = .dashboard {
        didSet {
            if oldValue != selectedTab { resetStack(of: oldValue) }
        }
    }

    /// Zähler je Tab, dient als `.id` seines NavigationStacks: Wer einen Tab verlässt,
    /// findet ihn beim Zurückkehren wieder an der Wurzel (statt tief in einer Unterseite).
    private(set) var stackGenerations: [AppTab: Int] = [:]

    func stackID(for tab: AppTab) -> Int { stackGenerations[tab, default: 0] }

    func resetStack(of tab: AppTab) {
        stackGenerations[tab, default: 0] += 1
    }
    var isClassPickerPresented = false

    /// Optionaler Kalender-Fokus: nur Stunden dieser Klasse farbig, alle anderen neutral.
    var calendarFocusClassID: UUID?
    /// Angezeigter Tag im Kalender (iPad: dessen Woche, schmal: Mitte des 3-Tage-Fensters).
    /// Hier statt in `CalendarView`, damit auch das Blättern in der Tab-Leiste (iPhone) darauf zugreift.
    var calendarDate = Calendar.school.startOfDay(for: .now)

    /// Offener Sitzplan (Vollbild über allem), z. B. nach Antippen einer Stunde mit Raum.
    var seatingPlan: SeatingPlanRoute?
    /// Fach, das der Tafelbild-Tab beim nächsten Öffnen zeigen soll (Kachel „Letztes Tafelbild“).
    var boardSubject: String?
    /// Raumliste als Sheet (iPhone): „Räume“ liegt dort unter „Mehr“, ein Tab-Wechsel führte beim Zurück dorthin.
    var isRoomsSheetPresented = false

    var selectedClassID: UUID? {
        didSet { UserDefaults.standard.set(selectedClassID?.uuidString, forKey: Self.selectedClassKey) }
    }

    private static let selectedClassKey = "app.selectedClassID"

    init() {
        let startTab = UserDefaults.standard.string(forKey: AppPreference.startTab).flatMap(AppTab.init(rawValue:))
        selectedTab = startTab.flatMap { AppTab.startTabs.contains($0) ? $0 : nil } ?? .dashboard
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

    /// Sitzplan einer Klasse in einem Raum öffnen; mit Fach (aus der Stunde) führt ein Schüler direkt zu seinen Notizen.
    func openSeatingPlan(room: Room, schoolClass: SchoolClass?, subject: String? = nil) {
        isClassPickerPresented = false
        seatingPlan = SeatingPlanRoute(room: room, schoolClass: schoolClass, subject: subject?.nonEmpty)
    }

    /// Räume aus Kalender oder Übersicht öffnen: iPhone als Sheet (Schließen führt zurück), iPad über den Tab.
    func openRooms(isPhone: Bool) {
        if isPhone {
            isClassPickerPresented = false
            isRoomsSheetPresented = true
        } else {
            open(.rooms)
        }
    }

    /// Kaufseite von der Testphasen-Kachel (schließbar, siehe `RootView`).
    var isPurchasePagePresented = false

    /// Einstellungen öffnen die Schuleinstellungen (Einrichtungs-Tipps auf der Übersicht).
    var isSchoolSettingsRequested = false

    func openSchoolSettings() {
        isSchoolSettingsRequested = true
        open(.settings)
    }

    /// Checkliste, die der Checklisten-Tab beim nächsten Öffnen zeigen soll (Kachel „Checklisten“).
    var checklistToOpen: UUID?

    func openChecklist(_ id: UUID) {
        checklistToOpen = id
        open(.checklists)
    }

    /// Tafelbild-Tab mit einem bestimmten Fach öffnen.
    func openBoard(subject: String) {
        boardSubject = subject
        open(.board)
    }

    /// Kalender öffnen, gefiltert auf eine Klasse, an einem bestimmten Datum.
    func openCalendar(focusing classID: UUID?, at date: Date? = nil) {
        calendarFocusClassID = classID
        if let date { calendarDate = Calendar.school.startOfDay(for: date) }
        open(.calendar)
    }
}
