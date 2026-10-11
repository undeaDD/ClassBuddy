import SwiftUI

// MARK: - Maskottchen

/// Zeichnet den Buddy: cremeweißer Würfel-Roboter mit Bildschirm-Gesicht, orangem Ohr-Knopf und kurzen Beinen.
/// Gezeichnet wird immer mit Blick nach rechts; nach links dreht ihn allein die Spiegelung.
/// Steht unten auf dem Boden (ca. 24 pt über dem Rand) und läuft zwischen 10 % und 90 % der Breite (`pose.x`).
struct BuddyMascotView: View {
    let pose: BuddyPose
    let mood: BuddyMood
    let accessory: BuddyAccessory
    let size: CGSize
    /// Füße über dem unteren Rand (Boden des Hintergrunds).
    var groundInset: CGFloat = 24

    private static let bodyColor = Color(red: 0.97, green: 0.96, blue: 0.94)
    private static let screenColor = Color(red: 0.17, green: 0.20, blue: 0.25)
    private static let earColor = Color(red: 0.96, green: 0.65, blue: 0.14)
    /// Wie in den Maskottchen-Bildern: helles Weiß-Cyan auf dem dunklen Bildschirm, ohne Leuchten.
    private static let eyeColor = Color(red: 0.86, green: 0.94, blue: 0.96)
    /// Etwas größer als die Grundmaße (62 × 52 pt Körper), damit er ca. 75 pt hoch ist.
    private static let scale: CGFloat = 1.15

    private var x: CGFloat { size.width * (0.1 + 0.8 * pose.x) }
    private var groundY: CGFloat { size.height - groundInset }

    /// Mitte des Körpers: über dem Boden, beim Springen höher, beim Atmen leicht wippend.
    private var centerY: CGFloat {
        let breathe = mood.isResting ? pose.breath * 3 : pose.breath * 1.5
        return groundY - 32 * Self.scale - pose.jump * 32 + breathe
    }

    var body: some View {
        ZStack {
            shadow
            if pose.hearts > 0 { hearts }
            if mood == .sleeping { snoring }
            mascot
                .scaleEffect(Self.scale)
                .scaleEffect(x: pose.facingRight ? 1 : -1, y: 1)
                .position(x: x, y: centerY)
        }
    }

    private var shadow: some View {
        let scale = 1 - pose.jump * 0.4
        return Ellipse()
            .fill(.black.opacity(0.12))
            .frame(width: 62 * scale, height: 7 * scale)
            .position(x: x, y: groundY)
    }

