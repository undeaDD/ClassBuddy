import Foundation

/// Anruf- und Mail-Links aus frei eingegebenen Angaben (Sekretariat, Kontakt von Schülerinnen und Schülern).
nonisolated enum ContactURL {
    /// `tel:` nur mit Ziffern und führendem +; `nil` bei weniger als 3 Ziffern.
    static func phone(_ phone: String) -> URL? {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        guard digits.count >= 3 else { return nil }
        return URL(string: "tel:\(trimmed.hasPrefix("+") ? "+" : "")\(digits)")
    }

    /// `mailto:` nur für Adressen mit @ und ohne Leerzeichen.
    static func mail(_ email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@"), !trimmed.contains(" "),
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "mailto:\(encoded)")
    }
}
