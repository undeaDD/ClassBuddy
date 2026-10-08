import CoreGraphics

/// Entscheidet aus der Scroll-Position, ob die eigene Tab-Leiste (`FloatingTabView`) minimiert sein soll:
/// Runterscrollen minimiert, Hochscrollen oder ganz oben vergrößert. Nur echte Gesten zählen.
/// Positionen werden auf den scrollbaren Bereich begrenzt, damit Nachfedern oben und unten nichts auslöst.
struct TabBarScrollTracker {
    /// Ab dieser Strecke (pt) in eine Richtung wechselt die Leiste.
    static let threshold: CGFloat = 24

    private var lastOffset: CGFloat = 0
    /// Strecke in eine Richtung seit dem letzten Richtungswechsel (positiv = runter).
    private var travelled: CGFloat = 0

    /// Neue Scroll-Ansicht (anderer Tab, Unterseite): ab hier messen.
    mutating func reset(offset: CGFloat, top: CGFloat, bottom: CGFloat) {
        lastOffset = Self.clamped(offset, top: top, bottom: bottom)
        travelled = 0
    }

    /// - Parameters:
    ///   - offset: `contentOffset.y`
    ///   - top: kleinste Position (`-adjustedContentInset.top`)
    ///   - bottom: größte Position (ganz unten)
    ///   - isUserScrolling: Finger liegt auf oder die Ansicht rollt nach einer Geste aus
    /// - Returns: `true` = minimieren, `false` = vergrößern, `nil` = unverändert lassen.
    mutating func update(offset: CGFloat, top: CGFloat, bottom: CGFloat, isUserScrolling: Bool) -> Bool? {
        let offset = Self.clamped(offset, top: top, bottom: bottom)
        defer { lastOffset = offset }
        if offset <= top + 1 {
            travelled = 0
            return false
        }
        guard isUserScrolling else { return nil }
        let delta = offset - lastOffset
        guard delta != 0 else { return nil }
        if (delta > 0) != (travelled > 0) { travelled = 0 }
        travelled += delta
        if travelled > Self.threshold { return true }
        if travelled < -Self.threshold { return false }
        return nil
    }

    private static func clamped(_ offset: CGFloat, top: CGFloat, bottom: CGFloat) -> CGFloat {
        min(max(offset, top), max(top, bottom))
    }
}
