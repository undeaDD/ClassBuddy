import SwiftUI

/// Kreis mit Kurzbezeichnung der Klasse (z. B. „7b“).
struct ClassBadge: View {
    let shortName: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Group {
            if shortName.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.42, weight: .semibold))
            } else {
                Text(shortName)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            }
        }
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
    /// Tab, in dessen Toolbar dieser Button sitzt. Jeder Tab hat einen eigenen
    /// Button – nur der im sichtbaren Tab darf das Popover zeigen.
    let tab: AppTab

    private var isPickerPresented: Binding<Bool> {
        Binding(
            get: { app.isClassPickerPresented && app.selectedTab == tab },
            set: { app.isClassPickerPresented = $0 }
        )
    }

    var body: some View {
        Button {
            app.isClassPickerPresented = true
        } label: {
            HStack(spacing: 10) {
                ClassBadge(
                    shortName: selectedClass?.shortName ?? "",
                    color: selectedClass?.color.color ?? .accentColor
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
            }
            .padding(.trailing, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(selectedClass.map { "\($0.title), Klasse wechseln" } ?? "Klasse auswählen")
        .popover(isPresented: isPickerPresented, arrowEdge: .top) {
            ClassPickerView()
                .frame(minWidth: 340, idealWidth: 360, minHeight: 360, idealHeight: 440)
        }
    }
}
