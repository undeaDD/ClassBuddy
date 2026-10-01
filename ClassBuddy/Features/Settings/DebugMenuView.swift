#if DEBUG
import SwiftData
import SwiftUI

/// Nur in Debug-Builds: schneller Zugriff auf schwer erreichbare Screens und Zustände
/// sowie Testdaten zum Ausprobieren.
struct DebugMenuView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Query private var classes: [SchoolClass]

    @State private var isLockPreviewPresented = false
    @State private var isPrivacyCoverPresented = false

    private var hasDummyData: Bool {
        classes.contains { DummyData.classIDs.contains($0.id) }
    }

    var body: some View {
        Form {
            Section {
                DebugActionRow(title: loc("Testdaten einfügen"), icon: .plus) {
                    insertDummyData()
                }
                .disabled(hasDummyData)
                DebugActionRow(title: loc("Testdaten entfernen"), icon: .trash) {
                    removeDummyData()
                }
                .disabled(!hasDummyData)
            } header: {
                Text("Testdaten")
            } footer: {
                Text("""
                    4 Klassen mit Schülern, ein Stundenplan (wöchentlich und einmalig) und Termine in der aktuellen Woche. \
                    Nur einmal einfügbar – erst nach dem Entfernen (oder „Alle lokalen Daten löschen“) wieder.
                    """)
            }

            Section("Sperre & Privatsphäre") {
                DebugActionRow(title: loc("App jetzt sperren"), icon: .lock) {
                    guard security.isAppLockEnabled else {
                        toasts.error(loc("App-Sperre ist in den App-Einstellungen ausgeschaltet."))
                        return
                    }
                    security.lock()
                }
                DebugActionRow(title: loc("Sperrbildschirm mit Fehlermeldung"), icon: .fingerprintLockCircle) {
                    isLockPreviewPresented = true
                }
                DebugActionRow(title: loc("Privatsphäre-Abdeckung"), icon: .eyeClosed) {
                    isPrivacyCoverPresented = true
                }
            }

            Section("Leerzustände") {
                NavigationLink {
                    EmptyStateView(
                        title: loc("Keine Klasse ausgewählt"),
                        message: loc("Legen Sie oben links Ihre erste Klasse an."),
                        symbol: .custom(.userXmark)
                    )
                } label: {
                    Label("Keine Klasse ausgewählt", icon: .userXmark)
                }
                NavigationLink {
                    EmptyStateView(
                        title: loc("Noch keine Schüler"),
                        message: loc("Fügen Sie über + oben rechts die Schülerinnen und Schüler der Klasse 7b hinzu."),
                        symbol: AppTab.students.symbol
                    )
                } label: {
                    Label("Noch keine Schüler", symbol: AppTab.students.symbol)
                }
                NavigationLink {
                    EmptyStateView(
                        title: AppTab.rooms.title,
                        message: loc("Hier verwalten Sie bald Ihre Räume und deren Sitzordnungen."),
                        symbol: AppTab.rooms.symbol
                    )
                } label: {
                    Label("Räume (Platzhalter)", symbol: AppTab.rooms.symbol)
                }
                NavigationLink {
                    SearchEmptyStateView(text: "Xylophon")
                } label: {
                    Label("Suche ohne Treffer", icon: .search)
                }
            }

            Section("Toasts") {
                DebugActionRow(title: loc("Erfolg"), icon: .toastSuccess) { toasts.success(loc("Export gespeichert")) }
                DebugActionRow(title: loc("Hinweis"), icon: .toastWarning) { toasts.info(loc("Keine Änderungen gefunden")) }
                DebugActionRow(title: loc("Fehler"), icon: .toastError) { toasts.error(loc("Import fehlgeschlagen: Datei beschädigt")) }
            }
        }
        .navigationTitle("Debug-Menü")
        .fullScreenCover(isPresented: $isLockPreviewPresented) {
            LockScreenView(previewError: loc("Authentifizierung fehlgeschlagen."))
                .overlay(alignment: .topTrailing) {
                    closeButton { isLockPreviewPresented = false }
                }
        }
        .fullScreenCover(isPresented: $isPrivacyCoverPresented) {
            PrivacyCoverView()
                .overlay(alignment: .topTrailing) {
                    closeButton { isPrivacyCoverPresented = false }
                }
        }
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Schließen", icon: .xmark)
                .labelStyle(.iconOnly)
                .padding(6)
        }
        .buttonStyle(.glass)
        .padding()
    }

    private func insertDummyData() {
        guard !hasDummyData else { return }
        let firstClass = DummyData.insert(into: modelContext, slotCount: settings.slots.count)
        do {
            try modelContext.save()
            app.selectedClassID = firstClass.id
            toasts.success(loc("Testdaten eingefügt"))
        } catch {
            toasts.error(loc("Testdaten fehlgeschlagen: \(error.localizedDescription)"))
        }
    }

    private func removeDummyData() {
        DummyData.remove(from: modelContext, classes: classes)
        do {
            try modelContext.save()
            if let selected = app.selectedClassID, DummyData.classIDs.contains(selected) {
                app.selectedClassID = nil
            }
            toasts.success(loc("Testdaten entfernt"))
        } catch {
            toasts.error(loc("Entfernen fehlgeschlagen: \(error.localizedDescription)"))
        }
    }
}

