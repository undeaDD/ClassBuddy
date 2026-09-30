import SwiftUI

/// Kreis mit Kurzbezeichnung der Klasse (z. B. „7b“); ohne Kürzel ein leerer Kreis.
struct ClassBadge: View {
    let shortName: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Text(shortName)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .sensitive()
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(size * 0.12)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .circle)
    }
}

/// Oben links: „Klasse auswählen“-Button – runder Glas-Kreis mit dem Kürzel der Klasse.
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
            // Nur das Kürzel in einem Glas-Kreis in der Klassenfarbe (ohne Klasse: leeres Glas).
            Text(selectedClass?.buttonName ?? "")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(.white)
                .sensitive()
                .padding(4)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(selectedClass?.displayColor).interactive(), in: .circle)
        .accessibilityLabel(selectedClass.map { "\($0.title), Klasse wechseln" } ?? "Klasse auswählen")
        .popover(isPresented: isPickerPresented, arrowEdge: .top) {
            ClassPickerView()
                .softScrollEdges()
                .frame(minWidth: 340, idealWidth: 360, minHeight: 360, idealHeight: 440)
        }
    }
}
