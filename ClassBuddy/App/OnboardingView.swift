import SwiftUI

/// Einführung beim ersten Start: drei Seiten, wischen oder über den Button weiter; xmark schließt.
/// iPhone: Vollbild; iPad: Form-Sheet. Einmalig (`storageKey`); in den App-Einstellungen erneut aufrufbar.
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
            image: .appIconPreview,
            title: "Willkommen bei ClassBuddy",
            text: "Klassen, Schüler, Stundenplan und Termine an einem Ort – gemacht für den Schulalltag."
        ),
        Page(
            image: .fingerprintLockCircle,
            title: "Deine Daten bleiben bei dir",
            text: "Kein Konto, keine Cloud: Alles wird nur auf diesem Gerät gespeichert und mit Face ID geschützt. "
                + "Das Auge oben rechts blendet Namen und Notizen aus, wenn jemand mitschaut."
        ),
        Page(
            image: .community,
            title: "Los geht’s",
            text: "Lege oben links deine erste Klasse an und trage in den Schuleinstellungen deinen Stundenplan ein."
        ),
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Schließen", image: .xmark, action: onFinish)
                    }
                }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index], isAppIcon: index == 0)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if isLastPage {
                    onFinish()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(isLastPage ? "Los geht’s" : "Weiter")
                    .font(.headline)
                    .frame(maxWidth: 420)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background {
            Rectangle()
                .fill(Color.accentColor.opacity(0.08).gradient)
                .ignoresSafeArea()
        }
        .background(Color(.systemBackground))
    }

    private func pageView(_ page: Page, isAppIcon: Bool) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Group {
                if isAppIcon {
                    // App-Icon in Originalfarben.
                    Image(page.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                } else {
                    Image(page.image)
                        .iconSize(device.isPhone ? 96 : 120)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(device.isPhone ? .title.bold() : .largeTitle.bold())
                Text(page.text)
                    .font(device.isPhone ? .body : .title3)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 520)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    OnboardingView {}
}
