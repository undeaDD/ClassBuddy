import SwiftUI

/// Einführung beim ersten Start: drei Seiten, wischen oder über den Button weiter; xmark schließt.
/// iPhone: Vollbild; iPad: Form-Sheet. Einmalig (`storageKey`); in den App-Einstellungen erneut aufrufbar.
///
/// Aufbau je Seite: Illustration mittig im oberen Bereich, Titel und Text unten linksbündig mit
/// fester Zeilenzahl – so steht der Button auf jeder Seite an derselben Stelle.
struct OnboardingView: View {
    static let storageKey = "onboarding.completed"

    @Environment(\.device) private var device
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
                Kein Konto, keine Cloud: Alles bleibt offline auf diesem Gerät, geschützt mit Face ID. \
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

    private var isLastPage: Bool { page == pages.count - 1 }

    /// Feste Zeilenzahl, damit Titel/Text/Button auf allen Seiten gleich stehen.
    private static let titleLines = 2
    private static let textLines = 4

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Schließen", icon: .xmark, action: onFinish)
                    }
                }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

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
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Spacer()
                pageDots
            }
            .padding(.top, 24)
            .padding(.bottom, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(.tint.opacity(0.08))
                .ignoresSafeArea()
        }
        .background(Color(.systemBackground))
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
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                    .frame(width: index == page ? 20 : 8, height: 8)
            }
        }
        .animation(.smooth, value: page)
        .accessibilityElement()
        .accessibilityLabel("Seite \(page + 1) von \(pages.count)")
    }
}

#Preview {
    OnboardingView {}
}
