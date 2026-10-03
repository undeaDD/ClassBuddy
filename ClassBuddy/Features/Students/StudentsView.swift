import CoreText
import SwiftData
import SwiftUI

/// Schülerliste der ausgewählten Klasse: alphabetisch nach Vornamen gruppiert,
/// durchsuchbar. Im Privatsphäre-Modus nur lesend.
struct StudentsView: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @Query private var classes: [SchoolClass]

    @State private var searchText = ""
    @State private var editorRoute: StudentEditorRoute?
    @State private var studentPendingDeletion: Student?

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == app.selectedClassID }
    }

    /// Bearbeiten ist im Privatsphäre-Modus gesperrt.
    private var canEdit: Bool { !security.isPrivacyModeOn }

    var body: some View {
        ClassScopedView { schoolClass in
            content(for: schoolClass)
        }
        .navigationTitle(AppTab.students.title)
        .navigationSubtitle(selectedClass.map { loc("\($0.students.count) Schüler") } ?? "")
        .appChrome(tab: .students) {
            if let selectedClass {
                Button("Schüler hinzufügen", icon: .plus) {
                    editorRoute = .new(selectedClass)
                }
                .disabled(!canEdit)
            }
        }
        .fullScreenCover(item: $editorRoute) { route in
            StudentEditorView(route: route)
                .softScrollEdges()
        }
        .confirmationDialog(
            "Schüler löschen?",
            isPresented: Binding(
                get: { studentPendingDeletion != nil },
                set: { if !$0 { studentPendingDeletion = nil } }
            ),
            presenting: studentPendingDeletion
        ) { student in
            Button("Löschen", role: .destructive) { delete(student) }
        } message: { _ in
            Text("Das kann nicht rückgängig gemacht werden.")
        }
        // Privatsphäre-Modus an → offene Editoren/Dialoge sofort schließen.
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                editorRoute = nil
                studentPendingDeletion = nil
            }
        }
    }

    @ViewBuilder
    private func content(for schoolClass: SchoolClass) -> some View {
        if schoolClass.students.isEmpty {
            EmptyStateView(
                title: loc("Noch keine Schüler"),
                message: loc("Fügen Sie über + oben rechts die Schülerinnen und Schüler der \(schoolClass.title) hinzu."),
                symbol: AppTab.students.symbol
            )
            .background(Color(.systemGroupedBackground))
        } else {
            let sections = StudentLetterSection.sections(for: filtered(schoolClass.students))
            List {
                ForEach(sections, id: \.letter) { section in
                    Section(section.letter) {
                        ForEach(section.students) { student in
                            row(for: student)
                        }
                    }
                    .sectionIndexLabel(section.letter)
                }
            }
            .listSectionIndexVisibility(.visible)
            .searchable(text: $searchText, prompt: "Schüler suchen")
            .overlay {
                if sections.isEmpty {
                    SearchEmptyStateView(text: searchText)
                }
            }
        }
    }

    /// Antippen → Fächer des Schülers (Notizen). Bearbeiten und Löschen über Wischen oder langes Drücken.
    private func row(for student: Student) -> some View {
        NavigationLink {
            StudentSubjectsView(student: student)
        } label: {
            rowLabel(for: student)
        }
        .contentShape(.rect)
        // Nach rechts wischen: bearbeiten
        .swipeActions(edge: .leading) {
            if canEdit {
                Button("Bearbeiten", icon: .editPencil) { editorRoute = .edit(student) }
                    .tint(accent)
            }
        }
        // Nach links wischen: löschen
        .swipeActions(edge: .trailing) {
            if canEdit {
                Button("Löschen", icon: .trash, role: .destructive) { studentPendingDeletion = student }
            }
        }
        .contextMenu {
            if canEdit {
                Button("Bearbeiten", icon: .editPencil) { editorRoute = .edit(student) }
                Button("Löschen", destructiveIcon: .trash) { studentPendingDeletion = student }
            }
        }
    }

    private func rowLabel(for student: Student) -> some View {
        HStack(spacing: 12) {
            StudentAvatar(student: student, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.fullName)
                    .font(.body.weight(.medium))
                    .sensitive()
                if let age = student.age {
                    Text("\(age) Jahre")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .sensitive()
                }
            }
            Spacer()
            // Notizen-Hinweis (im Privatsphäre-Modus verborgen); den Pfeil zeichnet der NavigationLink.
            if !student.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Image(icon: .notes)
                    .iconSize(18)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
                    .sensitive()
                    .accessibilityLabel("Hat Notizen")
            }
        }
    }

    private func filtered(_ students: [Student]) -> [Student] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return students }
        return students.filter { $0.fullName.localizedStandardContains(query) }
    }

    private func delete(_ student: Student) {
        modelContext.delete(student)
        do {
            try modelContext.save()
            toasts.success(loc("Schüler gelöscht"))
        } catch {
            toasts.error(loc("Löschen fehlgeschlagen: \(error.localizedDescription)"))
        }
    }
}

