import SwiftData
import SwiftUI

// Zufallsgruppen: Kachel → Abfrage (Gruppengröße oder Anzahl) → Ergebnis-Sheet mit Neu mischen und PDF.
// Das letzte Ergebnis wird je Klasse gespeichert und lässt sich aus der Abfrage wieder öffnen.

/// Aufteilung nach Gruppengröße oder nach Anzahl der Gruppen.
nonisolated enum GroupMode: String, Codable, CaseIterable, Identifiable {
    case size
    case count

    var id: String { rawValue }

    var title: String {
        switch self {
        case .size: loc("Gruppengröße")
        case .count: loc("Anzahl Gruppen")
        }
    }
}

/// Reine Logik der Aufteilung (testbar, ohne SwiftData).
nonisolated enum GroupSplit {
    /// Erlaubte Werte für den Stepper (Größe bzw. Anzahl): mindestens 2, höchstens die halbe Klasse.
    static func range(studentCount: Int) -> ClosedRange<Int> {
        2...max(2, studentCount / 2)
    }

    /// Vorbelegung: Größe 4, 3 oder 5, wenn die Klasse dann genau aufgeht, sonst 4; kleine Klassen paarweise.
    static func suggestedValue(studentCount: Int, mode: GroupMode) -> Int {
        let size = studentCount < 6 ? 2 : ([4, 3, 5].first { studentCount.isMultiple(of: $0) } ?? 4)
        let clamped = size.clamped(to: range(studentCount: studentCount))
        switch mode {
        case .size: return clamped
        case .count: return max(1, sizes(studentCount: studentCount, mode: .size, value: clamped).count)
                .clamped(to: range(studentCount: studentCount))
        }
    }

    /// Wert beim Wechsel des Modus übernehmen, damit die Aufteilung möglichst gleich bleibt.
    static func convert(_ value: Int, from mode: GroupMode, studentCount: Int) -> Int {
        let current = sizes(studentCount: studentCount, mode: mode, value: value)
        guard !current.isEmpty else { return suggestedValue(studentCount: studentCount, mode: mode == .size ? .count : .size) }
        let converted = switch mode {
        case .size: current.count
        case .count: Int((Double(studentCount) / Double(current.count)).rounded())
        }
        return converted.clamped(to: range(studentCount: studentCount))
    }

    /// Größen der Gruppen, absteigend; sie unterscheiden sich höchstens um 1.
    /// Nach Größe: Anzahl so gewählt, dass die Gruppen möglichst nah an der Wunschgröße liegen
    /// (bei Gleichstand lieber etwas größere Gruppen, z. B. 26 bei Größe 4 → 2 × 5 und 4 × 4).
    static func sizes(studentCount: Int, mode: GroupMode, value: Int) -> [Int] {
        guard studentCount > 0, value > 0 else { return [] }
        let count: Int
        switch mode {
        case .count:
            count = min(value, studentCount)
        case .size:
            let lower = max(1, studentCount / value)
            let upper = min(studentCount, lower + 1)
            count = deviation(studentCount: studentCount, count: upper, from: value)
                < deviation(studentCount: studentCount, count: lower, from: value) ? upper : lower
        }
        return evenSizes(studentCount: studentCount, count: count)
    }

    private static func evenSizes(studentCount: Int, count: Int) -> [Int] {
        let base = studentCount / count, remainder = studentCount % count
        return (0..<count).map { $0 < remainder ? base + 1 : base }
    }

    private static func deviation(studentCount: Int, count: Int, from size: Int) -> Int {
        let sizes = evenSizes(studentCount: studentCount, count: count)
        return max(abs((sizes.first ?? 0) - size), abs((sizes.last ?? 0) - size))
    }

    /// Verteilt die Elemente zufällig auf Gruppen der angegebenen Größen.
    static func deal<T, G: RandomNumberGenerator>(_ items: [T], sizes: [Int], using generator: inout G) -> [[T]] {
        var remaining = items.shuffled(using: &generator)[...]
        return sizes.map { size in
            let group = Array(remaining.prefix(size))
            remaining = remaining.dropFirst(size)
            return group
        }
    }

    /// Vorschau als ganzer Satz.
    static func sentence(sizes: [Int]) -> String {
        guard let largest = sizes.first, let smallest = sizes.last else { return loc("Die Klasse hat noch keine Schüler.") }
        let total = sizes.reduce(0, +)
        if sizes.count == 1 { return loc("Es entsteht eine Gruppe mit allen \(total) Schülern.") }
        if largest == smallest { return loc("Es entstehen \(sizes.count) Gruppen mit je \(largest) Schülern.") }
        return loc("Es entstehen \(sizes.count) Gruppen mit \(smallest) bis \(largest) Schülern.")
    }

    /// Kurzform für die Kachel, z. B. „6 × 4“ oder „6 × 4–5“.
    static func shortSummary(sizes: [Int]) -> String {
        guard let largest = sizes.first, let smallest = sizes.last else { return "–" }
        return largest == smallest ? "\(sizes.count) × \(largest)" : "\(sizes.count) × \(smallest)–\(largest)"
    }
}

