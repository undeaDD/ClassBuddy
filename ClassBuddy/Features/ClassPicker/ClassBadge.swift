import SwiftUI
import TipKit

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
    @Environment(\.appAccent) private var accent
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

    /// Wie die übrigen Toolbar-Knöpfe: ab iOS 26 die Glas-Knöpfe des Systems (44 pt), davor die Kapseln (36 pt).
    private static var size: CGFloat {
        if #available(iOS 26, *) { 44 } else { 36 }
    }

    var body: some View {
        Button {
            SetupTip(.createClass).invalidate(reason: .actionPerformed)
            app.isClassPickerPresented = true
        } label: {
            // Kürzel in einem Glas-Kreis in der Klassenfarbe; ohne Klasse ein Plus in der Akzentfarbe.
            Group {
                if let selectedClass {
                    Text(selectedClass.buttonName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .sensitive()
                } else {
                    Image(icon: .plus)
                        .iconSize(18)
                }
            }
            .foregroundStyle(.white)
            .padding(4)
            .frame(width: Self.size, height: Self.size)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        // Ohne Schatten: die Navigationsleiste schneidet ihn vor iOS 26 unten ab.
        .appGlassEffect(.regular.tint(selectedClass?.displayColor ?? accent).interactive(), in: .circle, fallbackShadow: false)
        .accessibilityLabel(selectedClass.map { loc("\($0.title), Klasse wechseln") } ?? "Klasse auswählen")
        .popover(isPresented: isPickerPresented, arrowEdge: .top) {
            ClassPickerView()
                .softScrollEdges()
                .frame(minWidth: 340, idealWidth: 360, minHeight: 360, idealHeight: 440)
        }
    }
}
