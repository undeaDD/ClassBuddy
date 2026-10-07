import SwiftUI

/// Kachel „Sekretariat“: anrufen oder E-Mail schreiben. Die Knöpfe sind nur aktiv,
/// wenn Telefon bzw. E-Mail in den Schuleinstellungen eingetragen sind.
struct SecretariatCard: View {
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    var body: some View {
        let card = DashboardBuiltInCard.secretariat
        let school = settings.values.school
        let phoneURL = Self.phoneURL(school.phone)
        let mailURL = Self.mailURL(school.email)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: card.title, symbol: card.symbol, showsChevron: false)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 12) {
                Text(phoneURL == nil && mailURL == nil
                    ? loc("Telefon und E-Mail in den Schuleinstellungen eintragen")
                    : (school.name.isEmpty ? loc("Schule") : school.name))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                actionButton(loc("Sekretariat anrufen"), icon: .phone, url: phoneURL)
                actionButton(loc("E-Mail an das Sekretariat"), icon: .sendMail, url: mailURL)
            }
        }
        .cardStyle()
    }

    private func actionButton(_ title: String, icon: AppIcon, url: URL?) -> some View {
        Button(title, icon: icon, action: Haptics.tapping { if let url { openURL(url) } })
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .disabled(url == nil)
            .help(title)
    }

    /// `tel:` nur mit Ziffern und führendem +.
    static func phoneURL(_ phone: String) -> URL? {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        guard digits.count >= 3 else { return nil }
        return URL(string: "tel:\(trimmed.hasPrefix("+") ? "+" : "")\(digits)")
    }

    static func mailURL(_ email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("@"), !trimmed.contains(" "),
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "mailto:\(encoded)")
    }
}
