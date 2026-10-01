import SwiftData
import SwiftUI

enum LinkEditorRoute: Identifiable {
    case new(DashboardLink.Kind, SchoolClass)
    case edit(DashboardLink)

    var id: String {
        switch self {
        case .new(let kind, let schoolClass): "new-\(kind.rawValue)-\(schoolClass.id)"
        case .edit(let link): link.id.uuidString
        }
    }

    var kind: DashboardLink.Kind {
        switch self {
        case .new(let kind, _): kind
        case .edit(let link): link.kind
        }
    }
}

/// Sheet: Website- oder Kurzbefehl-Kachel anlegen bzw. eigene Kachel bearbeiten.
/// Bei Dokumenten und Bildern ist nur der Titel änderbar.
struct LinkEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let route: LinkEditorRoute

    @State private var title: String
    /// Website-Adresse bzw. Name des Kurzbefehls.
    @State private var target: String

    init(route: LinkEditorRoute) {
        self.route = route
        switch route {
        case .new:
            _title = State(initialValue: "")
            _target = State(initialValue: "")
        case .edit(let link):
            _title = State(initialValue: link.title)
            _target = State(initialValue: link.kind.isStoredFile ? "" : link.location)
        }
    }

    private var isNew: Bool {
        if case .new = route { true } else { false }
    }

    private var trimmedTarget: String { target.trimmingCharacters(in: .whitespaces) }

    private var isValid: Bool {
        switch route.kind {
        case .website: URL.web(target) != nil
        case .shortcut: !trimmedTarget.isEmpty
        case .file, .image, .script: !title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var navigationTitle: String {
        guard isNew else { return loc("Kachel bearbeiten") }
        return route.kind == .shortcut ? loc("Kurzbefehl hinzufügen") : loc("Website hinzufügen")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $title)
                    targetField
                } footer: {
                    footer
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: isNew ? "Hinzufügen" : loc("Sichern"), action: save)
                        .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var targetField: some View {
        switch route.kind {
        case .website:
            TextField("Adresse (z. B. schule.de/vertretungsplan)", text: $target, prompt: Text("https://… oder App-Link"))
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .shortcut:
            TextField("Name des Kurzbefehls", text: $target)
                .autocorrectionDisabled()
            Button("Kurzbefehle-App öffnen", image: .navArrowRight) {
                if let url = URL(string: "shortcuts://") { openURL(url) }
            }
        case .file, .image, .script:
            EmptyView()
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch route.kind {
        case .website where !target.isEmpty && URL.web(target) == nil:
            Text("Nur https:// oder App-Links (z. B. notability://) sind erlaubt, kein http, ftp oder file.")
        case .shortcut:
            Text("Genau so schreiben wie in der Kurzbefehle-App. Antippen der Kachel startet den Kurzbefehl.")
        default:
            EmptyView()
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        switch route {
        case .new(let kind, let schoolClass):
            guard let location = location(for: kind) else { return }
            modelContext.insert(DashboardLink(
                title: trimmedTitle.isEmpty && kind == .website ? (URL.web(target)?.host() ?? "") : trimmedTitle,
                kind: kind,
                location: location,
                schoolClass: schoolClass
            ))
        case .edit(let link):
            link.title = trimmedTitle
            if let location = location(for: link.kind) { link.location = location }
        }
        try? modelContext.save()
        dismiss()
    }

    /// Ziel der Kachel: normalisierte URL bzw. Name des Kurzbefehls; Dateien bleiben unverändert.
    private func location(for kind: DashboardLink.Kind) -> String? {
        switch kind {
        case .website: URL.web(target)?.absoluteString
        case .shortcut: trimmedTarget.isEmpty ? nil : trimmedTarget
        case .file, .image, .script: nil
        }
    }
}
