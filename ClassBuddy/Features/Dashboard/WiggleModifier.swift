import SwiftUI

// MARK: - Wackeln im Anordnen-Modus

extension View {
    /// Leichtes Wackeln wie auf dem Home-Bildschirm. Bewusst winzig, weil die Kacheln groß sind.
    /// `seed` verteilt Richtung und Tempo, damit nicht alle Kacheln im Gleichtakt wackeln.
    func wiggling(seed: String) -> some View {
        modifier(WiggleModifier(seed: seed))
    }
}

private struct WiggleModifier: ViewModifier {
    let seed: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Maximaler Ausschlag in Grad – bei ~320 pt Breite knapp 1 pt am Rand.
    private let amplitude = 0.35

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // Stabiler (nicht per Start zufälliger) Wert aus der Kachel-ID.
            let value = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
            let direction: Double = value.isMultiple(of: 2) ? 1 : -1
            let quarter = 0.065 + Double(value % 5) * 0.004

            content.keyframeAnimator(initialValue: 0.0, repeating: true) { view, angle in
                view.rotationEffect(.degrees(angle * direction))
            } keyframes: { _ in
                CubicKeyframe(amplitude, duration: quarter)
                CubicKeyframe(-amplitude, duration: quarter * 2)
                CubicKeyframe(0, duration: quarter)
            }
        }
    }
}