/// Aktionszeile: Text in Textfarbe (auch bei Löschen), nur das Icon in der Akzentfarbe.
private struct DebugActionRow: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let icon: AppIcon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title).foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            } icon: {
                Image(icon: icon)
            }
        }
    }
}

/// Automatische README-Screenshots (`scripts/screenshots.sh`): Start mit `-screenshots`
/// fügt die Testdaten ein, wählt die erste Testklasse und öffnet den Tab aus `-tab <name>`.
/// (Das Erscheinungsbild setzt das Skript direkt per `-app.appearance light|dark`.)
enum ScreenshotMode {
    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains("-screenshots") }

    static func prepare(app: AppModel, context: ModelContext, settings: SchoolSettings) {
        guard isActive else { return }
        let classes = (try? context.fetch(FetchDescriptor<SchoolClass>())) ?? []
        let firstClass = classes.first { $0.id == DummyData.classIDs.first }
            ?? DummyData.insert(into: context, slotCount: settings.slots.count)
        try? context.save()
        app.selectedClassID = firstClass.id
        if let name = UserDefaults.standard.string(forKey: "tab"), let tab = AppTab(rawValue: name) {
            app.selectedTab = tab
        }
    }
}

/// Testdaten mit festen IDs: So lässt sich erkennen, ob sie schon eingefügt wurden,
/// und sie lassen sich gezielt wieder entfernen (Schüler und Stunden hängen per Cascade an der Klasse).
enum DummyData {
    private struct ClassSpec {
        let shortName: String
        let subjects: [String]
        let color: ClassColor
        let age: Int
        let studentCount: Int
    }

    private static let specs = [
        ClassSpec(shortName: "5a", subjects: ["Deutsch", "Englisch"], color: .blue, age: 10, studentCount: 12),
        ClassSpec(shortName: "7b", subjects: ["Mathematik"], color: .green, age: 12, studentCount: 10),
        ClassSpec(shortName: "9c", subjects: ["Biologie", "Chemie"], color: .orange, age: 14, studentCount: 9),
        ClassSpec(shortName: "Q1", subjects: ["Informatik"], color: .purple, age: 16, studentCount: 8),
    ]

    static let classIDs: [UUID] = (1...specs.count).map { fixedID(prefix: "DDDD0000", $0) }
    private static let entryIDs: [UUID] = (1...5).map { fixedID(prefix: "DDDD1111", $0) }

    private static func fixedID(prefix: String, _ number: Int) -> UUID {
        UUID(uuidString: String(format: "%@-0000-0000-0000-%012d", prefix, number)) ?? UUID()
    }

    private static let femaleNames = ["Emma", "Mia", "Hannah", "Sofia", "Lina", "Lea", "Marie", "Clara", "Ella", "Johanna", "Frieda", "Ida"]
    private static let maleNames = ["Noah", "Ben", "Paul", "Leon", "Finn", "Elias", "Felix", "Jonas", "Luis", "Henry", "Emil", "Theo"]
    private static let lastNames = [
        "Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker",
        "Schulz", "Hoffmann", "Koch", "Richter", "Klein", "Wolf", "Neumann", "Schröder",
    ]

    /// Fügt alles ein und gibt die erste Klasse zurück (zum direkten Auswählen).
    @discardableResult
    static func insert(into context: ModelContext, slotCount: Int) -> SchoolClass {
        let calendar = Calendar.school
        let classes = zip(specs, classIDs).map { spec, id in
            SchoolClass(id: id, shortName: spec.shortName, subjects: spec.subjects, color: spec.color)
        }
        classes.forEach(context.insert)

        for (index, (spec, schoolClass)) in zip(specs, classes).enumerated() {
            insertStudents(spec: spec, classIndex: index, into: schoolClass, context: context)
        }
        insertLessons(for: classes, slotCount: slotCount, calendar: calendar, context: context)
        insertEntries(calendar: calendar, classes: classes, context: context)
        return classes[0]
    }

