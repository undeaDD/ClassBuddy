import Foundation
import UIKit

/// App-Metadaten (Version, Feedback-Adresse).
enum AppInfo {
    /// Empfänger für „Feedback“.
    static let feedbackEmail = "dominic.drees@live.de"

    /// Quellcode auf GitHub.
    static let sourceCodeURL = URL(string: "https://github.com/undeaDD/ClassBuddy")!

    /// Spendenlink (vorerst die PayPal-Startseite, persönlicher Link folgt).
    static let donationURL = URL(string: "https://www.paypal.com")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    /// mailto-Link für allgemeines Feedback.
    static var feedbackMailURL: URL { mailURL(subject: "ClassBuddy Feedback") }

    /// Geräte-Infos für Feedback (hilft bei der Fehlersuche, keine persönlichen Daten).
    static var deviceInfo: String {
        "ClassBuddy \(version) · \(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    /// mailto-Link an die Feedback-Adresse mit Betreff, Text und Geräte-Infos.
    /// `&`, `=` und `+` werden selbst kodiert, damit Betreff/Text nicht abgeschnitten werden.
    static func mailURL(subject: String, body: String = "") -> URL {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        let fullBody = body + "\n\n---\n" + deviceInfo
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "subject", value: subject.addingPercentEncoding(withAllowedCharacters: allowed)),
            URLQueryItem(name: "body", value: fullBody.addingPercentEncoding(withAllowedCharacters: allowed)),
        ]
        return components.url ?? URL(string: "mailto:\(feedbackEmail)")!
    }
}
