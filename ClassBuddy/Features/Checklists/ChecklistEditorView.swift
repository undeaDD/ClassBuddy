import SwiftData
import SwiftUI

enum ChecklistEditorRoute: Identifiable {
    /// Neue Checkliste; `subject` ist die Vorauswahl (aktuelle Stunde).
    case new(SchoolClass, subject: String?)
    case edit(Checklist)

    var id: String {
        switch self {
        case .new(let schoolClass, _): "new-\(schoolClass.id)"
        case .edit(let checklist): checklist.id.uuidString
        }
    }
}

/// Anlegen bzw. Bearbeiten: Titel und Untertitel frei, dazu ein Fach oder „Für alle Fächer der Klasse“.
struct ChecklistEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    let route: ChecklistEditorRoute

    @State private var title = ""
    @State private var subtitle = ""
    @State private var isGlobal = false
    @State private var subject = ""
    @State private var hasDueDate = false
    @State private var dueDate = Calendar.school.date(byAdding: .day, value: 7, to: .now) ?? .now

    private var schoolClass: SchoolClass? {
        switch route {
        case .new(let schoolClass, _): schoolClass
        case .edit(let checklist): checklist.schoolClass
        }
    }

    private var isNew: Bool {
        if case .new = route { return true }
        return false
    }

    private var subjects: [String] { schoolClass?.subjects ?? [] }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        TextField("Titel", text: $title)
                    } icon: {
                        Image(icon: .label)
                    }
                    Label {
                        TextField("Untertitel (optional)", text: $subtitle)
                    } icon: {
                        Image(icon: .label)
                    }
                }

                Section {
                    Toggle(isOn: $isGlobal) {
                        Label("Für alle Fächer der Klasse", icon: .graduationCap)
                    }
                    .disabled(subjects.isEmpty)
                    if !isGlobal {
                        Picker(selection: $subject) {
                            ForEach(subjects, id: \.self) { Text(SchoolClass.displayName(ofSubject: $0)).tag($0) }
                        } label: {
                            Label("Fach", icon: .graduationCap)
                        }
                    }
                } footer: {
                    Text(isGlobal
                        ? loc("Die Checkliste erscheint in jedem Fach der Klasse, mit denselben Haken.")
                        : loc("Die Checkliste gehört nur zu diesem Fach."))
                }

                Section {
                    Toggle(isOn: $hasDueDate.animation()) {
                        Label("Enddatum", icon: .calendar)
                    }
                    if hasDueDate {
                        DatePicker(selection: $dueDate, displayedComponents: .date) {
                            Label("Bis", icon: .calendar)
                        }
                    }
                } footer: {
                    Text("Optional: Nach dem Enddatum wird die Checkliste rot markiert, solange noch Schüler offen sind.")
                }

                if isNew {
                    Section("Vorlagen") {
                        ForEach(ChecklistTemplates.all, id: \.self) { template in
                            Button {
                                title = template.title
                                subtitle = template.subtitle
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.title).foregroundStyle(.primary)
                                    Text(template.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .readableFormWidth()
            .navigationTitle(isNew ? "Neue Checkliste" : "Checkliste bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: isNew ? loc("Anlegen") : loc("Sichern"), action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        switch route {
        case .new(let schoolClass, let current):
            isGlobal = schoolClass.subjects.isEmpty
            subject = current ?? schoolClass.subjects.first ?? ""
        case .edit(let checklist):
            title = checklist.title
            subtitle = checklist.subtitle
            isGlobal = checklist.isGlobal
            subject = checklist.isGlobal ? (subjects.first ?? "") : checklist.subject
            hasDueDate = checklist.dueDate != nil
            dueDate = checklist.dueDate ?? dueDate
        }
    }

    private func save() {
        let scope = isGlobal ? "" : subject
        let cleanSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = hasDueDate ? Calendar.school.startOfDay(for: dueDate) : nil
        switch route {
        case .new(let schoolClass, _):
            let checklist = Checklist(title: trimmedTitle, subtitle: cleanSubtitle, subject: scope, schoolClass: schoolClass)
            checklist.dueDate = due
            modelContext.insert(checklist)
        case .edit(let checklist):
            checklist.dueDate = due
            checklist.title = trimmedTitle
            checklist.subtitle = cleanSubtitle
            checklist.subject = scope
            checklist.updatedAt = .now
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            toasts.error(loc("Speichern fehlgeschlagen: \(error.localizedDescription)"))
        }
    }
}
