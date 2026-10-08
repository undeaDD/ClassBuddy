import SwiftData
import SwiftUI

/// Sitzplan einer Klasse in einem Raum (geöffnet aus Kalender oder Übersicht).
struct SeatingPlanRoute: Identifiable {
    let id = UUID()
    let room: Room
    let schoolClass: SchoolClass?
    /// Fach der Stunde: Antippen eines Schülers führt dann direkt zu seinen Notizen in diesem Fach.
    var subject: String?
}

/// Sitzplan: freien Tisch antippen → Schüler wählen (iPhone: Sheet, iPad: Seitenleiste wie in Mail).
/// Auf dem iPad lassen sich Schüler auch aus der Seitenleiste auf einen Tisch ziehen.
/// Schüler auf einem Tisch: Antippen → Schnell-Leiste (Bewertung, Fehlzeit, Notiz; ohne Fächer: Akte),
/// langes Drücken → Bearbeiten / Platz freigeben, gedrückt ziehen → anderer Tisch.
/// Gestrichelte Tische: seit mindestens drei Stunden des Fachs ohne Beobachtung; abwesende Schüler sind abgeblendet.
/// Die Lehrkraft sitzt (nur zur Anzeige) am Lehrerpult.
struct SeatingPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.device) private var device
    @Environment(AppSecurity.self) private var security
    @Environment(ToastCenter.self) private var toasts
    @Environment(SchoolSettings.self) private var settings
    @Query private var lessons: [Lesson]
    @Query private var holidays: [Holiday]
    let route: SeatingPlanRoute

    /// `nil` (Termin ohne Klasse): leerer Sitzplan nur mit Grundriss, z. B. zum Drucken.
    @State private var schoolClass: SchoolClass?
    @State private var selectedTable: UUID?
    @State private var searchText = ""
    @State private var pendingAction: BulkAction?
    @State private var pdfPreview: URL?
    @State private var notesStudent: Student?
    /// Schüler in der Schnell-Leiste.
    @State private var quickStudent: Student?
    @State private var studentEditorRoute: StudentEditorRoute?
    @State private var roomEditorRoute: RoomEditorRoute?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private enum BulkAction {
        case shuffle, clearAll
    }

    init(route: SeatingPlanRoute) {
        self.route = route
        _schoolClass = State(initialValue: route.schoolClass)
        // Haben schon alle einen Platz, startet der Sitzplan ohne Seitenleiste.
        let everyoneSeated = route.schoolClass.map {
            SeatingPlan.occupants(in: route.room, schoolClass: $0).count >= $0.students.count
        } ?? true
        _columnVisibility = State(initialValue: everyoneSeated ? .detailOnly : .all)
    }

    private var room: Room { route.room }

    /// Im Privatsphäre-Modus nur lesend.
    private var isEditable: Bool { !security.isPrivacyModeOn && schoolClass != nil }

    private var teacher: TeacherProfile { settings.values.teacher }

    private var hasNoTables: Bool { SeatingPlan.tables(in: room).isEmpty }

    private var subtitle: String {
        [room.name, schoolClass?.title ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Alle Schüler der Klasse haben einen Platz → Seitenleiste ausblenden, iPhone-Liste nicht öffnen.
    private var everyoneSeated: Bool {
        guard let schoolClass else { return true }
        return occupants.count >= schoolClass.students.count
    }

    private var occupants: [UUID: Student] {
        schoolClass.map { SeatingPlan.occupants(in: room, schoolClass: $0) } ?? [:]
    }

    private var schedule: LessonSchedule {
        LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots)
    }

    private var lessonContext: LessonContext? {
        schoolClass.flatMap { SeatingPlanRecords.lessonContext(for: $0, schedule: schedule, preferred: [route.subject]) }
    }

    private var unobservedTables: Set<UUID> {
        guard let schoolClass, let lessonContext else { return [] }
        return SeatingPlanRecords.unobservedTables(occupants: occupants, classID: schoolClass.id, lesson: lessonContext, schedule: schedule)
    }

    private var absentTables: Set<UUID> {
        lessonContext.map { SeatingPlanRecords.absentTables(occupants: occupants, lesson: $0) } ?? []
    }

    /// Schüler ohne Platz in diesem Raum, nach Vornamen sortiert und gefiltert.
    private var unseatedStudents: [Student] {
        guard let schoolClass else { return [] }
        let seated = Set(occupants.values.map(\.id))
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return schoolClass.students
            .filter { !seated.contains($0.id) && (query.isEmpty || $0.fullName.localizedStandardContains(query)) }
            .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
    }

    var body: some View {
        Group {
            // Ohne Klasse gibt es nichts zuzuordnen → keine Seitenleiste.
            if device.isPad, schoolClass != nil {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    studentList
                        .navigationTitle(schoolClass?.title ?? loc("Schüler"))
                        .navigationBarTitleDisplayMode(.inline)
                } detail: {
                    NavigationStack { plan }
                }
            } else {
                NavigationStack { plan }
                    .sheet(isPresented: phoneSheetBinding) {
                        NavigationStack {
                            studentList
                                .navigationTitle("Schüler wählen")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Schließen", icon: .xmark, role: .appClose) { selectedTable = nil }
                                            .toolbarGroupBackground()
                                    }
                                }
                        }
                        .presentationDetents([.medium, .large])
                    }
            }
        }
        .confirmationDialog(
            pendingAction == .shuffle ? "Zufällig verteilen?" : "Alle Plätze freigeben?",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            switch action {
            case .shuffle: Button("Zufällig verteilen", role: .destructive, action: shuffle)
            case .clearAll: Button("Alle Plätze freigeben", role: .destructive, action: clearAll)
            }
        } message: { action in
            switch action {
            case .shuffle: Text("Alle Schüler der Klasse bekommen neue, zufällige Plätze.")
            case .clearAll: Text("Alle Schüler der Klasse verlieren ihren Platz in diesem Raum.")
            }
        }
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                quickStudent = nil
                selectedTable = nil
                pendingAction = nil
                studentEditorRoute = nil
                roomEditorRoute = nil
            }
        }
        .onChange(of: schoolClass?.id) { selectedTable = nil }
        .onChange(of: everyoneSeated) { _, isEmpty in
            withAnimation { columnVisibility = isEmpty ? .detailOnly : .all }
        }
        .quickLookPreview($pdfPreview)
        .fullScreenCover(item: $studentEditorRoute) { route in
            StudentEditorView(route: route)
                .softScrollEdges()
        }
        .fullScreenCover(item: $roomEditorRoute) { route in
            RoomEditorView(route: route, nextSortIndex: room.sortIndex)
                .softScrollEdges()
        }
    }

    // MARK: Grundriss

    private var plan: some View {
        content
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sitzplan")
            .appNavigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(item: $notesStudent) { student in
                if let subject = lessonContext?.subject, student.schoolClass?.subjects.contains(subject) ?? false {
                    StudentRecordView(student: student, subject: subject)
                } else {
                    StudentSubjectsView(student: student)
                }
            }
    }

    private var content: some View {
        SeatingPlanCanvas(
            shapes: room.shapes,
            occupants: occupants,
            teacher: teacher,
            selected: selectedTable,
            dashed: unobservedTables,
            dimmed: absentTables,
            isEditable: isEditable,
            onTap: { tap($0) },
            actions: SeatActions(
                open: { open($0) },
                edit: { studentEditorRoute = .edit($0) },
                clear: { clear($0) }
            ),
            onDrop: { drop(studentID: $0, on: $1) }
        )
        .overlay(alignment: .bottom) {
            if hasNoTables {
                hint("Dieser Raum hat noch keine Tische. Zeichnen Sie sie im Raum-Editor.")
            } else if let quickStudent, let lessonContext {
                QuickRatingBar(
                    student: quickStudent,
                    lesson: lessonContext,
                    onOpenRecord: {
                        notesStudent = quickStudent
                        self.quickStudent = nil
                    },
                    onClose: { withAnimation(.smooth) { self.quickStudent = nil } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topLeading) {
            if !unobservedTables.isEmpty {
                UnobservedLegend()
            }
        }
        .animation(.smooth, value: quickStudent?.id)
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            .padding()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Schließen", icon: .xmark, role: .appClose) { dismiss() }
                .toolbarGroupBackground()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Sitzplan") {
                    // Vorschau (Quick Look): dort sichern, drucken oder teilen.
                    Button("Als PDF exportieren", icon: .page) {
                        pdfPreview = SeatingPlanPDF.make(room: room, subtitle: subtitle, occupants: occupants, teacher: teacher)
                    }
                    Button("Raum bearbeiten", icon: .editPencil) { roomEditorRoute = .edit(room) }
                }
                Section("Plätze ändern") {
                    Button("Zufällig verteilen", destructiveIcon: .shuffle) { pendingAction = .shuffle }
                        .disabled(!isEditable || hasNoTables || (schoolClass?.students.isEmpty ?? true))
                    Button("Alle Plätze freigeben", destructiveIcon: .userXmark) { pendingAction = .clearAll }
                        .disabled(!isEditable || occupants.isEmpty)
                }
            } label: {
                Label("Mehr", icon: .moreHoriz)
            }
            // Im Privatsphäre-Modus weder teilen noch ändern.
            .disabled(security.isPrivacyModeOn)
            .toolbarGroupBackground()
        }
        AppToolbarSpacer(placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            PrivacyModeButton()
                .toolbarGroupBackground()
        }
    }

    // MARK: Schülerliste

    private var phoneSheetBinding: Binding<Bool> {
        Binding(get: { selectedTable != nil }, set: { if !$0 { selectedTable = nil } })
    }

    private var studentList: some View {
        let students = unseatedStudents
        return List {
            if device.isPad, isEditable {
                Section {
                    Text(selectedTable == nil
                        ? "Tippen Sie auf einen freien Tisch und dann auf einen Schüler – oder ziehen Sie einen Schüler auf einen Tisch."
                        : "Wählen Sie einen Schüler für den markierten Tisch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(students) { student in
                studentRow(student)
            }
        }
        // Auch in der iPad-Seitenleiste gruppiert: Zeilenhintergrund passt zum Geschlechts-Kreis.
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Schüler suchen")
        .overlay {
            if students.isEmpty {
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchEmptyStateView(text: searchText)
                } else if schoolClass?.students.isEmpty ?? true {
                    EmptyStateView(
                        title: loc("Noch keine Schüler"),
                        message: loc("Diese Klasse hat noch keine Schülerinnen und Schüler."),
                        symbol: AppTab.students.symbol
                    )
                } else {
                    EmptyStateView(
                        title: loc("Alle haben einen Platz"),
                        message: loc("Über langes Drücken auf einen Schüler geben Sie seinen Platz wieder frei."),
                        symbol: AppTab.students.symbol
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func studentRow(_ student: Student) -> some View {
        let row = Button {
            pick(student)
        } label: {
            HStack(spacing: 12) {
                StudentAvatar(student: student, size: 40)
                Text(student.fullName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .sensitive()
                Spacer()
            }
            .contentShape(.rect)
        }
        .disabled(!isEditable)
        if device.isPad, isEditable {
            row.draggable(student.id.uuidString) {
                StudentAvatar(student: student, size: 48)
            }
        } else {
            row
        }
    }
}

// MARK: Aktionen

extension SeatingPlanView {

    /// Schüler antippen: mit Fächern die Schnell-Leiste, sonst die Fächer bzw. Akte.
    private func open(_ student: Student) {
        guard lessonContext != nil else {
            notesStudent = student
            return
        }
        Haptics.selection()
        quickStudent = student
    }

    /// Freier Tisch → markieren (iPhone: Liste öffnet sich); besetzter Tisch oder daneben → Markierung weg.
    private func tap(_ table: UUID?) {
        // Freier Tisch oder daneben: Schnell-Leiste zuerst schließen (sonst liegt die Schülerliste darüber).
        quickStudent = nil
        guard let table, occupants[table] == nil, table != selectedTable, !everyoneSeated else {
            selectedTable = nil
            return
        }
        searchText = ""
        selectedTable = table
        Haptics.selection()
    }

    private func pick(_ student: Student) {
        guard let selectedTable else { return }
        assign(student, to: selectedTable)
    }

    /// Aus der Seitenleiste oder von einem anderen Tisch; besetztes Ziel → Plätze tauschen bzw. ersetzen.
    private func drop(studentID: UUID, on table: UUID) {
        guard let student = schoolClass?.students.first(where: { $0.id == studentID }) else { return }
        assign(student, to: table)
    }

    private func assign(_ student: Student, to tableID: UUID) {
        guard let table = room.elements.first(where: { $0.id == tableID }) else { return }
        SeatingPlan.move(student, to: table, in: modelContext)
        selectedTable = nil
        save()
        Haptics.selection()
    }

    private func clear(_ tableID: UUID) {
        guard let schoolClass, let table = room.elements.first(where: { $0.id == tableID }) else { return }
        SeatingPlan.clear(table, schoolClass: schoolClass, in: modelContext)
        save()
    }

    private func shuffle() {
        guard let schoolClass else { return }
        selectedTable = nil
        let unseated = SeatingPlan.shuffle(in: room, schoolClass: schoolClass, in: modelContext)
        guard save() else { return }
        if unseated > 0 {
            toasts.info(loc("\(unseated) Schüler ohne Platz – es gibt nicht genug Tische."))
        } else {
            toasts.success(loc("Plätze zufällig verteilt"))
        }
    }

    private func clearAll() {
        guard let schoolClass else { return }
        selectedTable = nil
        SeatingPlan.clearAll(in: room, schoolClass: schoolClass, in: modelContext)
        if save() { toasts.success(loc("Alle Plätze freigegeben")) }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            toasts.error(loc("Speichern fehlgeschlagen: \(error.localizedDescription)"))
            return false
        }
    }
}

/// PDF des Grundrisses mit Sitzplan (A4 quer), immer im hellen Erscheinungsbild. Raumfläche ohne Füllung
/// (spart Tinte); unten eine Fußzeile mit App-Icon, Name und Version, damit Empfänger die App finden.
enum SeatingPlanPDF {
    static func make(room: Room, subtitle: String, occupants: [UUID: Student], teacher: TeacherProfile? = nil) -> URL? {
        let page = CGSize(width: 842, height: 595)
        let content = VStack(alignment: .leading, spacing: 12) {
            Text("Sitzplan").font(.title.bold())
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
            SeatingPlanFloor(
                shapes: room.shapes, occupants: occupants, teacher: teacher, padding: 8, background: .white, fillsOutline: false
            )
            footer
        }
        .padding(36)
        .frame(width: page.width, height: page.height, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)

        let fileName = subtitle.replacingOccurrences(of: "/", with: "-")
        let url = URL.temporaryDirectory.appending(path: loc("Sitzplan \(fileName).pdf"))
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

    static var footer: some View {
        HStack(spacing: 8) {
            Image(.appIconPreview)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text("ClassBuddy \(AppInfo.shortVersion)")
                .fontWeight(.semibold)
            Text(AppInfo.shareURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
            Spacer()
            Text("Mit ❤️ gemacht von Devsforge.de")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}
