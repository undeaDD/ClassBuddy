import SwiftUI

/// Kreis mit Kurzbezeichnung der Klasse (z. B. „7b“).
struct ClassBadge: View {
    let shortName: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Text(shortName.isEmpty ? "?" : shortName)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(size * 0.12)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .circle)
    }
}

/// Oben links: „Klasse auswählen“-Button mit Kreis + Titel/Untertitel.
struct ClassPickerButton: View {
    @Environment(AppModel.self) private var app
    let selectedClass: SchoolClass?

    var body: some View {
        @Bindable var app = app
        Button {
            app.isClassPickerPresented = true
        } label: {
            HStack(spacing: 10) {
                ClassBadge(
                    shortName: selectedClass?.shortName ?? "",
                    color: selectedClass?.color.color ?? .gray
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text(selectedClass?.title ?? "Klasse auswählen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(selectedClass?.detailLine ?? "Keine Klasse aktiv")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.trailing, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(selectedClass.map { "\($0.title), Klasse wechseln" } ?? "Klasse auswählen")
        .popover(isPresented: $app.isClassPickerPresented, arrowEdge: .top) {
            ClassPickerView()
                .frame(minWidth: 340, idealWidth: 360, minHeight: 360, idealHeight: 440)
        }
    }
}
