import SwiftUI

/// Geschlecht als Segmented Control mit Symbol (♀ ♂ ⚧) und „keine Angabe“.
struct GenderPicker: View {
    @Binding var selection: Gender?

    var body: some View {
        Picker("Geschlecht", selection: $selection) {
            ForEach(Gender.allCases) { option in
                Text("\(option.symbol) \(option.title)").tag(Optional(option))
            }
            Text("keine Angabe").tag(Gender?.none)
        }
        .pickerStyle(.segmented)
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
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
            }
        }
    }
}
