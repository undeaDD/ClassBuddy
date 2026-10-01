import SwiftUI

/// Vor- und Nachname, je mit Namens-Icon vorne.
struct NameFields: View {
    @Binding var firstName: String
    @Binding var lastName: String

    var body: some View {
        Label {
            TextField("Vorname", text: $firstName)
                .textContentType(.givenName)
                .sensitive()
        } icon: {
            Image(.label)
        }
        Label {
            TextField("Nachname", text: $lastName)
                .textContentType(.familyName)
                .sensitive()
        } icon: {
            Image(.label)
        }
    }
}

/// Geschlecht mit Symbol (♀ ♂ ⚧) und „keine Angabe“.
/// iPad: Segmented Control neben der Beschriftung; iPhone: Pop-up-Menü (vier Segmente passen nicht in die Breite).
struct GenderPicker: View {
    @Environment(\.device) private var device
    @Binding var selection: Gender?

    var body: some View {
        if device.isPhone {
            picker.pickerStyle(.menu)
        } else {
            LabeledContent {
                picker.pickerStyle(.segmented).fixedSize()
            } label: {
                label
            }
        }
    }

    private var label: some View {
        Label("Geschlecht", image: .genderUnknown)
    }

    private var picker: some View {
        Picker(selection: $selection) {
            ForEach(Gender.allCases) { option in
                Text(verbatim: "\(option.symbol) \(option.displayTitle)").tag(Optional(option))
            }
            Text("Keine Angabe").tag(Gender?.none)
        } label: {
            label
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
                selection: Binding(get: { birthday ?? suggestion }, set: { birthday = $0 }),
                in: ...Date.now,
                displayedComponents: .date
            ) {
                Label("Geburtstag", image: .birthday)
            }
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
