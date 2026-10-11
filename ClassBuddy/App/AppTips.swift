import SwiftData
import SwiftUI
import TipKit

/// Einrichtung für neue Nutzer: Es zeigt immer nur der erste offene Schritt einen Tipp, als Kachel auf der
/// Übersicht (Schritt 1 über dem Leerzustand, solange es keine Klasse gibt).
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

    var title: String {
        switch self {
        case .createClass: loc("Erste Klasse anlegen")
        case .addStudents: loc("Schülerliste anlegen")
        case .createSchedule: loc("Stundenplan anlegen")
        case .schoolTimes: loc("Stundenraster und Pausen einstellen")
        case .assignRoom: loc("Raum zuweisen")
        case .importHolidays: loc("Ferien importieren")
        }
    }

    var message: String {
        switch self {
        case .createClass: loc("Legen Sie Ihre erste Klasse mit Fächern und Farbe an.")
        case .addStudents: loc("Tragen Sie die Schüler dieser Klasse ein.")
        case .createSchedule: loc("Tragen Sie die Stunden dieser Klasse im Kalender ein.")
        case .schoolTimes: loc("Passen Sie Schulbeginn, Stundenlänge und Pausen an Ihre Schule an.")
        case .assignRoom: loc("Weisen Sie Ihren Stunden einen Raum zu, dann öffnet die Stunde direkt den Sitzplan.")
        case .importHolidays: loc("Importieren Sie die Ferien Ihres Bundeslands in den Schuleinstellungen.")
        }
    }

    /// Button zur passenden Seite bzw. Aktion.
    var actionTitle: String? {
        switch self {
        case .createClass: loc("Klasse anlegen")
        case .addStudents: loc("Zu den Schülern")
        case .createSchedule: loc("Zum Kalender")
        case .schoolTimes, .importHolidays: loc("Zu den Schuleinstellungen")
        case .assignRoom: loc("Zu den Räumen")
        }
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

    var title: Text { Text(step.title) }
    var message: Text? { Text(step.message) }

    var actions: [Action] {
        step.actionTitle.map { [Action(id: "open", title: $0)] } ?? []
    }

    var rules: [Rule] {
        [#Rule(Self.$isAllowed) { $0 }]
    }
}

/// Privatsphäre-Modus, sobald die Klasse Schüler hat und die App ein paar Mal geöffnet wurde.
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

    var actions: [Action] {
        [Action(id: "open", title: loc("Einschalten"))]
    }

    var rules: [Rule] {
        [
            #Rule(SetupTip.$isAllowed) { $0 },
            #Rule(Self.appOpened) { $0.donations.count >= 3 },
        ]
    }
}

/// „Kacheln anordnen“, erst nach dem Tipp zum Privatsphäre-Modus.
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

    var actions: [Action] {
        [Action(id: "open", title: loc("Jetzt anordnen"))]
    }

    var rules: [Rule] {
        [
            #Rule(SetupTip.$isAllowed) { $0 },
            #Rule(Self.$isPrivacyTipDone) { $0 },
            #Rule(Self.dashboardOpened) { $0.donations.count >= 5 },
        ]
    }
}

/// Welche Tipps TipKit gerade zeigen würde (Regeln erfüllt, nicht geschlossen), nach Tipp-ID.
/// Beobachtet in `RootView`, damit die Kacheln ohne eigene Aufgabe reagieren und ganz verschwinden können.
@Observable
final class TipVisibility {
    static let shared = TipVisibility()

    private(set) var displayable: Set<String> = []

    func contains(_ tip: some Tip) -> Bool {
        displayable.contains(tip.id)
    }

    /// Je Tipp eine Beobachtung; endet mit der aufrufenden Aufgabe (`.task` in `RootView`).
    func observe() async {
        let tasks = SetupStep.allCases.map { track(SetupTip($0)) } + [track(PrivacyModeTip()), track(ArrangeCardsTip())]
        await withTaskCancellationHandler {
            for task in tasks { await task.value }
        } onCancel: {
            for task in tasks { task.cancel() }
        }
    }

    private func track(_ tip: some Tip) -> Task<Void, Never> {
        let id = tip.id
        return Task {
            for await shouldDisplay in tip.shouldDisplayUpdates {
                if shouldDisplay { displayable.insert(id) } else { displayable.remove(id) }
            }
        }
    }
}

/// Tipp-Kachel der Übersicht, immer nur ein Tipp: zuerst der offene Einrichtungsschritt, dann Privatsphäre-Modus,
/// dann „Kacheln anordnen“. Ohne Klasse (`schoolClass == nil`) nur Schritt 1 „Erste Klasse anlegen“ über dem
/// Leerzustand. TipKit-Optik (xmark oben rechts, Button unter der Trennlinie) in der Form einer Kachel.
struct DashboardTipCard: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.device) private var device
    @Query private var classes: [SchoolClass]
    @Query private var holidays: [Holiday]
    @AppStorage(AppPreference.hasOpenedSchoolSettings) private var hasOpenedSchoolSettings = false
    let schoolClass: SchoolClass?
    var onArrange: () -> Void = {}

    private enum Content {
        case setup(SetupStep)
        case privacy
        case arrange
    }

    /// Schritt 1 sichtbar (für den Leerzustand der Übersicht, siehe `ClassScopedView`).
    static func showsFirstClassTip(classes: [SchoolClass]) -> Bool {
        classes.isEmpty && TipVisibility.shared.contains(SetupTip(.createClass))
    }

    private var content: Content? {
        let visibility = TipVisibility.shared
        guard let schoolClass else {
            return Self.showsFirstClassTip(classes: classes) ? .setup(.createClass) : nil
        }
        let state = SetupStep.State(
            classes: classes,
            selectedClass: schoolClass,
            settings: settings.values,
            hasOpenedSchoolSettings: hasOpenedSchoolSettings,
            holidayCount: holidays.count
        )
        if let step = SetupStep.current(state), step != .createClass, visibility.contains(SetupTip(step)) {
            return .setup(step)
        }
        if !schoolClass.students.isEmpty, visibility.contains(PrivacyModeTip()) { return .privacy }
        if visibility.contains(ArrangeCardsTip()) { return .arrange }
        return nil
    }

    var body: some View {
        switch content {
        case .setup(let step):
            card(SetupTip(step, image: Image(icon: step.icon))) { open(step) }
        case .privacy:
            card(PrivacyModeTip(image: Image(icon: .eyeClosed))) {
                PrivacyModeTip().invalidate(reason: .actionPerformed)
                if !security.isPrivacyModeOn { Task { await security.togglePrivacyMode() } }
            }
        case .arrange:
            card(ArrangeCardsTip(image: Image(icon: .editPencil))) {
                ArrangeCardsTip().invalidate(reason: .actionPerformed)
                onArrange()
            }
        case nil:
            EmptyView()
        }
    }

    private func card(_ tip: some Tip, action: @escaping () -> Void) -> some View {
        TipView(tip) { _ in action() }
            .tipBackground(.clear)
            .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .top)
            .background(Color(.secondarySystemGroupedBackground), in: cardShape)
    }

    private func open(_ step: SetupStep) {
        switch step {
        case .createClass: app.isClassPickerPresented = true
        case .addStudents: app.open(.students)
        case .createSchedule: app.openCalendar(focusing: schoolClass?.id)
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
