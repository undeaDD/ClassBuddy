import SwiftUI

// Privatsphäre-Modus:
// Die Root-View setzt `.redacted(reason: .privacy)`, solange der Modus aktiv ist.
// Jede View, die sensible Daten zeigt (Namen, Noten, Notizen …), markiert sich mit
// `.sensitive()` – Text wird dann durch native Platzhalter ersetzt.
// Für Bilder/Grafiken gibt es `.sensitiveBlur()`.

extension View {
    /// Text/Inhalt im Privatsphäre-Modus schwärzen.
    func sensitive() -> some View {
        privacySensitive()
    }

    /// Inhalt im Privatsphäre-Modus weichzeichnen (für Fotos, Diagramme, Sitzpläne …).
    func sensitiveBlur(radius: CGFloat = 16) -> some View {
        modifier(SensitiveBlurModifier(radius: radius))
    }
}

private struct SensitiveBlurModifier: ViewModifier {
    @Environment(\.redactionReasons) private var reasons
    let radius: CGFloat

    func body(content: Content) -> some View {
        let hidden = reasons.contains(.privacy)
        content
            .blur(radius: hidden ? radius : 0)
            .allowsHitTesting(!hidden)
            .animation(.smooth, value: hidden)
    }
}
