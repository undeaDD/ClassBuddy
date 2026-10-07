import SwiftUI

/// Kachel „Sekretariat“: anrufen oder E-Mail schreiben. Die Knöpfe sind nur aktiv,
/// wenn Telefon bzw. E-Mail in den Schuleinstellungen eingetragen sind.
struct SecretariatCard: View {
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    /// Galerie-Vorschau: beide Knöpfe aktiv, unabhängig von den Schuleinstellungen.
    var isPreview = false

    /// Fehlende Angabe angetippt → Hinweis auf die Schuleinstellungen.
    @State private var missingField: String?

    /// Abstand zum Kartenrand (auch unten) und zwischen den Knöpfen (wie bei allen Kacheln).
    private static let spacing: CGFloat = 18

    var body: some View {
        let card = DashboardBuiltInCard.secretariat
        let school = settings.values.school
        let phoneURL = isPreview ? URL(string: "tel:0") : Self.phoneURL(school.phone)
        let mailURL = isPreview ? URL(string: "mailto:a@b.de") : Self.mailURL(school.email)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: card.title, symbol: card.symbol, showsChevron: false)
            // Knöpfe füllen den Rest der Kachel: unten bleibt so immer genau `spacing` Abstand.
            HStack(spacing: Self.spacing) {
                actionButton(loc("Telefon"), help: loc("Sekretariat anrufen"), icon: .phone, url: phoneURL)
                actionButton(loc("E-Mail"), help: loc("E-Mail an das Sekretariat"), icon: .sendMail, url: mailURL)
            }
        }
        .cardStyle(padding: Self.spacing)
        .alert(
            missingField.map { loc("\($0) fehlt") } ?? "",
            isPresented: Binding(get: { missingField != nil }, set: { if !$0 { missingField = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bitte in den Schuleinstellungen die Telefonnummer und E-Mail-Adresse des Sekretariats eintragen.")
        }
    }

    /// Symbol mit kleiner Beschriftung darunter (wie ein Tab-Leisten-Eintrag).
    /// Ohne Angabe ausgegraut; Antippen erklärt dann, wo sie eingetragen wird.
    private func actionButton(_ title: String, help: String, icon: AppIcon, url: URL?) -> some View {
        Button(action: Haptics.tapping {
            guard !isPreview else { return }
            if let url { openURL(url) } else { missingField = title }
        }) {
            VStack(spacing: 4) {
                Image(icon: icon)
                    .iconSize(24)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .opacity(url == nil ? 0.35 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 20))
        .help(help)
        .accessibilityLabel(help)
        .accessibilityHint(url == nil ? loc("Noch nicht eingetragen") : "")
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
