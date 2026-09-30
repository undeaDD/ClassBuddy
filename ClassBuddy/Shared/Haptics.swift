import UIKit

/// Haptisches Feedback bei Taps (App-Einstellung „Haptisches Feedback“, standardmäßig aus).
/// Einfach an der Stelle aufrufen, an der die Aktion passiert: `Haptics.tap()`.
enum Haptics {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreference.hapticFeedback)
    }

    /// Kachel, Button: kurzer, leichter Impuls.
    static func tap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Auswahl gewechselt (z. B. aktive Klasse).
    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Aktion mit vorangestelltem `tap()`, z. B. `Button(action: Haptics.tapping(action))`.
    static func tapping(_ action: @escaping () -> Void) -> () -> Void {
        {
            tap()
            action()
        }
    }

    /// Ergebnis einer Aktion (Toasts).
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
