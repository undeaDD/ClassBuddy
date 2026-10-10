import SwiftData
import SwiftUI
import TipKit

/// Einrichtung für neue Nutzer: Es zeigt immer nur der erste offene Schritt einen Tipp
/// (Schritt 1 als Popover am Klassen-Button, alle weiteren oben auf der Übersicht).
nonisolated enum SetupStep: String, CaseIterable, Sendable {
    case createClass
    case addStudents
    case createSchedule
    case schoolTimes
    case assignRoom
    case importHolidays

    /// Was die Schritte prüfen; getrennt von SwiftData, damit die Reihenfolge testbar ist.
    struct State {
        var hasClasses = false
        var hasSelectedClass = false
        var studentCount = 0
        /// Stunden und Termine der ausgewählten Klasse.
        var scheduleCount = 0
        var scheduleWithRoomCount = 0
        var hasReviewedSchoolTimes = false
        var hasHolidays = false
    }

    /// Erster offener Schritt; `nil`, wenn alles erledigt ist oder keine Klasse ausgewählt ist.
    static func current(_ state: State) -> SetupStep? {
        guard state.hasClasses else { return .createClass }
        guard state.hasSelectedClass else { return nil }
        if state.studentCount == 0 { return .addStudents }
        if state.scheduleCount == 0 { return .createSchedule }
        if !state.hasReviewedSchoolTimes { return .schoolTimes }
        if state.scheduleWithRoomCount == 0 { return .assignRoom }
        if !state.hasHolidays { return .importHolidays }
        return nil
    }

    var icon: AppIcon {
        switch self {
        case .createClass: .plus
        case .addStudents: .community
        case .createSchedule: .calendar
        case .schoolTimes: .time
        case .assignRoom: .floorLayout
        case .importHolidays: .gift
        }
    }
}

extension SetupStep.State {
    init(
        classes: [SchoolClass],
        selectedClass: SchoolClass?,
        settings: SchoolSettings.Values,
        hasOpenedSchoolSettings: Bool,
        holidayCount: Int
    ) {
        let lessonRooms = selectedClass?.lessons.map { $0.room != nil } ?? []
        let entryRooms = selectedClass?.calendarEntries.map { $0.room != nil } ?? []
        let schedule = lessonRooms + entryRooms
        self.init(
            hasClasses: !classes.isEmpty,
            hasSelectedClass: selectedClass != nil,
            studentCount: selectedClass?.students.count ?? 0,
            scheduleCount: schedule.count,
            scheduleWithRoomCount: schedule.filter { $0 }.count,
            hasReviewedSchoolTimes: hasOpenedSchoolSettings || settings.hasCustomTimes,
            hasHolidays: settings.holidaysImportedAt != nil || holidayCount > 0
        )
    }
}

extension SchoolSettings.Values {
    /// Stundenraster oder Pausen weichen von den Vorgaben ab (wer das angepasst hat, braucht keinen Tipp mehr).
    var hasCustomTimes: Bool {
        let defaults = Self()
        return dayStart != defaults.dayStart || dayEnd != defaults.dayEnd
            || lessonDuration != defaults.lessonDuration
            || breaks.map { [$0.start, $0.duration] } != defaults.breaks.map { [$0.start, $0.duration] }
    }
}

