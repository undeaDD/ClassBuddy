import Foundation
import UIKit

/// App-Metadaten (Version, Feedback-Adresse).
enum AppInfo {
    /// Empfänger für „Feedback“.
    static let feedbackEmail = "dominic.drees@live.de"

    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    /// mailto-Link mit Betreff und Geräte-Infos im Text.
    static var feedbackMailURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "ClassBuddy Feedback"),
            URLQueryItem(name: "body", value: """


                ---
                ClassBuddy \(version)
                \(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
                """),
        ]
        return components.url ?? URL(string: "mailto:")!
    }
}