nonisolated private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Gespeichertes Ergebnis (je Klasse das letzte).
nonisolated struct StudentGroups: Codable, Hashable {
    var mode: GroupMode
    var value: Int
    var groups: [[UUID]]
    var date: Date

    /// Neue Aufteilung der Schüler.
    static func deal(_ studentIDs: [UUID], mode: GroupMode, value: Int, date: Date = .now) -> StudentGroups {
        var generator = SystemRandomNumberGenerator()
        return deal(studentIDs, mode: mode, value: value, date: date, using: &generator)
    }

    static func deal<G: RandomNumberGenerator>(
        _ studentIDs: [UUID], mode: GroupMode, value: Int, date: Date = .now, using generator: inout G
    ) -> StudentGroups {
        let sizes = GroupSplit.sizes(studentCount: studentIDs.count, mode: mode, value: value)
        return StudentGroups(mode: mode, value: value, groups: GroupSplit.deal(studentIDs, sizes: sizes, using: &generator), date: date)
    }

    /// Schüler je Gruppe in Klassenreihenfolge; gelöschte Schüler und leere Gruppen fallen weg.
    func resolved(in students: [Student]) -> [[Student]] {
        let order = Dictionary(uniqueKeysWithValues: students.enumerated().map { ($1.id, $0) })
        return groups
            .map { group in group.compactMap { id in order[id].map { students[$0] } }.sorted { order[$0.id] ?? 0 < order[$1.id] ?? 0 } }
            .filter { !$0.isEmpty }
    }
}

