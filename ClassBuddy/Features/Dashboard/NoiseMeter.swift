import AVFoundation
import SwiftUI

/// Lautstärke-Ampel für die Klasse: Antippen startet bzw. stoppt die Messung.
/// Es wird nichts aufgenommen oder gespeichert – nur der Pegel jedes Puffers im Speicher berechnet.
struct NoiseMeterCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var meter = NoiseMeter()

    var body: some View {
        Button(action: Haptics.tapping(toggle)) {
            VStack(alignment: .leading, spacing: 12) {
                let card = DashboardBuiltInCard.noiseMeter
                CardHeader(title: card.title, symbol: card.symbol, showsChevron: false)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text(valueText)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(meter.state == .running ? meter.stage.color : .primary)
                        .contentTransition(.numericText())
                        .leadingAligned()
                    if meter.state == .running {
                        NoiseLevelBar(level: meter.level)
                    }
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .leadingAligned()
                }
            }
            .cardStyle()
            // Ampelfarbe als leichte Tönung über der Kachel.
            .overlay {
                if meter.state == .running {
                    cardShape
                        .fill(meter.stage.color.opacity(0.12))
                        .allowsHitTesting(false)
                        .animation(.smooth, value: meter.stage)
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        // Nicht im Hintergrund oder ohne sichtbare Kachel weiter messen.
        .onDisappear { meter.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { meter.stop() }
        }
    }

    private var valueText: String {
        switch meter.state {
        case .running: loc("\(Int(meter.level.rounded())) dB")
        case .starting: "…"
        case .off, .denied, .failed: loc("Aus")
        }
    }

    private var detailText: String {
        switch meter.state {
        case .running: meter.stage.title
        case .starting: loc("Mikrofon wird gestartet")
        case .off: loc("Antippen zum Messen")
        case .denied: loc("Mikrofon in den iOS-Einstellungen erlauben")
        case .failed: loc("Mikrofon nicht verfügbar")
        }
    }

    private func toggle() {
        if meter.state == .running || meter.state == .starting {
            meter.stop()
        } else {
            Task { await meter.start() }
        }
    }
}

/// Pegel als Balken über die drei Farbbereiche.
private struct NoiseLevelBar: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            let range = NoiseLevel.displayRange
            let fraction = (min(max(level, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(NoiseLevel.Stage.allCases, id: \.self) { stage in
                        Capsule()
                            .fill(stage.color.opacity(0.25))
                            .frame(width: proxy.size.width * stage.share(of: range))
                    }
                }
                Capsule()
                    .fill(NoiseLevel.stage(for: level).color)
                    .frame(width: max(proxy.size.width * fraction, 6))
                    .animation(.smooth(duration: 0.2), value: fraction)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: Messung

/// Pegelberechnung und Bereiche (rein, testbar).
/// Ohne Kalibrierung: dB ≈ dBFS + `calibrationOffset`; für eine Ampel reicht die grobe Schätzung.
nonisolated enum NoiseLevel {
    /// Typischer Abstand zwischen Mikrofon-Vollaussteuerung (dBFS) und Schalldruckpegel bei iPhone/iPad.
    static let calibrationOffset = 100.0
    /// Angezeigter Bereich des Balkens.
    static let displayRange = 30.0...90.0

    /// Grün bis 60 dB (Stillarbeit, normales Sprechen), Gelb bis 70 dB (Gruppenarbeit), darüber Rot.
    enum Stage: CaseIterable {
        case calm, lively, loud

        static let livelyFrom = 60.0
        static let loudFrom = 70.0

        var color: Color {
            switch self {
            case .calm: .green
            case .lively: .yellow
            case .loud: .red
            }
        }

        var title: String {
            switch self {
            case .calm: loc("Angenehm ruhig")
            case .lively: loc("Lebhaft")
            case .loud: loc("Zu laut")
            }
        }

        /// Anteil des Bereichs am Balken.
        func share(of range: ClosedRange<Double>) -> Double {
            let width = range.upperBound - range.lowerBound
            return switch self {
            case .calm: (Self.livelyFrom - range.lowerBound) / width
            case .lively: (Self.loudFrom - Self.livelyFrom) / width
            case .loud: (range.upperBound - Self.loudFrom) / width
            }
        }
    }

    static func stage(for decibels: Double) -> Stage {
        decibels >= Stage.loudFrom ? .loud : decibels >= Stage.livelyFrom ? .lively : .calm
    }

    /// Effektivwert der Samples.
    static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// Geschätzter Schalldruckpegel in dB (0…120).
    static func decibels(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        return min(max(20 * log10(Double(rms)) + calibrationOffset, 0), 120)
    }

    /// Glättung: steigt schnell, fällt langsam (ruhige Anzeige, Spitzen bleiben sichtbar).
    static func smoothed(previous: Double, new: Double) -> Double {
        let factor = new > previous ? 0.5 : 0.1
        return previous + (new - previous) * factor
    }
}

/// Mikrofon-Pegel live über `AVAudioEngine`; keine Aufnahme, keine Dateien.
@Observable
final class NoiseMeter {
    enum State {
        case off, starting, running, denied, failed
    }

    private(set) var state: State = .off
    private(set) var level: Double = 0
    var stage: NoiseLevel.Stage { NoiseLevel.stage(for: level) }

    private let engine = AVAudioEngine()

    func start() async {
        guard state != .running else { return }
        state = .starting
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied
            return
        }
        guard state == .starting else { return } // inzwischen wieder ausgeschaltet
        do {
            let session = AVAudioSession.sharedInstance()
            // Messmodus ohne automatische Pegelanpassung; andere Töne (Timer) laufen weiter.
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0), block: Self.tap { [weak self] decibels in
                Task { @MainActor in self?.receive(decibels) }
            })
            try engine.start()
            level = 0
            state = .running
        } catch {
            stop()
            state = .failed
        }
    }

    func stop() {
        guard state != .off else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .off
        level = 0
    }

    private func receive(_ decibels: Double) {
        guard state == .running else { return }
        level = level == 0 ? decibels : NoiseLevel.smoothed(previous: level, new: decibels)
    }

    /// Läuft auf dem Audio-Thread → nicht an den MainActor gebunden.
    private nonisolated static func tap(_ handler: @escaping @Sendable (Double) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            handler(NoiseLevel.decibels(rms: NoiseLevel.rms(samples)))
        }
    }
}
