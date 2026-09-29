import SwiftData
import SwiftUI

enum LinkEditorRoute: Identifiable {
    case newWebsite(SchoolClass)
    case edit(DashboardLink)

    var id: String {
        switch self {
        case .newWebsite(let schoolClass): "new-\(schoolClass.id)"
        case .edit(let link): link.id.uuidString
        }
    }
}

/// Sheet: Website-Kachel anlegen bzw. eigene Kachel bearbeiten.
/// Bei Dokumenten ist nur der Titel änderbar.
struct LinkEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let route: LinkEditorRoute

    @State private var title: String
    @State private var address: String

    init(route: LinkEditorRoute) {
        self.route = route
        switch route {
        case .newWebsite:
            _title = State(initialValue: "")
            _address = State(initialValue: "")
        case .edit(let link):
            _title = State(initialValue: link.title)
            _address = State(initialValue: link.kind == .website ? link.location : "")
        }
    }

    private var isWebsite: Bool {
        switch route {
        case .newWebsite: true
        case .edit(let link): link.kind == .website
        }
    }

    private var isNew: Bool {
        if case .newWebsite = route { true } else { false }
    }

    private var isValid: Bool {
        isWebsite ? URL.web(address) != nil : !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $title)
                    if isWebsite {
                        TextField("Adresse (z. B. schule.de/vertretungsplan)", text: $address)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } footer: {
                    if isWebsite, !address.isEmpty, URL.web(address) == nil {
                        Text("Keine gültige Adresse.")
                    }
                }
            }
            .navigationTitle(isNew ? "Website hinzufügen" : "Kachel bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Hinzufügen" : "Sichern", action: save)
                        .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        switch route {
        case .newWebsite(let schoolClass):
            guard let url = URL.web(address) else { return }
            modelContext.insert(DashboardLink(
                title: trimmedTitle.isEmpty ? (url.host() ?? "") : trimmedTitle,
                kind: .website,
                location: url.absoluteString,
                schoolClass: schoolClass
            ))
        case .edit(let link):
            link.title = trimmedTitle
            if link.kind == .website, let url = URL.web(address) {
                link.location = url.absoluteString
            }
        }
        try? modelContext.save()
        dismiss()
    }
}
