import SwiftUI

/// Kurze Rückmeldungen („Export gespeichert“, „Import fehlgeschlagen“ …) als Toast oben im Fenster.
/// Über die Umgebung verfügbar: `@Environment(ToastCenter.self) private var toasts`.
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        enum Style {
            case success, error, info

            var icon: AppIcon {
                switch self {
                case .success: .toastSuccess
                case .error: .toastError
                case .info: .toastWarning
                }
            }

            var color: Color {
                switch self {
                case .success: .green
                case .error: .red
                // Fest gelb (Hinweis-Icon), unabhängig von der Akzentfarbe.
                case .info: .yellow
                }
            }
        }

        let id = UUID()
        let message: String
        let style: Style
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Toast.Style = .info) {
        let toast = Toast(message: message, style: style)
        switch style {
        case .success: Haptics.notify(.success)
        case .error: Haptics.notify(.error)
        case .info: Haptics.tap()
        }
        withAnimation(.bouncy(duration: 0.35)) { current = toast }
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(style == .error ? 4.5 : 3))
            guard !Task.isCancelled else { return }
            dismiss(toast.id)
        }
    }

    func success(_ message: String) { show(message, style: .success) }
    func error(_ message: String) { show(message, style: .error) }
    func info(_ message: String) { show(message, style: .info) }

    func dismiss(_ id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        withAnimation(.smooth(duration: 0.25)) { current = nil }
    }
}

/// Anzeige des aktuellen Toasts. Nur so groß wie der Toast selbst, blockiert also keine Eingaben
/// (in `RootView` per `.overlay(alignment: .top)` eingebunden).
struct ToastOverlay: View {
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        ZStack {
            if let toast = toasts.current {
                HStack(spacing: 10) {
                    Image(icon: toast.style.icon)
                        .iconSize(22)
                        .foregroundStyle(toast.style.color)
                    Text(toast.message)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .onTapGesture { toasts.dismiss(toast.id) }
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .frame(maxWidth: 640)
        .padding(.top, 12)
        .padding(.horizontal, 24)
    }
}
