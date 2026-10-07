import SwiftData
import SwiftUI

enum AssessmentEditorRoute: Identifiable {
    /// Neue Leistung; `subject` ist die Vorauswahl.
    case new(SchoolClass, subject: String?)
    case edit(Assessment)

    var id: String {
        switch self {
        case .new(let schoolClass, _): "new-\(schoolClass.id)"
        case .edit(let assessment): assessment.id.uuidString
        }
    }
}

/// Leistung anlegen oder bearbeiten: Titel, Art (bestimmt den Bereich), Fach, Datum, optional Rohpunkte.
struct AssessmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SchoolSettings.self) private var schoolSettings
    let route: AssessmentEditorRoute

    @State private var title = ""
    @State private var typeID: UUID?
    @State private var area: AssessmentArea = .other
    @State private var subject = ""
    @State private var date = Date.now
    @State private var usesPoints = false
    @State private var maxPointsText = ""

    private var schoolClass: SchoolClass? {
        switch route {
        case .new(let schoolClass, _): schoolClass
        case .edit(let assessment): assessment.schoolClass
        }
    }

    private var isNew: Bool {
        if case .new = route { return true }
        return false
    }

    private var hasWrittenWork: Bool {
        schoolClass?.recordSettings(for: subject, schoolType: schoolSettings.values.schoolType).hasWrittenWork ?? true
    }

    private var types: [AssessmentType] { schoolSettings.values.selectableTypes(hasWrittenWork: hasWrittenWork) }

    private var maxPoints: Double? {
        Double(maxPointsText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !subject.isEmpty && (!usesPoints || maxPoints != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        TextField("Titel (z. B. Klassenarbeit 2)", text: $title)
                    } icon: {
                        Image(icon: .label)
                    }
                    Picker(selection: $typeID) {
                        ForEach(types) { Text($0.name).tag(Optional($0.id)) }
                    } label: {
                        Label("Art", icon: .page)
                    }
                    if hasWrittenWork {
                        Picker("Bereich", selection: $area) {
                            ForEach(AssessmentArea.allCases) { Text(schoolSettings.values.areaName($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section {
                    if (schoolClass?.subjects.count ?? 0) > 1 {
                        Picker(selection: $subject) {
                            ForEach(schoolClass?.subjects ?? [], id: \.self) { Text(SchoolClass.displayName(ofSubject: $0)).tag($0) }
                        } label: {
                            Label("Fach", icon: .graduationCap)
                        }
                    }
                    DatePicker(selection: $date, displayedComponents: .date) {
                        Label("Datum", icon: .calendar)
                    }
                }
                Section {
                    Toggle(isOn: $usesPoints) {
                        Label("Mit Rohpunkten bewerten", icon: .number1Circle)
                    }
                    if usesPoints {
                        TextField("Höchstpunktzahl (z. B. 50)", text: $maxPointsText)
                            .keyboardType(.decimalPad)
                    }
                } footer: {
                    Text(usesPoints
                        ? loc("""
                            Aus den Punkten wird die Note nach der Abitur-Tabelle vorgeschlagen (95 % = 15 Punkte bzw. 1+); \
                            sie lässt sich je Schüler ändern.
                            """)
                        : loc("Die Note tragen Sie je Schüler direkt ein."))
                }
            }
            .navigationTitle(isNew ? "Neue Leistung" : "Leistung bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: isNew ? loc("Anlegen") : loc("Sichern"), action: save)
                        .disabled(!isValid)
                }
            }
            .onChange(of: typeID) { _, id in
                if let type = types.first(where: { $0.id == id }) { area = type.area }
            }
            .onChange(of: hasWrittenWork) { _, written in
                if !written { area = .other }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        switch route {
        case .new(let schoolClass, let preferred):
            subject = preferred.flatMap { schoolClass.subjects.contains($0) ? $0 : nil } ?? schoolClass.subjects.first ?? ""
            typeID = types.first?.id
            area = types.first?.area ?? .other
        case .edit(let assessment):
            title = assessment.title
            subject = assessment.subject
            date = assessment.date
            area = assessment.area
            typeID = types.first { $0.name == assessment.typeName }?.id
            usesPoints = assessment.maxPoints != nil
            maxPointsText = assessment.maxPoints.map { $0.formatted() } ?? ""
        }
    }

    private func save() {
        guard let schoolClass else { return }
        let typeName = types.first { $0.id == typeID }?.name ?? ""
        let points = usesPoints ? maxPoints : nil
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        switch route {
        case .new:
            modelContext.insert(Assessment(
                subject: subject, title: cleanTitle, typeName: typeName, area: area, date: date, maxPoints: points, schoolClass: schoolClass
            ))
        case .edit(let assessment):
            assessment.title = cleanTitle
            assessment.subject = subject
            assessment.date = date
            assessment.area = area
            if !typeName.isEmpty { assessment.typeName = typeName }
            assessment.maxPoints = points
        }
        try? modelContext.save()
        dismiss()
    }
}

/// Note eines Schülers in einer Leistung wählen (Menü mit allen Noten des Notensystems).
struct GradeMenu: View {
    let grade: String
    let system: GradeSystem
    var placeholder = "–"
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            Button("Keine Note") { onSelect("") }
            Divider()
            ForEach(GradeScale.values(for: system), id: \.self) { value in
                Button(value) { onSelect(value) }
            }
        } label: {
            Text(grade.isEmpty ? placeholder : grade)
                .font(grade.isEmpty && placeholder.count > 1 ? .subheadline.weight(.medium) : .title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                // Platzhalter wie „eintragen“ brauchen Innenabstand, eine Note nicht.
                .padding(.horizontal, grade.isEmpty && placeholder.count > 1 ? 12 : 0)
                .frame(minWidth: 44, minHeight: 36)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .sensitive()
        }
        .menuOrder(.fixed)
    }
}
