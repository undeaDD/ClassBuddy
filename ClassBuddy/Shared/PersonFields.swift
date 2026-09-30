import SwiftUI

/// Geschlecht mit Symbol (♀ ♂ ⚧) und „keine Angabe“.
/// iPad: Segmented Control; iPhone: Pop-up-Menü (vier Segmente passen nicht in die Breite).
struct GenderPicker: View {
    @Environment(\.device) private var device
    @Binding var selection: Gender?

    var body: some View {
        if device.isPhone {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var picker: some View {
        Picker("Geschlecht", selection: $selection) {
            ForEach(Gender.allCases) { option in
                Text("\(option.symbol) \(option.title)").tag(Optional(option))
            }
            Text("keine Angabe").tag(Gender?.none)
        }
    }
}

/// Optionaler Geburtstag ohne Schalter: Datum direkt wählbar.
/// Solange keins gesetzt ist, ist die Zeile abgeblendet; das x entfernt es wieder.
struct BirthdayField: View {
    @Binding var birthday: Date?
    /// Vorbelegung des Datumsfelds, solange kein Geburtstag gesetzt ist.
    var suggestedAge = 12

    private var suggestion: Date {
        Calendar.school.date(byAdding: .year, value: -suggestedAge, to: .now) ?? .now
    }

    var body: some View {
        HStack {
            DatePicker(
                "Geburtstag",
                selection: Binding(get: { birthday ?? suggestion }, set: { birthday = $0 }),
                in: ...Date.now,
                displayedComponents: .date
            )
            .opacity(birthday == nil ? 0.45 : 1)
            .sensitive()

            if birthday != nil {
                Button("Geburtstag entfernen", image: .xmark) { birthday = nil }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.borderless)
                    .padding(.leading, 6)
            }
        }
    }
}

extension View {
    /// Vollbild-Formulare: auf dem iPad mittig mit begrenzter Breite (eigener Hintergrund
    /// für die Ränder); auf dem iPhone unverändert mit dem Standard-Hintergrund des Formulars.
    func readableFormWidth() -> some View {
        modifier(ReadableFormWidth())
    }
}

private struct ReadableFormWidth: ViewModifier {
    @Environment(\.device) private var device

    func body(content: Content) -> some View {
        if device.isPad {
            content
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
        } else {
            content
        }
    }
}
