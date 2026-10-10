import SwiftUI

/// Unterer Bereich der Kaufseite (letzte Seite der Einführung): oben die Testphase, darunter die Vollversion,
/// darunter „Käufe wiederherstellen“. Hervorgehoben ist immer genau eine Karte: vor der Testphase „Testen“,
/// sonst „Kaufen“. `onDone` nach erfolgreichem Start der Testphase bzw. Kauf.
struct PurchaseChoices: View {
    @Environment(PurchaseStore.self) private var purchases
    let onDone: () -> Void

    @State private var runningAction: Action?
    @State private var message: String?

    private enum Action {
        case trial, buy, restore
    }

    private var status: PurchaseStatus { purchases.status }

    var body: some View {
        VStack(spacing: 12) {
            trialCard
            buyCard
            Button("Käufe wiederherstellen") { run(.restore) }
                .font(.footnote.weight(.semibold))
                .disabled(purchases.isWorking || status == .loading)
                .padding(.top, 4)
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: message)
    }

    @ViewBuilder
    private var trialCard: some View {
        switch status {
        case .trial(let days):
            PurchaseCard(title: loc("Testphase läuft"), subtitle: trialDaysText(days), systemImage: "hourglass", style: .inactive)
        case .expired:
            PurchaseCard(
                title: loc("Testphase abgelaufen"), subtitle: loc("Die 30 Tage sind vorbei"),
                systemImage: "hourglass.bottomhalf.filled", style: .inactive
            )
        default:
            PurchaseCard(
                title: loc("30 Tage kostenlos testen"),
                subtitle: loc("Alle Funktionen, endet automatisch"),
                systemImage: "hourglass",
                style: .prominent,
                isLoading: runningAction == .trial || status == .loading,
                isDisabled: purchases.isWorking || status == .loading
            ) { run(.trial) }
        }
    }

    private var buyCard: some View {
        let price = purchases.fullVersion?.displayPrice
        return PurchaseCard(
            title: loc("Vollversion kaufen"),
            subtitle: price.map { loc("Einmalig \($0), kein Abo") } ?? loc("Einmalig, kein Abo"),
            systemImage: "checkmark.seal",
            style: status == .notStarted || status == .loading ? .secondary : .prominent,
            isLoading: runningAction == .buy,
            isDisabled: purchases.isWorking || status == .loading
        ) { run(.buy) }
    }

    private func run(_ action: Action) {
        runningAction = action
        message = nil
        Task {
            defer { runningAction = nil }
            switch action {
            case .trial: handle(await purchases.startTrial())
            case .buy: handle(await purchases.buyFullVersion())
            case .restore:
                guard await purchases.restore() else {
                    message = Self.unreachable
                    return
                }
                if purchases.status.requiresChoice {
                    message = loc("Für diesen Apple Account wurden keine Käufe gefunden.")
                } else {
                    onDone()
                }
            }
        }
    }

    private func handle(_ outcome: PurchaseStore.Outcome) {
        switch outcome {
        case .success: onDone()
        case .cancelled: break
        case .pending: message = loc("Der Kauf wartet noch auf eine Freigabe.")
        case .failed: message = Self.unreachable
        }
    }

    private static var unreachable: String {
        loc("Der App Store ist gerade nicht erreichbar. Bitte versuchen Sie es später noch einmal.")
    }
}

/// „Noch 23 Tage“ bzw. „Noch 1 Tag“.
func trialDaysText(_ days: Int) -> String {
    days == 1 ? loc("Noch 1 Tag") : loc("Noch \(days) Tage")
}

/// Große, ganz antippbare Karte der Kaufseite.
struct PurchaseCard: View {
    enum Style {
        /// Gefüllt in der Akzentfarbe.
        case prominent
        /// Hell mit Rahmen und Titel in der Akzentfarbe: klar als Option erkennbar, nicht versteckt.
        case secondary
        /// Nur Information (Testphase läuft oder ist abgelaufen).
        case inactive
    }

    let title: String
    let subtitle: String
    /// Vorläufig SF Symbols statt eigener Icons.
    let systemImage: String
    let style: Style
    var isLoading = false
    var isDisabled = false
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(titleStyle)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(titleStyle)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(subtitleStyle)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                        .tint(style == .prominent ? .white : nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(background, in: cardShape)
            .overlay {
                if style == .secondary {
                    cardShape.strokeBorder(.tint, lineWidth: 1.5)
                }
            }
            .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .disabled(style == .inactive || isDisabled)
        .opacity(isDisabled && !isLoading && style != .inactive ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    private var titleStyle: AnyShapeStyle {
        switch style {
        case .prominent: AnyShapeStyle(.white)
        case .secondary: AnyShapeStyle(.tint)
        case .inactive: AnyShapeStyle(.secondary)
        }
    }

    private var subtitleStyle: AnyShapeStyle {
        style == .prominent ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary)
    }

    private var background: AnyShapeStyle {
        switch style {
        case .prominent: AnyShapeStyle(.tint)
        case .secondary, .inactive: AnyShapeStyle(Color(.secondarySystemGroupedBackground))
        }
    }
}

/// Feste erste Kachel der Übersicht während der Testphase: verbleibende Tage, in der Akzentfarbe
/// hervorgehoben; Antippen öffnet die Kaufseite.
struct TrialDashboardCard: View {
    let daysLeft: Int
    let action: () -> Void

    var body: some View {
        Button(action: Haptics.tapping(action)) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Testphase", systemImage: "hourglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trialDaysText(daysLeft))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Vollversion freischalten")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: cardHeight, alignment: .topLeading)
            .background(.tint, in: cardShape)
            .contentShape(.hoverEffect, cardShape)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }
}