/// Kreis mit Initialen und kleinem Geschlechts-Indikator.
struct StudentAvatar: View {
    let initials: String
    var photo: Data?
    var gender: Gender?
    var size: CGFloat = 40

    init(student: Student, size: CGFloat = 40) {
        self.init(initials: student.initials, photo: student.photo, gender: student.gender, size: size)
    }

    init(initials: String, photo: Data?, gender: Gender?, size: CGFloat = 40) {
        self.initials = initials
        self.photo = photo
        self.gender = gender
        self.size = size
    }

    var body: some View {
        Group {
            if let image = photo.flatMap(StudentPhoto.image(from:)) {
                // Foto im Privatsphäre-Modus unscharf.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.circle)
                    .sensitiveBlur(radius: size / 4)
            } else {
                Text(initials.isEmpty ? "?" : initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tint)
                    .frame(width: size, height: size)
                    .background(.tint.opacity(0.15), in: .circle)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let gender {
                GenderBadge(gender: gender, size: size * 0.42)
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
    }
}

/// Geschlechts-Symbol in der Ecke des Avatars. Der Hintergrund hat die Farbe der Umgebung
/// (`avatarCutout`), dadurch wirkt es wie aus dem Bild ausgeschnitten.
struct GenderBadge: View {
    @Environment(\.avatarCutout) private var cutout
    let gender: Gender
    var size: CGFloat = 16

    var body: some View {
        let fontSize = size * 0.78
        Text(gender.symbol)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(gender.color)
            .fixedSize()
            .offset(GlyphCentering.offset(of: gender.symbol, size: fontSize, weight: .bold))
            .frame(width: size, height: size)
            .background {
                ZStack {
                    ForEach(cutout.indices, id: \.self) { Circle().fill(cutout[$0]) }
                }
            }
            .accessibilityLabel(gender.displayTitle)
    }
}

extension EnvironmentValues {
    /// Farbschichten hinter dem Geschlechts-Symbol = Hintergrund, auf dem der Avatar liegt
    /// (Standard: Zeile einer gruppierten Liste; Sitzplan: Fläche plus Tischfarbe).
    @Entry var avatarCutout: [Color] = [Color(.secondarySystemGroupedBackground)]
}

/// Symbole wie ♀ ♂ ⚧ sitzen nicht mittig in ihrer Laufweite; SwiftUI zentriert aber die Laufweite.
/// Der Versatz verschiebt die sichtbare Glyphe (Umriss laut CoreText) in die Mitte.
enum GlyphCentering {
    @MainActor private static var cache: [String: CGSize] = [:]

    @MainActor
    static func offset(of text: String, size: CGFloat, weight: UIFont.Weight) -> CGSize {
        let key = "\(text)|\(size)|\(weight.rawValue)"
        if let cached = cache[key] { return cached }
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let box = CTLineGetBoundsWithOptions(line, [])
        // CoreText zählt y nach oben, SwiftUI nach unten.
        let offset = ink.isEmpty ? .zero : CGSize(width: box.midX - ink.midX, height: ink.midY - box.midY)
        cache[key] = offset
        return offset
    }
}

extension Gender {
    var color: Color {
        switch self {
        case .female: .pink
        case .male: .blue
        case .diverse: .purple
        }
    }
}

/// Alphabetischer Abschnitt einer Schülerliste (nach Vornamen), mit Schnell-Index rechts.
struct StudentLetterSection {
    let letter: String
    let students: [Student]

    /// Nach Vor- und Nachnamen sortiert, „#“ (kein Buchstabe) zuletzt.
    static func sections(for students: [Student]) -> [StudentLetterSection] {
        let sorted = students.sorted {
            let byFirst = $0.firstName.localizedStandardCompare($1.firstName)
            return byFirst == .orderedSame
                ? $0.lastName.localizedStandardCompare($1.lastName) == .orderedAscending
                : byFirst == .orderedAscending
        }
        let grouped = Dictionary(grouping: sorted, by: \.sectionLetter)
        return grouped.keys
            .sorted { $0 == "#" ? false : $1 == "#" ? true : $0 < $1 }
            .map { StudentLetterSection(letter: $0, students: grouped[$0] ?? []) }
    }
}
