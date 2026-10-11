import SwiftUI

// MARK: - Zustand (aus Stundenplan, Ferien, Wetter, Uhrzeit)

/// Stimmung des Buddys: bestimmt das Gesicht.
enum BuddyMood: Equatable {
    /// Laufende Stunde: wach, aufmerksam.
    case alert
    /// Pause, Freistunde, Nachmittag: entspannt (Musiknote).
    case relaxed
    /// Abends, nachts, Wochenende: schläft (Zzz), läuft nicht.
    case sleeping
    /// Kurz nach dem Antippen: glücklich (Herzen).
    case happy
    /// Regen: sitzt still mit X-Augen („kaputt“).
    case gloomy

    /// Steht still statt herumzulaufen.
    var isResting: Bool { self == .sleeping || self == .gloomy }
}

enum BuddyScene: String, Equatable {
    case classroom
    case outdoor
    case night
    case beach
    case rain

    /// Hintergrund-Bild im Asset-Katalog (`buddy-bg-classroom` …); fehlt es, wird der Hintergrund gezeichnet.
    var backgroundAsset: String { "buddy-bg-\(rawValue)" }
    /// Optionale Vordergrund-Ebene vor dem Buddy (z. B. Busch), transparentes PNG gleicher Größe.
    var foregroundAsset: String { "buddy-fg-\(rawValue)" }

    /// Höhe der Füße über dem unteren Rand (Anteil der Kachelhöhe): Mitte des Bodenstreifens im Bild.
    var feetHeight: CGFloat {
        switch self {
        case .classroom: 0.062
        case .outdoor: 0.071
        case .night: 0.075
        case .beach: 0.09
        case .rain: 0.082
        }
    }

    /// Füße über dem Rand in Punkt: mit Hintergrundbild auf dessen Boden, gezeichnet fest 24 pt.
    func groundInset(height: CGFloat) -> CGFloat {
        UIImage(named: backgroundAsset) != nil ? feetHeight * height : 24
    }
}

enum BuddyAccessory: Equatable {
    case none
    case sunglasses
}

/// Eingaben von der Übersicht (einmal pro Minute neu berechnet).
struct BuddyContext: Equatable {
    var isLessonRunning = false
    var isSchoolDay = true
    var isHoliday = false
    var isRaining = false
    var isNight = false

    /// Grundzustand ohne Antippen.
    var mood: BuddyMood {
        if isNight || (!isSchoolDay && !isHoliday) { return .sleeping }
        if isRaining { return .gloomy }
        if isLessonRunning { return .alert }
        return .relaxed
    }

    var scene: BuddyScene {
        if mood == .sleeping { return .night }
        if isRaining { return .rain }
        if isHoliday { return .beach }
        return isLessonRunning ? .classroom : .outdoor
    }

    var accessory: BuddyAccessory {
        mood == .relaxed && isHoliday ? .sunglasses : .none
    }

    /// Aus dem Stundenplan aller Klassen: Nacht ab 20 Uhr bis 6 Uhr, Ferien, angezeigte Schultage, laufende Stunde.
    static func make(schedule: LessonSchedule, visibleWeekdays: [Int], isRaining: Bool, now: Date) -> Self {
        let calendar = Calendar.school
        let hour = calendar.component(.hour, from: now)
        let minute = hour * 60 + calendar.component(.minute, from: now)
        let isHoliday = schedule.holiday(on: now) != nil
        let isSchoolDay = !isHoliday && visibleWeekdays.contains(calendar.mondayBasedWeekday(of: now))
        let slot = schedule.slots.first { $0.start <= minute && minute < $0.end }
        let isLessonRunning = isSchoolDay && slot.flatMap { schedule.lesson(on: now, slotIndex: $0.index) } != nil
        return Self(
            isLessonRunning: isLessonRunning,
            isSchoolDay: isSchoolDay,
            isHoliday: isHoliday,
            isRaining: isRaining,
            isNight: hour >= 20 || hour < 6
        )
    }
}

// MARK: - Bewegung (reine Funktion der Zeit)

