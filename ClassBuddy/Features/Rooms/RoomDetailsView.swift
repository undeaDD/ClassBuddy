import SwiftUI

/// Stammdaten eines Raums im Editor; übernommen erst beim Speichern des Raums.
struct RoomDetails: Equatable {
    var name = ""
    var subtitle = ""
    var category: RoomCategory = .classroom
    var assignments: [String] = []
    var equipment: [String] = []

    init(room: Room?) {
        guard let room else { return }
        name = room.name
        subtitle = room.subtitle
        category = room.category
        assignments = room.assignments
        equipment = room.equipment
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    func apply(to room: Room) {
        room.name = trimmedName
        room.subtitle = subtitle.trimmingCharacters(in: .whitespaces)
        room.category = category
        room.assignments = assignments
        room.equipment = equipment
    }
}

/// Formular „Details“: Name, Untertitel, Kategorie, Fächer und Ausstattung.
struct RoomDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SchoolSettings.self) private var settings
    @Binding var details: RoomDetails

    var body: some View {
        NavigationStack {
            Form {
                Section("Raum") {
                    Label {
                        TextField("Name (z. B. R 204)", text: $details.name)
                            .sensitive()
                    } icon: {
                        Image(icon: .label)
                    }
                    Label {
                        TextField("Untertitel (z. B. Physikraum, 2. OG)", text: $details.subtitle)
                            .sensitive()
                    } icon: {
                        Image(icon: .label)
                    }
                    Picker(selection: $details.category) {
                        ForEach(RoomCategory.allCases) { category in
                            Text(category.displayTitle).tag(category)
                        }
                    } label: {
                        Label("Kategorie", symbol: AppTab.rooms.symbol)
                    }
                }

                Section {
                    ForEach(details.assignments, id: \.self) { subject in
                        Text(SchoolClass.displayName(ofSubject: subject))
                            .sensitive()
                    }
                    .onDelete { details.assignments.remove(atOffsets: $0) }
                    NavigationLink {
                        SubjectPickerView(subjects: $details.assignments, preferred: settings.values.teacher.subjects)
                    } label: {
                        Label("Fach hinzufügen", icon: .graduationCap)
                    }
                } header: {
                    Text("Fächer")
                } footer: {
                    Text(details.assignments.isEmpty
                        ? loc("Ohne Auswahl können hier alle Fächer unterrichtet werden.")
                        : loc("Zum Entfernen nach links wischen."))
                }

                Section("Ausstattung") {
                    ForEach(details.equipment, id: \.self) { item in
                        Text(Room.displayName(ofEquipment: item))
                    }
                    .onDelete { details.equipment.remove(atOffsets: $0) }
                    NavigationLink {
                        MultiSelectPickerView(
                            title: loc("Ausstattung"),
                            selection: $details.equipment,
                            suggestions: Room.suggestedEquipment,
                            displayName: Room.displayName(ofEquipment:),
                            customPlaceholder: loc("Eigene Ausstattung")
                        )
                    } label: {
                        Label("Ausstattung hinzufügen", icon: .box)
                    }
                }
            }
            .readableFormWidth()
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: loc("Fertig")) { dismiss() }
                }
            }
        }
    }
}

/// Mehrfachauswahl aus Vorschlägen plus eigene Einträge (Reihenfolge = Reihenfolge des Antippens).
struct MultiSelectPickerView: View {
    let title: String
    @Binding var selection: [String]
    let suggestions: [String]
    let displayName: (String) -> String
    let customPlaceholder: String

    @State private var customItem = ""

    var body: some View {
        List {
            Section {
                ForEach(suggestions, id: \.self, content: row)
            }
            Section("Eigene Einträge") {
                ForEach(selection.filter { !suggestions.contains($0) }, id: \.self, content: row)
                HStack {
                    TextField(customPlaceholder, text: $customItem)
                        .onSubmit(addCustomItem)
                    Button("Hinzufügen", icon: .check, action: addCustomItem)
                        .labelStyle(.iconOnly)
                        .disabled(customItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addCustomItem() {
        let item = customItem.trimmingCharacters(in: .whitespaces)
        guard !item.isEmpty else { return }
        if !selection.contains(item) { selection.append(item) }
        customItem = ""
    }

    private func row(_ item: String) -> some View {
        let isSelected = selection.contains(item)
        return Button {
            if isSelected {
                selection.removeAll { $0 == item }
            } else {
                selection.append(item)
            }
        } label: {
            HStack {
                Text(displayName(item))
                    .foregroundStyle(Color.primary)
                Spacer()
                if isSelected {
                    Image(icon: .check)
                        .iconSize(20)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
