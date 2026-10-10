import SwiftUI

/// Einführung beim ersten Start: drei Seiten, wischen oder über den Button weiter. Solange weder Testphase
/// noch Vollversion gewählt ist, folgt die Kaufseite (zwei Karten statt Button); die Einführung lässt sich dann
/// nicht schließen und beginnt nach dem Wechsel in den Hintergrund wieder von vorn.
/// iPhone: Vollbild; iPad: Form-Sheet. Einmalig (`storageKey`); in den Einstellungen erneut aufrufbar.
///
/// `purchase`: nur die Kaufseite, ohne Zurück (nach Ablauf der Testphase; von der Testphasen-Kachel mit xmark).
///
/// Aufbau je Seite: Illustration mittig im oberen Bereich, Titel und Text unten linksbündig mit
/// fester Zeilenzahl – so steht der Button auf jeder Seite an derselben Stelle.
struct OnboardingView: View {
    static let storageKey = "onboarding.completed"

    enum Mode: Equatable {
        case intro
        case purchase(isClosable: Bool)
    }

    @Environment(\.device) private var device
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PurchaseStore.self) private var purchases
    var mode: Mode = .intro
    let onFinish: () -> Void

    @State private var page = 0

    private struct Page {
        let image: ImageResource
        let title: String
        let text: String
    }

    private let pages = [
        Page(
            image: .book,
            title: loc("Willkommen bei ClassBuddy"),
            text: loc("""
                Verwalten Sie Klassen mit Fächern und Farben, pflegen Sie Ihre Schülerliste \
                und behalten Sie Stundenplan und Termine im Blick.
                """)
        ),
        Page(
            image: .shield,
            title: loc("Sicher, offline, DSGVO-konform"),
            text: loc("""
                Kein Konto, keine Cloud: Alles bleibt offline auf diesem Gerät, biometrisch geschützt. \
                Per Excel-Export sichern Sie Ihre Daten und importieren sie jederzeit wieder.
                """)
        ),
        Page(
            image: .heart,
            title: loc("Helfen Sie mit, ClassBuddy besser zu machen"),
            text: loc("""
                Fehlt Ihnen etwas? Schreiben Sie mir über „Feedback senden“ in den Einstellungen. \
                Gefällt Ihnen die App, freue ich mich über eine Empfehlung oder einen Kaffee.
                """)
        ),
    ]

    /// Kaufseite anhängen: vor der Entscheidung, nach Ablauf und während der Testphase (von der Kachel).
    private var showsPurchasePage: Bool {
        if case .purchase = mode { return true }
        return purchases.status.requiresChoice || purchases.status == .loading
    }

    private var allPages: [Page] {
        switch mode {
        case .purchase: [purchasePage]
        case .intro: showsPurchasePage ? pages + [purchasePage] : pages
        }
    }

    private var purchasePage: Page {
        switch purchases.status {
        case .expired:
            Page(image: .hourglass, title: loc("Die Testphase ist vorbei"), text: loc("""
                Ihre Daten liegen weiterhin auf diesem Gerät. Mit der Vollversion geht es genau dort weiter, \
                einmalig und ohne Abo.
                """))
        case .trial(let days):
            Page(image: .hourglass, title: trialDaysText(days), text: loc("""
                Mit der Vollversion nutzen Sie ClassBuddy dauerhaft, einmalig und ohne Abo. \
                Ihre Daten bleiben, wie sie sind.
                """))
        default:
            Page(image: .hourglass, title: loc("ClassBuddy kennenlernen"), text: loc("""
                Testen Sie 30 Tage lang alle Funktionen kostenlos. Danach schalten Sie die Vollversion \
                einmalig frei, ohne Abo.
                """))
        }
    }

    private var isLastPage: Bool { page == allPages.count - 1 }
    private var isOnPurchasePage: Bool { showsPurchasePage && isLastPage }

    /// Feste Zeilenzahl, damit Titel/Text/Button auf allen Seiten gleich stehen.
    private static let titleLines = 2
    private static let textLines = 4

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    if mode == .purchase(isClosable: true) {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Schließen", icon: .xmark, action: onFinish)
                                .toolbarGroupBackground()
                        }
                    }
                }
        }
        .interactiveDismissDisabled(mode != .purchase(isClosable: true))
        // Ohne Entscheidung: beim nächsten Öffnen wieder von vorn.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, mode == .intro, purchases.status.requiresChoice { page = 0 }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                // Seite als Wert statt Index: Nach dem Kauf fällt die Kaufseite weg, ein veralteter Index stürzte ab.
                ForEach(Array(allPages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: allPages.count) { _, count in page = min(page, count - 1) }

            if isOnPurchasePage {
                PurchaseChoices(onDone: onFinish)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: 600)
            } else {
                buttonBar
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var buttonBar: some View {
        HStack {
            Button {
                if isLastPage {
                    onFinish()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(isLastPage ? "Los geht’s" : "Weiter")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            .appGlassButtonStyle(prominent: true)
            .controlSize(.large)

            Spacer()
            pageDots
        }
        .padding(.top, 24)
        .padding(.bottom, 24)
        .padding(.horizontal, 28)
        .frame(maxWidth: 600)
    }

    private func pageView(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Illustration mittig im oberen Bereich.
            Image(page.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: device.isPhone ? 240 : 300)
                .clipShape(.rect(cornerRadius: device.isPhone ? 44 : 56, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text(page.title)
                    .font(device.isPhone ? .title.bold() : .largeTitle.bold())
                    .lineLimit(Self.titleLines, reservesSpace: true)
                    .minimumScaleFactor(0.8)
                Text(page.text)
                    .font(device.isPhone ? .body : .title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(Self.textLines, reservesSpace: true)
                    .minimumScaleFactor(0.85)
            }
            .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 600)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(allPages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                    .frame(width: index == page ? 20 : 8, height: 8)
            }
        }
        .animation(.smooth, value: page)
        .accessibilityElement()
        .accessibilityLabel("Seite \(page + 1) von \(allPages.count)")
    }
}

#Preview {
    OnboardingView {}
        .environment(PurchaseStore())
}