extension SchoolClass {
    /// Letzte Zufallsgruppen der Klasse (JSON in `lastGroupsData`).
    var lastGroups: StudentGroups? {
        get { lastGroupsData.flatMap { try? JSONDecoder().decode(StudentGroups.self, from: $0) } }
        set { lastGroupsData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

// MARK: - Kachel

/// Kachel „Gruppen“: zeigt das letzte Ergebnis, antippen öffnet immer die Abfrage.
struct GroupsCard: View {
    @Environment(\.device) private var device
    @Environment(AppSecurity.self) private var security
    let schoolClass: SchoolClass

    @State private var isPromptPresented = false
    /// Aus der Abfrage gewähltes Ergebnis – erst nach deren Schließen gezeigt (sonst kollidieren die Sheets).
    @State private var pendingResult: GroupsResultRoute?
    @State private var result: GroupsResultRoute?

    var body: some View {
        let card = DashboardBuiltInCard.groups
        let last = schoolClass.lastGroups
        StatCard(
            title: card.title,
            value: last.map { GroupSplit.shortSummary(sizes: $0.resolved(in: schoolClass.sortedStudents).map(\.count)) } ?? "?",
            detail: last.map { Self.lastDateText($0.date) } ?? loc("Antippen zum Einteilen"),
            symbol: card.symbol,
            isSensitive: false
        ) {
            isPromptPresented = true
        }
        .sheet(isPresented: $isPromptPresented, onDismiss: showPendingResult) {
            GroupsPromptView(schoolClass: schoolClass) { pendingResult = $0 }
        }
        .sheet(item: device.isPhone ? .constant(nil) : $result) { route in
            GroupsResultView(schoolClass: schoolClass, route: route)
                .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
                .appPresentationSizing(.form)
        }
        .fullScreenCover(item: device.isPhone ? $result : .constant(nil)) { route in
            // Privatsphäre-Modus und Geräteweiche im Cover erneut setzen.
            GroupsResultView(schoolClass: schoolClass, route: route)
                .environment(\.device, device)
                .redacted(reason: security.isPrivacyModeOn ? .privacy : [])
        }
    }

    private func showPendingResult() {
        result = pendingResult
        pendingResult = nil
    }

    static func lastDateText(_ date: Date) -> String {
        let time = date.appTime
        if Calendar.current.isDateInToday(date) { return loc("Zuletzt heute um \(time)") }
        return loc("Zuletzt am \(date.appDate) um \(time)")
    }
}

/// Was das Ergebnis-Sheet zeigt: neu gemischte Gruppen (noch nicht gespeichert) oder die letzten.
struct GroupsResultRoute: Identifiable {
    let id = UUID()
    var groups: StudentGroups
    var isNew: Bool
}

// MARK: - Abfrage

struct GroupsPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSecurity.self) private var security
    let schoolClass: SchoolClass
    let onResult: (GroupsResultRoute) -> Void

    @State private var mode: GroupMode = .size
    @State private var value = 4

    private var studentCount: Int { schoolClass.students.count }
    private var sizes: [Int] { GroupSplit.sizes(studentCount: studentCount, mode: mode, value: value) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Einteilen nach", selection: $mode) {
                        ForEach(GroupMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    Stepper(value: $value, in: GroupSplit.range(studentCount: studentCount)) {
                        LabeledContent(mode.title) {
                            Text(value, format: .number)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                    .disabled(studentCount < 2)
                } footer: {
                    Text(GroupSplit.sentence(sizes: sizes))
                        .contentTransition(.numericText())
                }
                if let last = schoolClass.lastGroups {
                    Section("Letzte Gruppen") {
                        Button {
                            onResult(GroupsResultRoute(groups: last, isNew: false))
                            dismiss()
                        } label: {
                            LabeledContent {
                                Text(GroupsCard.lastDateText(last.date))
                            } label: {
                                Label("Letzte Gruppen öffnen", icon: .shareIos)
                            }
                        }
                    }
                }
            }
            .animation(.smooth, value: value)
            .navigationTitle(DashboardBuiltInCard.groups.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                        .toolbarGroupBackground()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: loc("Gruppen bilden"), action: create)
                        .disabled(studentCount < 2 || security.isPrivacyModeOn)
                        .toolbarGroupBackground(prominent: true)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            // Letzte Einstellung übernehmen, sonst gleich große Gruppen vorschlagen.
            if let last = schoolClass.lastGroups {
                mode = last.mode
                value = last.value.clamped(to: GroupSplit.range(studentCount: studentCount))
            } else {
                value = GroupSplit.suggestedValue(studentCount: studentCount, mode: mode)
            }
        }
        .onChange(of: mode) { old, _ in
            value = GroupSplit.convert(value, from: old, studentCount: studentCount)
        }
    }

    private func create() {
        onResult(GroupsResultRoute(groups: .deal(schoolClass.students.map(\.id), mode: mode, value: value), isNew: true))
        FunStat.groupsDealt.increment()
        dismiss()
    }
}

// MARK: - Ergebnis

/// Gruppen als Raster. Neu gemischte Gruppen werden erst mit dem Haken gespeichert, xmark verwirft sie.
struct GroupsResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSecurity.self) private var security
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.device) private var device
    let schoolClass: SchoolClass

    @State private var groups: StudentGroups
    @State private var isChanged: Bool
    @State private var pdfPreview: URL?

    init(schoolClass: SchoolClass, route: GroupsResultRoute) {
        self.schoolClass = schoolClass
        _groups = State(initialValue: route.groups)
        _isChanged = State(initialValue: route.isNew)
    }

    private var resolved: [[Student]] { groups.resolved(in: schoolClass.sortedStudents) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    // iPhone: volle Breite untereinander, damit Namen nicht abgeschnitten werden.
                    columns: device.isPhone
                        ? [GridItem(.flexible(), spacing: 16, alignment: .top)]
                        : [GridItem(.adaptive(minimum: 200), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(Array(resolved.enumerated()), id: \.offset) { index, students in
                        GroupTile(number: index + 1, students: students)
                    }
                }
                .padding(20)
                .animation(.smooth, value: groups)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(DashboardBuiltInCard.groups.title)
            .appNavigationSubtitle(GroupSplit.sentence(sizes: resolved.map(\.count)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .quickLookPreview($pdfPreview)
        }
        .tint(schoolClass.displayColor)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Schließen", icon: .xmark, role: .appClose) { dismiss() }
                .toolbarGroupBackground()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Neu mischen", icon: .shuffle, action: Haptics.tapping(reshuffle))
                // Vorschau (Quick Look): dort sichern, drucken oder teilen.
                Button("Als PDF exportieren", icon: .page) {
                    pdfPreview = GroupsPDF.make(schoolClass: schoolClass, groups: resolved, date: groups.date)
                }
            } label: {
                Label("Mehr", icon: .moreHoriz)
            }
            // Im Privatsphäre-Modus weder mischen noch teilen.
            .disabled(security.isPrivacyModeOn)
            .toolbarGroupBackground()
        }
        AppToolbarSpacer(placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            PrivacyModeButton()
                .toolbarGroupBackground()
        }
        // Haken ganz rechts wie in allen Sheets.
        AppToolbarSpacer(placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            ConfirmButton(title: loc("Sichern"), action: save)
                .toolbarGroupBackground(prominent: true)
        }
    }

    private func reshuffle() {
        withAnimation(.bouncy) {
            groups = .deal(schoolClass.students.map(\.id), mode: groups.mode, value: groups.value)
        }
        isChanged = true
        FunStat.groupsDealt.increment()
    }

    private func save() {
        guard isChanged, !security.isPrivacyModeOn else { return dismiss() }
        schoolClass.lastGroups = groups
        do {
            try modelContext.save()
            dismiss()
        } catch {
            toasts.error(loc("Gruppen konnten nicht gesichert werden: \(error.localizedDescription)"))
        }
    }
}

