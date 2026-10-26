import SwiftUI

/// Eingabefelder zu einer Person, für die Tab-Reihenfolge (`tabOrder`).
enum PersonField: Hashable {
    case firstName, lastName, phone, email, otherContact, notes
}

/// Vor- und Nachname, je mit Namens-Icon vorne.
struct NameFields: View {
    @Binding var firstName: String
    @Binding var lastName: String
    /// Fokus des Formulars; `order` ist dessen Tab-Reihenfolge.
    var focus: FocusState<PersonField?>.Binding
    var order: [PersonField]

    var body: some View {
        Label {
            TextField("Vorname", text: $firstName)
                .textContentType(.givenName)
                .tabOrder(.firstName, in: order, focus: focus)
                .sensitive()
        } icon: {
            Image(icon: .label)
        }
        Label {
            TextField("Nachname", text: $lastName)
                .textContentType(.familyName)
                .tabOrder(.lastName, in: order, focus: focus)
                .sensitive()
        } icon: {
            Image(icon: .label)
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
        Label("Geschlecht", icon: .genderUnknown)
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
                Label("Geburtstag", icon: .birthday)
            }
            .opacity(birthday == nil ? 0.45 : 1)
            .sensitive()

            if birthday != nil {
                Button("Geburtstag entfernen", icon: .xmark) { birthday = nil }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .buttonStyle(.borderless)
                    .padding(.leading, 6)
            }
        }
    }
}

extension View {
    /// Tab bzw. Umschalt-Tab (externe Tastatur) springt in `order` zum nächsten bzw. vorigen Eingabefeld (am Ende
    /// wieder zum ersten). Sonst folgt Tab der Systemreihenfolge, die auch Fotowahl, Picker und Datumsfelder anspringt,
    /// und mehrzeilige Felder fügen ein Tabulatorzeichen ein.
    func tabOrder<Field: Hashable>(_ field: Field, in order: [Field], focus: FocusState<Field?>.Binding) -> some View {
        focused(focus, equals: field)
            .onKeyPress(.tab, phases: [.down, .repeat]) { press in
                guard let index = order.firstIndex(of: field) else { return .ignored }
                let step = press.modifiers.contains(.shift) ? order.count - 1 : 1
                focus.wrappedValue = order[(index + step) % order.count]
                return .handled
            }
    }

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
