import AudioToolbox
import Foundation
import SwiftUI
import UserNotifications

/// App-weiter Unterrichts-Timer (ersetzt den nicht dokumentierten Sprung in die Uhr-App).
/// Das Ende wird gespeichert, damit der Timer einen Neustart der App übersteht; läuft die
/// App im Hintergrund, meldet sich eine lokale Mitteilung.
@Observable
final class ClassTimer {
    static let presets = [5, 10, 15, 20, 30, 45]

    private(set) var endDate: Date? {
        didSet { UserDefaults.standard.set(endDate, forKey: Self.endKey) }
    }
    private(set) var durationMinutes = 0 {
        didSet { UserDefaults.standard.set(durationMinutes, forKey: Self.durationKey) }
    }

    /// Start der Stoppuhr (zählt hoch); läuft nie gleichzeitig mit dem Timer.
    private(set) var stopwatchStart: Date? {
        didSet { UserDefaults.standard.set(stopwatchStart, forKey: Self.stopwatchKey) }
    }

    /// Wird beim Ablaufen im Vordergrund aufgerufen (z. B. Toast anzeigen).
    var onFinish: (() -> Void)?

    private var finishTask: Task<Void, Never>?
    private static let endKey = "timer.endDate"
    private static let durationKey = "timer.durationMinutes"
    private static let stopwatchKey = "timer.stopwatchStart"
    private static let notificationID = "classbuddy.timer"

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.object(forKey: Self.endKey) as? Date, saved > .now {
            endDate = saved
            durationMinutes = defaults.integer(forKey: Self.durationKey)
            scheduleFinish()
        }
        stopwatchStart = defaults.object(forKey: Self.stopwatchKey) as? Date
    }

    var isRunning: Bool { endDate.map { $0 > .now } ?? false }

    func start(minutes: Int) {
        stopStopwatch()
        durationMinutes = minutes
        endDate = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        scheduleFinish()
        Task { await scheduleNotification() }
    }

    func extend(byMinutes minutes: Int) {
        guard let endDate, isRunning else { return }
        self.endDate = endDate.addingTimeInterval(TimeInterval(minutes * 60))
        durationMinutes += minutes
        scheduleFinish()
        Task { await scheduleNotification() }
    }

    func stop() {
        // Bis zum Abbrechen gelaufene Minuten für die Stats.
        if let endDate, isRunning {
            let remaining = endDate.timeIntervalSinceNow / 60
            FunStat.timerMinutes.increment(by: Int((Double(durationMinutes) - remaining).rounded(.down)))
        }
        finishTask?.cancel()
        endDate = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    func startStopwatch() {
        if isRunning { stop() }
        stopwatchStart = .now
    }

    func stopStopwatch() {
        guard let stopwatchStart else { return }
        FunStat.timerMinutes.increment(by: Int(Date.now.timeIntervalSince(stopwatchStart) / 60))
        self.stopwatchStart = nil
    }

    /// Restzeit als „mm:ss“ bzw. „h:mm:ss“.
    static func remainingText(until end: Date, now: Date) -> String {
        durationText(seconds: max(Int(end.timeIntervalSince(now).rounded(.up)), 0))
    }

    /// Laufzeit der Stoppuhr als „mm:ss“ bzw. „h:mm:ss“.
    static func elapsedText(since start: Date, now: Date) -> String {
        durationText(seconds: max(Int(now.timeIntervalSince(start).rounded(.down)), 0))
    }

    private static func durationText(seconds: Int) -> String {
        let (hours, minutes, rest) = (seconds / 3600, seconds % 3600 / 60, seconds % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%02d:%02d", minutes, rest)
    }

    /// App-Einstellung „Timer nur vibrieren“ (nur iPhone).
    private static var vibratesOnly: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && UserDefaults.standard.bool(forKey: AppPreference.timerVibratesOnly)
    }

    private func scheduleFinish() {
        finishTask?.cancel()
        guard let endDate else { return }
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(endDate.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self else { return }
            self.finish()
        }
    }

    private func finish() {
        endDate = nil
        FunStat.timerMinutes.increment(by: durationMinutes)
        // Im Vordergrund: Ton + Rückmeldung; die Mitteilung ist dann überflüssig.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        AudioServicesPlaySystemSound(Self.vibratesOnly ? kSystemSoundID_Vibrate : 1005)
        onFinish?()
    }

    private func scheduleNotification() async {
        guard let endDate else { return }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = loc("Timer abgelaufen")
        content.body = loc("\(durationMinutes) Minuten sind um.")
        content.sound = Self.vibratesOnly ? nil : .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(endDate.timeIntervalSinceNow, 1), repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        try? await center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }
}

/// Timer-Kachel: Dauer wählen, Countdown, verlängern oder stoppen – oder Stoppuhr (über ein Menü).
struct TimerCard: View {
    @Environment(ClassTimer.self) private var timer

    var body: some View {
        Menu {
            if timer.isRunning {
                Button("+1 Minute", icon: .plus) { timer.extend(byMinutes: 1) }
                Button("+5 Minuten", icon: .plus) { timer.extend(byMinutes: 5) }
                Button("Stoppen", destructiveIcon: .xmark) { timer.stop() }
            } else if timer.stopwatchStart != nil {
                Button("Stoppuhr stoppen", destructiveIcon: .xmark) { timer.stopStopwatch() }
                Button("Neu starten", icon: .undo) { timer.startStopwatch() }
            } else {
                Section("Timer") {
                    ForEach(ClassTimer.presets, id: \.self) { minutes in
                        Button("\(minutes) Minuten") { timer.start(minutes: minutes) }
                    }
                }
                Button("Stoppuhr starten", icon: .time) { timer.startStopwatch() }
            }
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(now: context.date)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private func content(now: Date) -> some View {
        if let end = timer.endDate, end > now {
            TimerCardContent(remaining: ClassTimer.remainingText(until: end, now: now), detail: loc("\(timer.durationMinutes) min · endet um \(end.appTime)"))
        } else if let start = timer.stopwatchStart {
            TimerCardContent(
                remaining: ClassTimer.elapsedText(since: start, now: now),
                detail: loc("Stoppuhr · seit \(start.appTime)"),
                countsDown: false
            )
        } else {
            TimerCardContent(remaining: nil, detail: loc("Antippen für Timer oder Stoppuhr"))
        }
    }
}

/// Inhalt der Timer-Kachel (auch Galerie-Vorschau); ohne `remaining` „Starten“.
struct TimerCardContent: View {
    let remaining: String?
    let detail: String
    /// Timer zählt herunter, Stoppuhr hoch (Richtung der Ziffern-Animation).
    var countsDown = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: DashboardBuiltInCard.timer.title, symbol: DashboardBuiltInCard.timer.symbol, showsChevron: true)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                if let remaining {
                    Text(remaining)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .contentTransition(.numericText(countsDown: countsDown))
                } else {
                    Text("Starten")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .cardStyle()
    }
}