/// Alles, was das Maskottchen pro Frame braucht. Werte sind normiert, die Views skalieren auf ihre Größe.
struct BuddyPose: Equatable {
    /// Horizontale Position 0 (links) … 1 (rechts) innerhalb des Laufbereichs.
    var x: Double = 0.5
    var facingRight = true
    var isWalking = false
    /// 0 … 1, läuft beim Gehen zweimal pro Sekunde durch (Beine).
    var stepPhase: Double = 0
    /// Augen gerade zu (kurzes Blinzeln).
    var isBlinking = false
    /// Sprunghöhe 0 … 1 (0 = am Boden), nur nach dem Antippen.
    var jump: Double = 0
    /// Herzen 0 … 1 (Einblenden/Aufsteigen), nur nach dem Antippen.
    var hearts: Double = 0
    /// Atmen/Schlafen 0 … 1, für sanftes Heben und „Zzz“.
    var breath: Double = 0
    /// 0 … 1, läuft jede Sekunde einmal durch (fallender Regen).
    var rainPhase: Double = 0
}

enum BuddyMotion {
    /// Laufzyklus: 12 s – rechts laufen, stehen, links laufen, stehen.
    static let cycle: Double = 12
    static let jumpDuration: Double = 0.7
    static let heartsDuration: Double = 1.4

    static func pose(at date: Date, mood: BuddyMood, tappedAt: Date?) -> BuddyPose {
        let time = date.timeIntervalSinceReferenceDate
        var pose = BuddyPose()
        pose.breath = (sin(time * 2 * .pi / 3.5) + 1) / 2
        pose.rainPhase = time.truncatingRemainder(dividingBy: 1)

        if !mood.isResting {
            let phase = time.truncatingRemainder(dividingBy: cycle)
            switch phase {
            case ..<4:
                pose = walking(pose, from: 0.15, to: 0.85, progress: phase / 4, time: time)
            case ..<6:
                pose.x = 0.85
                pose.facingRight = true
            case ..<10:
                pose = walking(pose, from: 0.85, to: 0.15, progress: (phase - 6) / 4, time: time)
            default:
                pose.x = 0.15
                pose.facingRight = false
            }
            // Alle 4 s für 0,15 s blinzeln.
            pose.isBlinking = time.truncatingRemainder(dividingBy: 4) < 0.15
        }

        if let tappedAt {
            let elapsed = date.timeIntervalSince(tappedAt)
            if elapsed >= 0, elapsed < jumpDuration {
                pose.jump = sin(.pi * elapsed / jumpDuration)
            }
            if elapsed >= 0, elapsed < heartsDuration {
                pose.hearts = elapsed / heartsDuration
            }
        }
        return pose
    }

    private static func walking(_ pose: BuddyPose, from start: Double, to end: Double, progress: Double, time: Double) -> BuddyPose {
        var pose = pose
        // Weich anfahren und abbremsen.
        let eased = progress * progress * (3 - 2 * progress)
        pose.x = start + (end - start) * eased
        pose.facingRight = end > start
        pose.isWalking = true
        pose.stepPhase = (time * 2).truncatingRemainder(dividingBy: 1)
        return pose
    }
}

// MARK: - Kachel

