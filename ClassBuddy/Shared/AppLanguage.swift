import Foundation
import SwiftUI

/// Sprache der App, unabhängig von der Systemsprache (App-Einstellungen → Sprache).
/// Deutsch ist die Ausgangssprache (Schlüssel = deutscher Text), Englisch steht in `Localizable.xcstrings`.
///
/// - SwiftUI-Texte (`Text("…")`, `Label`, `Button` …) folgen `.environment(\.locale, …)` an der Wurzel.
/// - Texte aus Code (`String`) laufen über `loc(…)`, das die gewählte Sprache explizit mitgibt.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case german = "de"
    case english = "en"

    var id: String { rawValue }
    static let storageKey = "app.language"

    /// Gewählte Sprache, zwischengespeichert für `loc(…)` (wird sehr oft gelesen).
    nonisolated(unsafe) static var current: AppLanguage = stored

    static var stored: AppLanguage {
        UserDefaults.standard.string(forKey: storageKey).flatMap { AppLanguage(rawValue: $0) } ?? .system
    }

    /// Name in der jeweiligen Sprache selbst, damit man ihn auch ohne Kenntnis der aktuellen findet.
    var title: String {
        switch self {
        case .system: loc("System")
        case .german: "Deutsch"
        case .english: "English"
        }
    }

    /// Wert im Excel-Backup (Blatt „App“, Schlüssel „Sprache“).
    var backupTitle: String {
        switch self {
        case .system: "System"
        case .german: "Deutsch"
        case .english: "Englisch"
        }
    }

    init?(backupTitle: String) {
        let text = backupTitle.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = Self.allCases.first(where: {
            $0.backupTitle.lowercased() == text || $0.rawValue == text || $0.title.lowercased() == text
        }) else { return nil }
        self = match
    }

    /// Tatsächlich verwendete Sprache. „System“: die erste bevorzugte Systemsprache, die Deutsch oder
    /// Englisch ist (z. B. [Französisch, Deutsch] → Deutsch); sonst Englisch als verständlichster Rückfall.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        for identifier in Locale.preferredLanguages {
            switch Locale(identifier: identifier).language.languageCode?.identifier {
            case "de": return .german
            case "en": return .english
            default: continue
            }
        }
        return .english
    }

    /// Sprache plus Region des Geräts – für Texte und Datums-/Zahlenformate.
    var locale: Locale {
        let region = Locale.current.region?.identifier ?? (resolved == .english ? "US" : "DE")
        return Locale(identifier: "\(resolved.rawValue)_\(region)")
    }
}

/// Text aus Code in der gewählten App-Sprache, z. B. `loc("Einstellungen")` oder `loc("\(count) Schüler")`.
/// Literale landen automatisch im String Catalog (Parameter ist `LocalizedStringResource`).
nonisolated func loc(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    resource.locale = AppLanguage.current.locale
    return String(localized: resource)
}

extension Date {
    /// Wie `formatted(_:)`, aber in der App-Sprache (Monats- und Wochentagsnamen).
    nonisolated func appFormatted(_ style: Date.FormatStyle) -> String {
        formatted(style.locale(AppLanguage.current.locale))
    }

    nonisolated func appFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time, locale: AppLanguage.current.locale))
    }
}
