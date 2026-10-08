import SwiftUI
import UIKit

/// Akzentfarbe der App (App-Einstellungen → Darstellung). Gespeichert als Kennung einer Vorgabe
/// (`amber`, `blue` …) oder als eigene Farbe (`#RRGGBB`); Standard ist das ClassBuddy-Braun.
///
/// Wirkt über `.tint(…)` an der Wurzel (SwiftUI-Stil `.tint`), `\.appAccent` für Stellen, die eine
/// `Color` brauchen (Verläufe, Glas, Wisch-Aktionen), und die Tint-Farbe der Fenster (UIKit).
nonisolated enum AppAccent {
    static let storageKey = "app.accentColor"
    static let defaultValue = "amber"

    struct Preset: Identifiable {
        let id: String
        let name: LocalizedStringResource
        let color: UIColor
    }

    static let presets: [Preset] = [
        Preset(id: "amber", name: "Bernstein", color: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.804, green: 0.612, blue: 0.369, alpha: 1)
                : UIColor(red: 0.612, green: 0.408, blue: 0.188, alpha: 1)
        }),
        Preset(id: "blue", name: "Blau", color: .systemBlue),
        Preset(id: "indigo", name: "Indigo", color: .systemIndigo),
        Preset(id: "purple", name: "Lila", color: .systemPurple),
        Preset(id: "pink", name: "Pink", color: .systemPink),
        Preset(id: "red", name: "Rot", color: .systemRed),
        Preset(id: "orange", name: "Orange", color: .systemOrange),
        Preset(id: "green", name: "Grün", color: .systemGreen),
        Preset(id: "mint", name: "Mint", color: .systemMint),
        Preset(id: "teal", name: "Türkis", color: .systemTeal),
        Preset(id: "graphite", name: "Graphit", color: .systemGray),
    ]

    /// Farbe zu einem gespeicherten Wert; Unbekanntes fällt auf den Standard zurück.
    static func uiColor(for value: String) -> UIColor {
        if let preset = presets.first(where: { $0.id == value }) { return preset.color }
        if value.hasPrefix("#"), let color = Color(hex: value) { return UIColor(color) }
        return presets[0].color
    }

    static func color(for value: String) -> Color {
        Color(uiColor: uiColor(for: value))
    }

    /// Gültiger gespeicherter Wert (Vorgabe oder `#RRGGBB`), z. B. beim Excel-Import.
    static func isValid(_ value: String) -> Bool {
        presets.contains { $0.id == value } || (value.hasPrefix("#") && Color(hex: value) != nil)
    }

    /// `#RRGGBB` für hell bzw. dunkel – für die CSS der lokalen HTML-Seiten.
    static func cssHex(for value: String, dark: Bool) -> String {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        return Color(uiColor: uiColor(for: value).resolvedColor(with: traits)).hexString
    }

    /// Setzt die Tint-Farbe der Fenster (UIKit: Alerts, Menüs, Datumsauswahl …).
    @MainActor
    static func apply(_ value: String) {
        let color = uiColor(for: value)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.tintColor = color
            }
        }
        LegacyBackButton.apply(accent: color)
    }
}

extension EnvironmentValues {
    /// Akzentfarbe als `Color` – für Stellen, an denen der Stil `.tint` nicht reicht.
    @Entry var appAccent = AppAccent.color(for: AppAccent.defaultValue)
}