/// Eine Gruppe: Titel und Schüler mit Avatar.
private struct GroupTile: View {
    let number: Int
    let students: [Student]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gruppe \(number)")
                .font(.headline)
                .foregroundStyle(.tint)
            ForEach(students) { student in
                HStack(spacing: 10) {
                    StudentAvatar(student: student, size: 32)
                    Text(student.fullName)
                        .lineLimit(1)
                        .sensitive()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: cardShape)
    }
}

/// PDF der Gruppen (A4 hoch), hell, mit derselben Fußzeile wie der Sitzplan.
enum GroupsPDF {
    static func make(schoolClass: SchoolClass, groups: [[Student]], date: Date) -> URL? {
        let page = CGSize(width: 595, height: 842)
        let subtitle = "\(schoolClass.title) · \(date.appDate)"
        let content = VStack(alignment: .leading, spacing: 16) {
            Text("Gruppen").font(.title.bold())
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 12) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, students in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gruppe \(index + 1)").font(.headline)
                        ForEach(students) { Text($0.fullName).font(.subheadline) }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray.opacity(0.4)))
                }
            }
            Spacer(minLength: 0)
            SeatingPlanPDF.footer
        }
        .padding(36)
        .frame(width: page.width, height: page.height, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)

        let fileName = schoolClass.shortName.replacingOccurrences(of: "/", with: "-")
        let url = URL.temporaryDirectory.appending(path: loc("Gruppen \(fileName).pdf"))
        let renderer = ImageRenderer(content: content)
        var box = CGRect(origin: .zero, size: page)
        renderer.render { _, draw in
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }
}