    private var hearts: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                let delay = index == 0 ? 0.0 : 0.2
                let progress = max(0, min(1, (pose.hearts - delay) / 0.8))
                if progress > 0, progress < 1 {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.85))
                        .scaleEffect(0.5 + progress * 0.5)
                        .opacity(1 - progress)
                        .offset(x: index == 0 ? -15 : 18, y: -50 - progress * 45)
                }
            }
        }
        .position(x: x, y: centerY)
    }

    private var snoring: some View {
        let phase = pose.breath
        return ZStack {
            Text(verbatim: "z")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .offset(x: 28 + phase * 10, y: -28 - phase * 22)
                .opacity(sin(phase * .pi))
            Text(verbatim: "Z")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .offset(x: 38 + phase * 6, y: -41 - phase * 20)
                .opacity(sin((phase + 0.3).truncatingRemainder(dividingBy: 1) * .pi))
        }
        .foregroundStyle(.white.opacity(0.6))
        .position(x: x, y: centerY)
        .accessibilityHidden(true)
    }

    /// Der Buddy selbst (Blick nach rechts), 62 × 52 pt plus Beine.
    private var mascot: some View {
        ZStack {
            HStack(spacing: 16) {
                leg(isLeft: true)
                leg(isLeft: false)
            }
            .offset(y: 28)

            // Ohr-Knopf hinten (links), ragt deutlich über den Körper hinaus.
            Capsule()
                .fill(Self.earColor)
                .frame(width: 7, height: 18)
                .offset(x: -33)

            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Self.bodyColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(.black.opacity(0.06), lineWidth: 1.5)
                }
                .frame(width: 62, height: 52)

            face
        }
    }

    /// Bildschirm mit Augen und Mund (oder digitaler Sonnenbrille), leicht nach vorn versetzt; Bäckchen beim
    /// Schlafen und Freuen.
    private var face: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Self.screenColor)
                .frame(width: 46, height: 32)
            if accessory == .sunglasses {
                sunglasses.offset(y: -3)
            } else {
                HStack(spacing: 12) {
                    eye
                    eye
                }
                .offset(y: -3)
            }
            mouth.offset(y: 7)
            if mood == .sleeping || mood == .happy {
                HStack(spacing: 28) {
                    Circle().fill(.red.opacity(0.35)).frame(width: 5, height: 5)
                    Circle().fill(.red.opacity(0.35)).frame(width: 5, height: 5)
                }
                .offset(y: 5)
            }
        }
        .offset(x: 3, y: 1)
    }

    /// Sonnenbrille als Anzeige auf dem Bildschirm (statt der Augen), in der Augenfarbe.
    private var sunglasses: some View {
        HStack(spacing: 2) {
            lens
            Capsule()
                .fill(Self.eyeColor)
                .frame(width: 4, height: 2)
                .offset(y: -2)
            lens
        }
    }

    private var lens: some View {
        UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 2)
            .fill(Self.eyeColor)
            .frame(width: 13, height: 9)
            .overlay {
                // Kleiner Glanzstreifen, damit es als Brille lesbar ist.
                Capsule()
                    .fill(Self.screenColor.opacity(0.7))
                    .frame(width: 2, height: 6)
                    .rotationEffect(.degrees(30))
                    .offset(x: -2, y: -0.5)
            }
    }

    /// Mund wie in den Bildern: Lächeln, beim Freuen offen, beim Schlafen ein kleiner Strich.
    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .sleeping:
            Capsule()
                .fill(Self.eyeColor)
                .frame(width: 5, height: 1.5)
        case .happy:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 9))
                path.closeSubpath()
            }
            .fill(Self.eyeColor)
            .frame(width: 10, height: 5)
        case .gloomy:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 3))
                path.addQuadCurve(to: CGPoint(x: 8, y: 3), control: CGPoint(x: 4, y: -1))
            }
            .stroke(Self.eyeColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 8, height: 3)
        case .alert, .relaxed:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 6))
            }
            .stroke(Self.eyeColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 10, height: 3)
        }
    }

    private func leg(isLeft: Bool) -> some View {
        let step = pose.isWalking ? sin(pose.stepPhase * 2 * .pi) : 0
        let lift = pose.isWalking && cos(pose.stepPhase * 2 * .pi) > 0 ? -2.0 : 0
        return Capsule()
            .fill(Self.screenColor)
            .frame(width: 8, height: 12)
            .rotationEffect(.degrees(isLeft ? step * 25 : -step * 25), anchor: .top)
            .offset(y: lift)
    }

    @ViewBuilder
    private var eye: some View {
        if mood == .gloomy {
            // „Kaputt“: X-Augen.
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 7, y: 7))
                path.move(to: CGPoint(x: 7, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 7))
            }
            .stroke(Self.eyeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 7, height: 7)
        } else if pose.isBlinking {
            Capsule()
                .fill(Self.eyeColor)
                .frame(width: 8, height: 1.5)
        } else {
            switch mood {
            case .alert:
                // Aufmerksam: runde, aufrechte Augen.
                Capsule()
                    .fill(Self.eyeColor)
                    .frame(width: 7, height: 9)
            case .relaxed, .happy:
                // Bogen-Augen ^^ (beim Freuen etwas größer).
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 5))
                    path.addLine(to: CGPoint(x: 4, y: 0))
                    path.addLine(to: CGPoint(x: 8, y: 5))
                }
                .stroke(Self.eyeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 8, height: 5)
                .scaleEffect(mood == .happy ? 1.15 : 1)
            case .sleeping, .gloomy:
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 1))
                    path.addQuadCurve(to: CGPoint(x: 7, y: 1), control: CGPoint(x: 3.5, y: 4.5))
                }
                .stroke(Self.eyeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 7, height: 4)
            }
        }
    }
}