/// Tipp zu einem Einrichtungsschritt. Das Bild kommt aus der View (Icon-Theme ist an den Main Actor gebunden).
nonisolated struct SetupTip: Tip {
    /// Tipps überhaupt erlaubt: Einstellung an, Einführung erledigt, App entsperrt und im Vordergrund.
    /// Gilt für alle Tipps der App, gesetzt in `RootView`.
    @Parameter static var isAllowed: Bool = false

    let step: SetupStep
    var image: Image?

    init(_ step: SetupStep, image: Image? = nil) {
        self.step = step
        self.image = image
    }

    var id: String { "setup.\(step.rawValue)" }

    var title: Text {
        switch step {
        case .createClass: Text(loc("Erste Klasse anlegen"))
        case .addStudents: Text(loc("Schülerliste anlegen"))
        case .createSchedule: Text(loc("Stundenplan anlegen"))
        case .schoolTimes: Text(loc("Stundenraster und Pausen einstellen"))
        case .assignRoom: Text(loc("Raum zuweisen"))
        case .importHolidays: Text(loc("Ferien importieren"))
        }
    }

    var message: Text? {
        switch step {
        case .createClass:
            Text(loc("Tippen Sie hier, um Ihre erste Klasse mit Fächern und Farbe anzulegen."))
        case .addStudents:
            Text(loc("Tragen Sie die Schüler dieser Klasse ein."))
        case .createSchedule:
            Text(loc("Tragen Sie die Stunden dieser Klasse im Kalender ein."))
        case .schoolTimes:
            Text(loc("Passen Sie Schulbeginn, Stundenlänge und Pausen in den Schuleinstellungen an Ihre Schule an."))
        case .assignRoom:
            Text(loc("""
                Legen Sie einen Raum an und weisen Sie ihn Ihren Stunden im Kalender zu. \
                Dann öffnet die Stunde direkt den Sitzplan.
                """))
        case .importHolidays:
            Text(loc("Importieren Sie die Ferien Ihres Bundeslands in den Schuleinstellungen."))
        }
    }

    var actions: [Action] {
        switch step {
        case .createClass: []
        case .addStudents: [Action(id: "open", title: loc("Zu den Schülern"))]
        case .createSchedule: [Action(id: "open", title: loc("Zum Kalender"))]
        case .schoolTimes, .importHolidays: [Action(id: "open", title: loc("Zu den Schuleinstellungen"))]
        case .assignRoom: [Action(id: "open", title: loc("Zu den Räumen"))]
        }
    }

    var rules: [Rule] {
        [#Rule(Self.$isAllowed) { $0 }]
    }
}

/// Privatsphäre-Modus (Button oben rechts), sobald die Klasse Schüler hat und die App ein paar Mal geöffnet wurde.
nonisolated struct PrivacyModeTip: Tip {
    static let appOpened = Tips.Event(id: "appOpened")

    var image: Image?

    init(image: Image? = nil) {
        self.image = image
    }

    var title: Text { Text(loc("Privatsphäre-Modus")) }

    var message: Text? {
        Text(loc("Blendet Namen und Notizen aus, zum Beispiel wenn Ihr Bildschirm per Beamer zu sehen ist."))
    }

    var rules: [Rule] {
        [
            #Rule(SetupTip.$isAllowed) { $0 },
            #Rule(Self.appOpened) { $0.donations.count >= 3 },
        ]
    }
}

/// „Kacheln anordnen“ auf der Übersicht, erst nach dem Tipp zum Privatsphäre-Modus.
nonisolated struct ArrangeCardsTip: Tip {
    static let dashboardOpened = Tips.Event(id: "dashboardOpened")
    @Parameter static var isPrivacyTipDone: Bool = false

    var image: Image?

    init(image: Image? = nil) {
        self.image = image
    }

    var title: Text { Text(loc("Kacheln anordnen")) }

    var message: Text? {
        Text(loc("Sortieren Sie die Kacheln der Übersicht oder blenden Sie einzelne aus."))
    }

    var rules: [Rule] {
        [
            #Rule(SetupTip.$isAllowed) { $0 },
            #Rule(Self.$isPrivacyTipDone) { $0 },
            #Rule(Self.dashboardOpened) { $0.donations.count >= 5 },
        ]
    }
}

/// Oben auf der Übersicht: Tipp zum offenen Einrichtungsschritt ab Schritt 2
/// (Schritt 1 zeigt der Klassen-Button), mit Button zur passenden Seite.
struct SetupTipView: View {
    @Environment(AppModel.self) private var app
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.device) private var device
    @Query private var classes: [SchoolClass]
    @Query private var holidays: [Holiday]
    @AppStorage(AppPreference.hasOpenedSchoolSettings) private var hasOpenedSchoolSettings = false
    let schoolClass: SchoolClass
    /// Beim Anordnen der Kacheln ausgeblendet.
    var isHidden = false

    private var step: SetupStep? {
        let state = SetupStep.State(
            classes: classes,
            selectedClass: schoolClass,
            settings: settings.values,
            hasOpenedSchoolSettings: hasOpenedSchoolSettings,
            holidayCount: holidays.count
        )
        guard let step = SetupStep.current(state), step != .createClass else { return nil }
        return step
    }

    var body: some View {
        if !isHidden, let step {
            TipView(SetupTip(step, image: Image(icon: step.icon))) { _ in
                open(step)
            }
            .tipBackground(Color(.secondarySystemGroupedBackground))
        }
    }

    private func open(_ step: SetupStep) {
        switch step {
        case .createClass: app.isClassPickerPresented = true
        case .addStudents: app.open(.students)
        case .createSchedule: app.openCalendar(focusing: schoolClass.id)
        case .schoolTimes, .importHolidays: app.openSchoolSettings()
        case .assignRoom: app.openRooms(isPhone: device.isPhone)
        }
    }
}

enum AppTips {
    /// Einmal beim Start. Ein Fehler hier (z. B. doppelt konfiguriert) bedeutet nur: keine Tipps.
    static func configure() {
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

extension View {
    /// Popover-Tipp, nur wenn `tip` gesetzt ist. TipKit nimmt optionale Tipps erst ab iOS 18.4 an.
    /// Tipp „Kacheln anordnen“ am Button der Übersicht; zählt dabei, wie oft die Übersicht geöffnet wurde.
    func arrangeCardsTip(isEnabled: Bool) -> some View {
        appPopoverTip(isEnabled ? ArrangeCardsTip(image: Image(icon: .editPencil)) : nil)
            .onAppear { Task { await ArrangeCardsTip.dashboardOpened.donate() } }
    }

    @ViewBuilder
    func appPopoverTip(_ tip: (some Tip)?) -> some View {
        if let tip {
            popoverTip(tip, arrowEdge: .top)
        } else {
            self
        }
    }
}
