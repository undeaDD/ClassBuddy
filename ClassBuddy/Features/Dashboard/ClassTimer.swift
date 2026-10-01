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

    /// Wird beim Ablaufen im Vordergrund aufgerufen (z. B. Toast anzeigen).
    var onFinish: (() -> Void)?

    private var finishTask: Task<Void, Never>?
    private static let endKey = "timer.endDate"
    private static let durationKey = "timer.durationMinutes"
    private static let notificationID = "classbuddy.timer"

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.object(forKey: Self.endKey) as? Date, saved > .now {
            endDate = saved
            durationMinutes = defaults.integer(forKey: Self.durationKey)
            scheduleFinish()
        }
    }

    var isRunning: Bool { endDate.map { $0 > .now } ?? false }

    func start(minutes: Int) {
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
        finishTask?.cancel()
        endDate = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    /// Restzeit als „mm:ss“ bzw. „h:mm:ss“.
    static func remainingText(until end: Date, now: Date) -> String {
        let seconds = max(Int(end.timeIntervalSince(now).rounded(.up)), 0)
        let (hours, minutes, rest) = (seconds / 3600, seconds % 3600 / 60, seconds % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%02d:%02d", minutes, rest)
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
        // Im Vordergrund: Ton + Rückmeldung; die Mitteilung ist dann überflüssig.
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        AudioServicesPlaySystemSound(1005)
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
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(endDate.timeIntervalSinceNow, 1), repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        try? await center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }
}

/// Timer-Kachel: Dauer wählen, Countdown, verlängern oder stoppen (über ein Menü).
struct TimerCard: View {
    @Environment(ClassTimer.self) private var timer

    var body: some View {
        Menu {
            if timer.isRunning {
                Button("+1 Minute", image: .plus) { timer.extend(byMinutes: 1) }
                Button("+5 Minuten", image: .plus) { timer.extend(byMinutes: 5) }
                Button("Stoppen", image: .xmark, role: .destructive) { timer.stop() }
            } else {
                ForEach(ClassTimer.presets, id: \.self) { minutes in
                    Button("\(minutes) Minuten") { timer.start(minutes: minutes) }
                }
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
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: DashboardBuiltInCard.timer.title, symbol: DashboardBuiltInCard.timer.symbol, showsChevron: true)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                if let end = timer.endDate, end > now {
                    Text(ClassTimer.remainingText(until: end, now: now))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText(countsDown: true))
                    Text("\(timer.durationMinutes) min · endet um \(end.appFormatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Starten")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("Antippen, um eine Dauer zu wählen")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
        .cardStyle()
    }
}