    private static func insertStudents(spec: ClassSpec, classIndex: Int, into schoolClass: SchoolClass, context: ModelContext) {
        let calendar = Calendar.school
        for number in 0..<spec.studentCount {
            let isFemale = number.isMultiple(of: 2)
            let names = isFemale ? femaleNames : maleNames
            let firstName = names[(number / 2 + classIndex * 3) % names.count]
            let lastName = lastNames[(number * 5 + classIndex * 7) % lastNames.count]
            // Ein Geburtstag pro Klasse liegt in den nächsten Tagen (Kachel „Nächster Geburtstag“).
            let daysFromNow = number == 0 ? classIndex + 2 : (number * 37 + classIndex * 11) % 365
            let birthdayThisYear = calendar.date(byAdding: .day, value: daysFromNow, to: calendar.startOfDay(for: .now)) ?? .now
            let birthday = calendar.date(byAdding: .year, value: -(spec.age + number % 2), to: birthdayThisYear)
            let gender: Gender? = number == spec.studentCount - 1 ? nil : (number % 7 == 5 ? .diverse : (isFemale ? .female : .male))
            let student = Student(
                firstName: firstName,
                lastName: lastName,
                birthday: birthday,
                gender: gender,
                notes: number % 4 == 1 ? "Sitzt gern vorne." : "",
                schoolClass: schoolClass
            )
            context.insert(student)
        }
    }

    /// Wöchentlicher Stundenplan Mo–Fr plus drei einmalige Stunden in freien Slots dieser Woche.
    private static func insertLessons(for classes: [SchoolClass], slotCount: Int, calendar: Calendar, context: ModelContext) {
        let slots = min(slotCount, 6)
        guard slots > 0 else { return }
        var free: [(weekday: Int, slot: Int)] = []

        for weekday in 0..<5 {
            for slot in 0..<slots {
                // Muster mit Freistunden: jede 5. Kombination bleibt leer.
                let pick = (weekday * 3 + slot) % (classes.count + 1)
                guard pick < classes.count else {
                    free.append((weekday, slot))
                    continue
                }
                let schoolClass = classes[pick]
                let subjects = schoolClass.subjects
                let lesson = Lesson(
                    weekday: weekday,
                    slotIndex: slot,
                    subject: subjects[(weekday + slot) % subjects.count],
                    isRecurring: true,
                    date: nil,
                    schoolClass: schoolClass
                )
                context.insert(lesson)
            }
        }

        let weekStart = calendar.startOfWeek(for: .now)
        for (index, spot) in free.prefix(3).enumerated() {
            let schoolClass = classes[index % classes.count]
            let day = calendar.date(byAdding: .day, value: spot.weekday, to: weekStart) ?? weekStart
            let lesson = Lesson(
                weekday: spot.weekday,
                slotIndex: spot.slot,
                subject: schoolClass.subjects[0],
                isRecurring: false,
                date: calendar.startOfDay(for: day),
                schoolClass: schoolClass
            )
            context.insert(lesson)
        }
    }

    private struct EntrySpec {
        let title: String
        let weekday: Int
        let hour: Int
        let minute: Int
        let minutes: Int
        let notes: String
        /// Index in `specs` (nil = Termin ohne Klasse).
        var classIndex: Int?
    }

    private static func insertEntries(calendar: Calendar, classes: [SchoolClass], context: ModelContext) {
        let weekStart = calendar.startOfWeek(for: .now)
        let entries = [
            EntrySpec(title: "Fachkonferenz Mathematik", weekday: 0, hour: 15, minute: 0, minutes: 90, notes: "Raum 204"),
            EntrySpec(title: "Lehrerkonferenz", weekday: 2, hour: 14, minute: 30, minutes: 90, notes: ""),
            EntrySpec(
                title: "Elterngespräch Fam. Müller", weekday: 3, hour: 13, minute: 15, minutes: 30,
                notes: "Leistungsstand", classIndex: 1
            ),
            // Mit Klasse außerhalb der Schulzeit bzw. mitten im Schultag.
            EntrySpec(title: "Elternabend", weekday: 1, hour: 18, minute: 0, minutes: 90, notes: "Aula", classIndex: 0),
            EntrySpec(title: "Museumsbesuch", weekday: 4, hour: 9, minute: 0, minutes: 180, notes: "", classIndex: 2),
        ]
        for (entry, id) in zip(entries, entryIDs) {
            let day = calendar.date(byAdding: .day, value: entry.weekday, to: weekStart) ?? weekStart
            let start = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: day) ?? day
            let end = start.addingTimeInterval(TimeInterval(entry.minutes * 60))
            let schoolClass = entry.classIndex.map { classes[$0] }
            context.insert(CalendarEntry(id: id, title: entry.title, start: start, end: end, notes: entry.notes, schoolClass: schoolClass))
        }
    }

    static func remove(from context: ModelContext, classes: [SchoolClass]) {
        for schoolClass in classes where classIDs.contains(schoolClass.id) {
            context.delete(schoolClass)
        }
        let ids = entryIDs
        try? context.delete(model: CalendarEntry.self, where: #Predicate { ids.contains($0.id) })
    }
}
#endif
