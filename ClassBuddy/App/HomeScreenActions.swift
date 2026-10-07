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
                localizedTitle: loc("Kalender"),
                localizedSubtitle: loc("Stundenplan dieser Woche"),
                icon: Self.shortcutIcon(.calendar)
            )
        case .feedback:
            UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: loc("Bitte nicht löschen"),
                localizedSubtitle: loc("Sagen Sie mir lieber, was fehlt"),
                icon: Self.shortcutIcon(.sendMail)
            )
        }
    }

    /// Symbol im aktiven Icon-Theme (Iconoir aus dem Katalog bzw. SF Symbol).
    private static func shortcutIcon(_ icon: AppIcon) -> UIApplicationShortcutIcon {
        if IconManager.shared.theme == .sfSymbols, let name = IconTheme.sfSymbolNames[icon] {
            return UIApplicationShortcutIcon(systemImageName: name)
        }
        return UIApplicationShortcutIcon(templateImageName: icon.rawValue)
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
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FunStat.appLaunches.increment()
        // Vor dem Öffnen der Datenbank (das passiert erst mit der ersten Szene).
        DataProtectionMigration.runIfNeeded()
        return true
    }

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
