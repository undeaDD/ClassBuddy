import SwiftUI

/// Schnellaktionen für den Apple Pencil (Pro).
///
/// - **Squeeze** (Pencil Pro): öffnet ein radiales Schnellmenü genau dort,
///   wo der Stift gerade schwebt (Hover), sonst in der Bildschirmmitte.
/// - **Doppeltippen** (Pencil 2 / Pro): Privatsphäre-Modus umschalten.
///
/// Beide Gesten respektieren die in den Systemeinstellungen gewählte Pencil-Aktion
/// („Ignorieren“ = keine Aktion).
struct QuickAction: Identifiable {
    let id: String
    let title: String
    let symbol: AppSymbol
    var tint: Color = .accentColor
    let perform: () -> Void
}

extension View {
    func pencilQuickActions() -> some View {
        modifier(PencilQuickActionsModifier())
    }
}

private struct PencilQuickActionsModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(\.preferredPencilSqueezeAction) private var squeezeAction
    @Environment(\.preferredPencilDoubleTapAction) private var doubleTapAction

    @State private var menuLocation: CGPoint?

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .onPencilSqueeze { phase in
                    guard squeezeAction != .ignore, case .ended(let value) = phase else { return }
                    let location = value.hoverPose?.location
                        ?? CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    withAnimation(.bouncy(duration: 0.3)) {
                        menuLocation = menuLocation == nil ? location : nil
                    }
                }
                .onPencilDoubleTap { _ in
                    guard doubleTapAction != .ignore else { return }
                    Task { await security.togglePrivacyMode() }
                }
                .overlay {
                    if let menuLocation {
                        RadialQuickMenu(
                            center: clamped(menuLocation, in: proxy.size),
                            actions: actions,
                            dismiss: dismissMenu
                        )
                        .transition(.opacity)
                    }
                }
        }
    }

    private var actions: [QuickAction] {
        [
            QuickAction(id: "dashboard", title: "Übersicht", symbol: AppTab.dashboard.symbol) { app.open(.dashboard) },
            QuickAction(id: "students", title: "Schüler", symbol: AppTab.students.symbol) { app.open(.students) },
            QuickAction(id: "calendar", title: "Kalender", symbol: AppTab.calendar.symbol) { app.open(.calendar) },
            QuickAction(id: "class", title: "Klasse", symbol: .system("arrow.left.arrow.right")) {
                app.isClassPickerPresented = true
            },
            QuickAction(
                id: "privacy",
                title: security.isPrivacyModeOn ? "Anzeigen" : "Verbergen",
                symbol: .system(security.isPrivacyModeOn ? "eye" : "eye.slash"),
                tint: .orange
            ) {
                Task { await security.togglePrivacyMode() }
            },
        ]
    }

    private func dismissMenu() {
        withAnimation(.snappy(duration: 0.2)) { menuLocation = nil }
    }

    /// Menü vollständig im sichtbaren Bereich halten.
    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let margin = RadialQuickMenu.radius + 44
        return CGPoint(
            x: min(max(point.x, margin), max(size.width - margin, margin)),
            y: min(max(point.y, margin), max(size.height - margin, margin))
        )
    }
}

/// Kreisförmig um den Stift angeordnete Aktionen.
struct RadialQuickMenu: View {
    static let radius: CGFloat = 92

    let center: CGPoint
    let actions: [QuickAction]
    let dismiss: () -> Void

    @State private var isExpanded = false

    var body: some View {
        ZStack {
            // Tippen außerhalb schließt das Menü.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            GlassEffectContainer(spacing: 20) {
                ZStack {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Schnellmenü schließen")

                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        actionButton(action)
                            .offset(offset(for: index))
                    }
                }
            }
            .position(center)
        }
        .onAppear {
            withAnimation(.bouncy(duration: 0.35, extraBounce: 0.1)) { isExpanded = true }
        }
    }

    private func actionButton(_ action: QuickAction) -> some View {
        Button {
            action.perform()
            dismiss()
        } label: {
            VStack(spacing: 2) {
                action.symbol.image
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                Text(action.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(action.tint)
            .frame(width: 68, height: 68)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .hoverEffect(.lift)
    }

    private func offset(for index: Int) -> CGSize {
        guard isExpanded else { return .zero }
        let angle = (Double(index) / Double(actions.count)) * 2 * .pi - .pi / 2
        return CGSize(width: cos(angle) * Self.radius, height: sin(angle) * Self.radius)
    }
}
