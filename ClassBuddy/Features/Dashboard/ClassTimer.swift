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
        content.title = "Timer abgelaufen"
        content.body = "\(durationMinutes) Minuten sind um."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(endDate.timeIntervalSinceNow, 1), repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
        try? await center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }
}