/// „Buddy“: kleines Maskottchen, das in der Kachel herumläuft und auf den Schultag reagiert (ohne Titel und Icon,
/// die ganze Kachel ist seine Welt). Antippen: Sprung mit Herzen.
/// Pausiert (steht still, zeigt aber den Ausdruck) beim Anordnen, im Privatsphäre-Modus, bei „Bewegung reduzieren“,
/// im Hintergrund und wenn die Kachel nicht sichtbar ist.
struct BuddyCard: View {
    let context: BuddyContext
    /// Übersicht im Anordnen-Modus bzw. Vorschau in der Galerie: nichts animieren.
    var isPaused = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSecurity.self) private var security
    @State private var isVisible = false
    @State private var tappedAt: Date?

    private var isAnimationPaused: Bool {
        isPaused || !isVisible || reduceMotion || security.isPrivacyModeOn || scenePhase != .active
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isAnimationPaused)) { timeline in
            let isHappy = tappedAt.map { timeline.date.timeIntervalSince($0) < BuddyMotion.heartsDuration } ?? false
            let mood = isHappy ? BuddyMood.happy : context.mood
            // Pausiert: feste Pose in der Mitte statt eingefrorenem Zwischenschritt (Sprung nach dem Antippen läuft weiter).
            let pose = isAnimationPaused && !isHappy
                ? BuddyPose(x: 0.5, breath: 0.5)
                : BuddyMotion.pose(at: timeline.date, mood: mood, tappedAt: tappedAt)

            GeometryReader { proxy in
                ZStack {
                    BuddyBackgroundView(scene: context.scene, rainPhase: pose.rainPhase, size: proxy.size)
                    BuddyMascotView(
                        pose: pose, mood: mood, accessory: context.accessory, size: proxy.size,
                        groundInset: context.scene.groundInset(height: proxy.size.height)
                    )
                    BuddySceneImage(name: context.scene.foregroundAsset, size: proxy.size)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipShape(cardShape)
        .contentShape(cardShape)
        .contentShape(.hoverEffect, cardShape)
        .contentShape(.dragPreview, cardShape)
        .onTapGesture {
            // Schlafend oder bei Regen reagiert er nicht.
            guard !isPaused, !context.mood.isResting else { return }
            // Erst nach dem letzten Sprung (samt Herzen) wieder springen.
            if let tappedAt, Date.now.timeIntervalSince(tappedAt) < BuddyMotion.heartsDuration { return }
            Haptics.tap()
            tappedAt = .now
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        switch context.mood {
        case .alert: loc("Buddy passt im Unterricht auf")
        case .relaxed: loc("Buddy macht Pause")
        case .sleeping: loc("Buddy schläft")
        case .happy: loc("Buddy freut sich")
        case .gloomy: loc("Buddy mag keinen Regen")
        }
    }
}

/// Buddy auf der Übersicht: Zustand aus Stundenplan und Ferien (jede Minute neu), Regen nur aus dem Wetter, das die
/// Wetter-Kachel ohnehin geladen hat (Buddy fragt selbst nichts im Internet ab, siehe Datenschutzerklärung).
struct DashboardBuddyCard: View {
    @Environment(SchoolSettings.self) private var settings
    let schedule: LessonSchedule
    var isArranging = false

    @State private var isRaining = false
    #if DEBUG
    @AppStorage(BuddyDebugState.storageKey) private var debugState: BuddyDebugState = .real
    #endif

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            BuddyCard(context: context(at: timeline.date), isPaused: isArranging)
            .task(id: Int(timeline.date.timeIntervalSince1970 / 300)) {
                isRaining = await WeatherService.cachedSnapshot(for: settings.values.school)?.condition.isRainy ?? false
            }
        }
    }

    private func context(at date: Date) -> BuddyContext {
        #if DEBUG
        if let context = debugState.context { return context }
        #endif
        return .make(schedule: schedule, visibleWeekdays: settings.visibleWeekdays, isRaining: isRaining, now: date)
    }
}

#if DEBUG
/// Debug-Menü: Buddy-Zustand fest vorgeben statt aus Stundenplan, Ferien und Wetter.
enum BuddyDebugState: String, CaseIterable, Identifiable {
    case real
    case lesson
    case breakTime
    case holiday
    case rain
    case night

    static let storageKey = "debug.buddyState"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .real: "Echt"
        case .lesson: "Unterricht"
        case .breakTime: "Pause"
        case .holiday: "Ferien"
        case .rain: "Regen"
        case .night: "Nacht"
        }
    }

    var context: BuddyContext? {
        switch self {
        case .real: nil
        case .lesson: BuddyContext(isLessonRunning: true)
        case .breakTime: BuddyContext()
        case .holiday: BuddyContext(isSchoolDay: false, isHoliday: true)
        case .rain: BuddyContext(isRaining: true)
        case .night: BuddyContext(isNight: true)
        }
    }
}
#endif

/// Bild einer Szene, füllt die Kachel und bleibt unten ausgerichtet (der Boden liegt immer gleich hoch);
/// nichts, wenn das Bild nicht im Asset-Katalog liegt.
struct BuddySceneImage: View {
    let name: String
    let size: CGSize

    var body: some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height, alignment: .bottom)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        BuddyCard(context: BuddyContext(isLessonRunning: true))
        BuddyCard(context: BuddyContext(isHoliday: true))
        BuddyCard(context: BuddyContext(isRaining: true))
        BuddyCard(context: BuddyContext(isNight: true))
    }
    .padding()
    .frame(width: 360)
    .environment(AppSecurity())
}