// MARK: - Hintergrund

/// Minimaler Hintergrund je Szene, füllt die ganze Kachel. Im Dunkelmodus gedämpfte Varianten derselben Farben.
struct BuddyBackgroundView: View {
    let scene: BuddyScene
    /// 0 … 1 je Sekunde (fallender Regen).
    var rainPhase: Double = 0
    let size: CGSize

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if UIImage(named: scene.backgroundAsset) != nil {
            // Generiertes Bild; im Dunkelmodus abgedunkelt (die Nacht ist ohnehin dunkel).
            BuddySceneImage(name: scene.backgroundAsset, size: size)
                .overlay(.black.opacity(isDark && scene != .night ? 0.35 : 0))
                .overlay { if scene == .rain { rain } }
        } else {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
                groundColor.frame(height: 24)
                decoration
            }
            .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private var decoration: some View {
        switch scene {
        case .classroom: classroom
        case .outdoor: outdoor
        case .night: night
        case .beach: beach
        case .rain: rain
        }
    }

    // MARK: Szenen

    private var classroom: some View {
        ZStack {
            // Tafel
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.16, green: 0.31, blue: 0.24).opacity(isDark ? 0.45 : 0.18))
                .frame(width: 75, height: 44)
                .position(x: 65, y: 48)
            clock
                .position(x: size.width - 50, y: 38)
        }
    }

    /// Wanduhr: Zifferblatt und Zeiger in einem Stapel, einmal positioniert.
    private var clock: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(isDark ? 0.25 : 0.65))
            Circle()
                .stroke(.black.opacity(0.1), lineWidth: 1.5)
            Path { path in
                path.move(to: CGPoint(x: 11, y: 11))
                path.addLine(to: CGPoint(x: 11, y: 5))
                path.move(to: CGPoint(x: 11, y: 11))
                path.addLine(to: CGPoint(x: 15, y: 12))
            }
            .stroke(.black.opacity(isDark ? 0.5 : 0.25), lineWidth: 1.5)
        }
        .frame(width: 22, height: 22)
    }

    private var outdoor: some View {
        ZStack {
            Path { path in
                path.addEllipse(in: CGRect(x: 20, y: size.height - 42, width: 22, height: 22))
                path.addEllipse(in: CGRect(x: 32, y: size.height - 48, width: 28, height: 28))
                path.addEllipse(in: CGRect(x: 52, y: size.height - 38, width: 20, height: 20))
            }
            .fill(Color(red: 0.38, green: 0.69, blue: 0.48).opacity(isDark ? 0.45 : 0.25))
            sun(diameter: 24)
            Image(systemName: "music.note")
                .font(.system(size: 11))
                .foregroundStyle(.green.opacity(0.5))
                .position(x: size.width - 95, y: 44)
        }
    }

    private var night: some View {
        ZStack {
            ForEach(Self.stars.indices, id: \.self) { index in
                let star = Self.stars[index]
                Circle()
                    .fill(.white.opacity(star.opacity))
                    .frame(width: star.diameter, height: star.diameter)
                    .position(x: star.x < 0 ? size.width + star.x : star.x, y: star.y)
            }
            Image(systemName: "moon.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.98, green: 0.95, blue: 0.72))
                .shadow(color: .white.opacity(0.15), radius: 4)
                .position(x: size.width - 50, y: 34)
        }
    }

    private struct Star {
        /// Negative Werte zählen vom rechten Rand.
        let x: CGFloat
        let y: CGFloat
        let diameter: CGFloat
        let opacity: Double
    }

    private static let stars = [
        Star(x: 35, y: 28, diameter: 2, opacity: 0.4), Star(x: 110, y: 45, diameter: 3, opacity: 0.3),
        Star(x: -120, y: 24, diameter: 2, opacity: 0.5), Star(x: -30, y: 55, diameter: 2, opacity: 0.25),
        Star(x: 70, y: 18, diameter: 2, opacity: 0.35),
    ]

    private var beach: some View {
        let leaf = Color(red: 0.22, green: 0.58, blue: 0.40)
        return ZStack {
            sun(diameter: 28)
            Path { path in
                path.move(to: CGPoint(x: -5, y: size.height - 24))
                path.addQuadCurve(to: CGPoint(x: 15, y: 40), control: CGPoint(x: 2, y: 70))
                path.addQuadCurve(to: CGPoint(x: -5, y: size.height - 24), control: CGPoint(x: 20, y: size.height - 30))
            }
            .fill(leaf.opacity(isDark ? 0.35 : 0.15))
            Path { path in
                path.addEllipse(in: CGRect(x: 5, y: 33, width: 24, height: 10))
                path.addEllipse(in: CGRect(x: -12, y: 38, width: 22, height: 9))
                path.addEllipse(in: CGRect(x: 8, y: 44, width: 18, height: 8))
            }
            .fill(leaf.opacity(isDark ? 0.45 : 0.22))
        }
    }

    /// Regentropfen fallen schräg und kommen oben wieder herein.
    private var rain: some View {
        Path { path in
            let columns = Int(size.width / 28)
            for column in 0...max(columns, 1) {
                let x = CGFloat(column) * 28 + (column.isMultiple(of: 2) ? 0 : 14)
                for row in 0..<3 {
                    let offset = (Double(row) / 3 + rainPhase + Double(column % 3) * 0.17).truncatingRemainder(dividingBy: 1)
                    let y = CGFloat(offset) * (size.height - 30)
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - 4, y: y + 12))
                }
            }
        }
        .stroke(.white.opacity(isDark ? 0.18 : 0.35), lineWidth: 1.5)
    }

    private func sun(diameter: CGFloat) -> some View {
        Circle()
            .fill(Color(red: 0.98, green: 0.79, blue: 0.28).opacity(isDark ? 0.75 : 1))
            .frame(width: diameter, height: diameter)
            .position(x: size.width - 45, y: 34)
    }

    // MARK: Farben

    private var isDark: Bool { colorScheme == .dark }

    private var gradient: [Color] {
        switch scene {
        case .classroom: tone(light: [rgb(0.88, 0.93, 0.98), rgb(0.93, 0.96, 0.99)], dark: [rgb(0.14, 0.18, 0.25), rgb(0.17, 0.21, 0.28)])
        case .outdoor: tone(light: [rgb(0.88, 0.95, 0.90), rgb(0.94, 0.97, 0.95)], dark: [rgb(0.13, 0.21, 0.17), rgb(0.16, 0.24, 0.20)])
        case .night: [rgb(0.16, 0.17, 0.28), rgb(0.22, 0.25, 0.38)]
        case .beach: tone(light: [rgb(0.99, 0.93, 0.86), rgb(0.98, 0.96, 0.91)], dark: [rgb(0.25, 0.21, 0.16), rgb(0.28, 0.25, 0.20)])
        case .rain: tone(light: [rgb(0.65, 0.71, 0.77), rgb(0.75, 0.79, 0.83)], dark: [rgb(0.18, 0.21, 0.25), rgb(0.21, 0.24, 0.28)])
        }
    }

    private var groundColor: Color {
        switch scene {
        case .classroom: tone(light: rgb(0.82, 0.86, 0.93).opacity(0.65), dark: rgb(0.20, 0.24, 0.31))
        case .outdoor: tone(light: rgb(0.78, 0.89, 0.82), dark: rgb(0.19, 0.29, 0.23))
        case .night: rgb(0.11, 0.12, 0.20)
        case .beach: tone(light: rgb(0.95, 0.87, 0.75), dark: rgb(0.33, 0.28, 0.21))
        case .rain: tone(light: rgb(0.58, 0.64, 0.70), dark: rgb(0.15, 0.18, 0.21))
        }
    }

    private func tone<Value>(light: Value, dark: Value) -> Value {
        isDark ? dark : light
    }

    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red, green: green, blue: blue)
    }
}
