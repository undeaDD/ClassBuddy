import SwiftUI

/// Schuleinstellungen → Leistungsarten und Bereiche: Bereiche umbenennen (Vorgabe je Bundesland),
/// Leistungsarten umbenennen, einem Bereich zuordnen, ausblenden, hinzufügen und löschen.
struct AssessmentTypesView: View {
    @Environment(SchoolSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                ForEach(AssessmentArea.allCases) { area in
                    TextField(
                        area.defaultName(federalState: settings.values.federalState),
                        text: Binding(
                            get: { settings.values.areaNames[area.rawValue] ?? "" },
                            set: { settings.values.areaNames[area.rawValue] = $0.isEmpty ? nil : $0 }
                        )
                    )
                }
            } header: {
                Text("Bereiche")
            } footer: {
                Text("Leer lassen für die Vorgabe des Bundeslands.")
            }

            Section {
                ForEach($settings.values.assessmentTypes) { $type in
                    HStack(spacing: 12) {
                        TextField("Name", text: $type.name)
                            .foregroundStyle(type.isHidden ? .secondary : .primary)
                        Picker("Bereich", selection: $type.area) {
                            ForEach(AssessmentArea.allCases) { Text(settings.values.areaName($0)).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .swipeActions(edge: .leading) {
                        Button(type.isHidden ? "Einblenden" : "Ausblenden", icon: type.isHidden ? .eye : .eyeClosed) {
                            type.isHidden.toggle()
                        }
                    }
                }
                .onDelete { settings.values.assessmentTypes.remove(atOffsets: $0) }
                .onMove { settings.values.assessmentTypes.move(fromOffsets: $0, toOffset: $1) }

                Button("Leistungsart hinzufügen", icon: .plus) {
                    settings.values.assessmentTypes.append(AssessmentType(name: loc("Neue Leistungsart"), area: .other))
                }
            } header: {
                Text("Leistungsarten")
            } footer: {
                Text("Nach rechts wischen zum Aus- bzw. Einblenden, nach links zum Löschen. Bestehende Leistungen behalten ihre Art.")
            }

            Section {
                Button("Vorgaben wiederherstellen", icon: .undo) {
                    settings.values.assessmentTypes = AssessmentType.defaults
                }
            }
        }
        .navigationTitle("Leistungsarten")
        .toolbar { EditButton() }
    }
}
