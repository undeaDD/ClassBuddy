import SwiftUI
import UIKit

/// Schnellaktionen beim langen Drücken auf das App-Icon (Home-Bildschirm):
/// Kalender öffnen und – direkt neben „App entfernen“ – Feedback statt Deinstallieren.
/// Icons kommen aus dem eigenen Asset-Katalog (Template-Bilder), keine SF Symbols.
enum HomeScreenAction: String {
    case calendar = "de.devsforge.ClassBuddy.calendar"
    case feedback = "de.devsforge.ClassBuddy.feedback"

    var shortcutItem: UIApplicationShortcutItem {
        switch self {
        case .calendar:
            UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: "Kalender",
                localizedSubtitle: loc("Stundenplan dieser Woche"),
                icon: UIApplicationShortcutIcon(templateImageName: "calendar")
            )
        case .feedback:
            UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: loc("Bitte nicht löschen"),
                localizedSubtitle: loc("Sag mir lieber, was fehlt"),
                icon: UIApplicationShortcutIcon(templateImageName: "send-mail")
            )
        }
    }

    static func register() {
        UIApplication.shared.shortcutItems = [HomeScreenAction.calendar, .feedback].map(\.shortcutItem)
    }
}

/// Zuletzt gewählte Schnellaktion; `RootView` führt sie aus (auch nach dem Entsperren).
@Observable
final class HomeScreenActionCenter {
    static let shared = HomeScreenActionCenter()
    var pending: HomeScreenAction?
}

/// Nimmt Schnellaktionen entgegen – beim Kaltstart (`connectionOptions`) und bei laufender App.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            HomeScreenActionCenter.shared.pending = HomeScreenAction(rawValue: item.type)
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let action = HomeScreenAction(rawValue: shortcutItem.type)
        HomeScreenActionCenter.shared.pending = action
        completionHandler(action != nil)
    }
}
