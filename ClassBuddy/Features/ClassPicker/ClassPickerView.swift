import SwiftData
import SwiftUI

/// Liste aller Klassen zum Wechseln + Neue Klasse anlegen.
struct ClassPickerView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\SchoolClass.schoolYear, order: .reverse), SortDescriptor(\SchoolClass.shortName)])
    private var classes: [SchoolClass]

    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Group {
                if classes.isEmpty {
                    EmptyStateView(
                        title: "Noch keine Klassen",
                        message: "Lege deine erste Klasse an.",
                        symbol: .system("person.2.badge.plus")
                    ) {
                        Button("Klasse anlegen") { isCreating = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(classes) { schoolClass in
                            row(for: schoolClass)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Klassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Neue Klasse", systemImage: "plus") { isCreating = true }
                }
            }
            .navigationDestination(isPresented: $isCreating) {
                ClassEditorView { newClass in
                    app.selectedClassID = newClass.id
                    app.isClassPickerPresented = false
                }
            }
        }
        .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
    }

    private func row(for schoolClass: SchoolClass) -> some View {
        Button {
            app.selectedClassID = schoolClass.id
            app.isClassPickerPresented = false
        } label: {
            HStack(spacing: 12) {
                ClassBadge(shortName: schoolClass.shortName, color: schoolClass.color.color, size: 40)
                VStack(alignment: .leading) {
                    Text(schoolClass.title).font(.body.weight(.medium))
                    Text(schoolClass.detailLine).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if app.selectedClassID == schoolClass.id {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let schoolClass = classes[index]
            if app.selectedClassID == schoolClass.id { app.selectedClassID = nil }
            modelContext.delete(schoolClass)
        }
    }
}

/// Formular zum Anlegen einer Klasse.
struct ClassEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var onCreate: (SchoolClass) -> Void

    @State private var shortName = ""
    @State private var subtitle = ""
    @State private var schoolYear = SchoolClass.currentSchoolYear
    @State private var color: ClassColor = .blue

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    ClassBadge(shortName: shortName, color: color.color, size: 72)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section("Klasse") {
                TextField("Kürzel (z. B. 7b)", text: $shortName)
                    .textInputAutocapitalization(.never)
                TextField("Fach / Rolle (z. B. Mathematik)", text: $subtitle)
                TextField("Schuljahr", text: $schoolYear)
            }
            Section("Farbe") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(ClassColor.allCases) { option in
                        Circle()
                            .fill(option.color.gradient)
                            .frame(width: 32, height: 32)
                            .overlay {
                                if option == color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture { color = option }
                            .hoverEffect(.lift)
                            .accessibilityLabel(option.rawValue)
                            .accessibilityAddTraits(option == color ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Neue Klasse")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Anlegen", action: create)
                    .disabled(shortName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func create() {
        let newClass = SchoolClass(
            shortName: shortName.trimmingCharacters(in: .whitespaces),
            subtitle: subtitle.trimmingCharacters(in: .whitespaces),
            schoolYear: schoolYear.trimmingCharacters(in: .whitespaces),
            color: color
        )
        modelContext.insert(newClass)
        onCreate(newClass)
        dismiss()
    }
}
