import Foundation
import SwiftData

/// Export/Import aller App-Daten als Excel-Arbeitsmappe (ein Blatt je Bereich).
///
/// Import = Wiederherstellen: Datenblätter (Klassen, Schüler, Stunden, Termine,
/// Kacheln, Ferien) ersetzen die vorhandenen Daten komplett; Einstellungsblätter
/// werden nur übernommen, wenn sie in der Datei vorhanden sind.
/// Dokument-Kacheln enthalten Dateien, die nicht in die Tabelle passen: Sie bleiben
/// erhalten, wenn die Datei auf diesem Gerät noch existiert, sonst werden sie übersprungen.
enum Backup {
    static let formatName = "ClassBuddy-Export"
    static let formatVersion = 1

    enum Sheet {
        static let info = "Info"
        static let classes = "Klassen"
        static let students = "Schüler"
        static let lessons = "Stunden"
        static let entries = "Termine"
        static let links = "Kacheln"
        static let holidays = "Ferien"
        static let school = "Schule"
        static let schoolDay = "Schultag"
        static let breaks = "Pausen"
        static let profile = "Profil"
        static let app = "App"
    }

    struct ImportSummary {
        var classes = 0
        var students = 0
        var lessons = 0
        var entries = 0
        var links = 0
        var holidays = 0
        var skippedDocuments = 0

        var text: String {
            var parts = [
                "\(classes) Klassen", "\(students) Schüler", "\(lessons) Stunden",
                "\(entries) Termine", "\(links) Kacheln", "\(holidays) Ferien/Feiertage",
            ]
            if skippedDocuments > 0 {
                parts.append("\(skippedDocuments) Dokument-Kacheln übersprungen (Datei nicht auf diesem Gerät)")
            }
            return "Importiert: " + parts.joined(separator: ", ") + "."
        }
    }

    enum ImportError: LocalizedError {
        case notAClassBuddyFile

        var errorDescription: String? {
            "Die Datei ist kein ClassBuddy-Export (Blatt „Info“ oder „Klassen“ fehlt)."
        }
    }

    // MARK: Export

    static func export(context: ModelContext, settings: SchoolSettings.Values, appearance: AppAppearance) throws -> Data {
        let classes = try context.fetch(FetchDescriptor<SchoolClass>(sortBy: [SortDescriptor(\.shortName)]))
        let entries = try context.fetch(FetchDescriptor<CalendarEntry>(sortBy: [SortDescriptor(\.start)]))
        let holidays = try context.fetch(FetchDescriptor<Holiday>(sortBy: [SortDescriptor(\.startDate)]))

        var sheets: [XLSXSheet] = []

        sheets.append(XLSXSheet(name: Sheet.info, rows: [
            ["Schlüssel", "Wert"],
            ["Format", formatName],
            ["Formatversion", "\(formatVersion)"],
            ["Exportiert am", Cell.dateTime(.now)],
            ["App-Version", AppInfo.version],
        ]))

        sheets.append(XLSXSheet(name: Sheet.classes, rows: [
            ["ID", "Kürzel", "Fächer", "Schuljahr", "Farbe", "Erstellt", "Kachel-Reihenfolge"],
        ] + classes.map {
            [$0.id.uuidString, $0.shortName, Cell.list($0.subjects), $0.schoolYear, $0.colorRaw,
             Cell.dateTime($0.createdAt), Cell.list($0.dashboardOrder)]
        }))

        sheets.append(XLSXSheet(name: Sheet.students, rows: [
            ["ID", "Klassen-ID", "Klasse", "Vorname", "Nachname", "Geburtstag", "Geschlecht", "Notizen", "Erstellt"],
        ] + classes.flatMap { schoolClass in
            schoolClass.sortedStudents.map {
                [$0.id.uuidString, schoolClass.id.uuidString, schoolClass.shortName, $0.firstName, $0.lastName,
                 Cell.date($0.birthday), $0.gender?.title ?? "", $0.notes, Cell.dateTime($0.createdAt)]
            }
        }))

        sheets.append(XLSXSheet(name: Sheet.lessons, rows: [
            ["ID", "Klassen-ID", "Klasse", "Wochentag", "Stunde", "Fach", "Wöchentlich", "Datum"],
        ] + classes.flatMap { schoolClass in
            schoolClass.lessons
                .sorted { ($0.weekday, $0.slotIndex) < ($1.weekday, $1.slotIndex) }
                .map {
                    [$0.id.uuidString, schoolClass.id.uuidString, schoolClass.shortName, Cell.weekday($0.weekday),
                     "\($0.slotIndex + 1)", $0.subject, Cell.bool($0.isRecurring), Cell.date($0.date)]
                }
        }))

        sheets.append(XLSXSheet(name: Sheet.entries, rows: [
            ["ID", "Titel", "Beginn", "Ende", "Notizen"],
        ] + entries.map {
            [$0.id.uuidString, $0.title, Cell.dateTime($0.start), Cell.dateTime($0.end), $0.notes]
        }))

        sheets.append(XLSXSheet(name: Sheet.links, rows: [
            ["ID", "Klassen-ID", "Klasse", "Typ", "Titel", "Adresse / Datei", "Erstellt"],
        ] + classes.flatMap { schoolClass in
            schoolClass.dashboardLinks.sorted { $0.createdAt < $1.createdAt }.map {
                [$0.id.uuidString, schoolClass.id.uuidString, schoolClass.shortName,
                 $0.kind == .file ? "Dokument" : "Website", $0.title,
                 $0.kind == .file ? $0.detail : $0.location, Cell.dateTime($0.createdAt)]
            }
        }))

        sheets.append(XLSXSheet(name: Sheet.holidays, rows: [
            ["ID", "Name", "Beginn", "Ende", "Schulferien"],
        ] + holidays.map {
            [$0.id, $0.name, Cell.date($0.startDate), Cell.date($0.endDate), Cell.bool($0.isSchoolHoliday)]
        }))

        let school = settings.school
        sheets.append(XLSXSheet(name: Sheet.school, rows: [
            ["Schlüssel", "Wert"],
            ["Name", school.name], ["Website", school.website], ["Straße", school.street],
            ["PLZ", school.postalCode], ["Ort", school.city], ["Telefon", school.phone], ["E-Mail", school.email],
        ]))

        sheets.append(XLSXSheet(name: Sheet.schoolDay, rows: [
            ["Schlüssel", "Wert"],
            ["Beginn", settings.dayStart.clockString],
            ["Ende", settings.dayEnd.clockString],
            ["Stundenlänge (min)", "\(settings.lessonDuration)"],
            ["Wochenende anzeigen", Cell.bool(settings.showWeekends)],
            ["Bundesland", settings.federalState ?? ""],
        ]))

        sheets.append(XLSXSheet(name: Sheet.breaks, rows: [
            ["Beginn", "Dauer (min)"],
        ] + settings.breaks.sorted { $0.start < $1.start }.map { [$0.start.clockString, "\($0.duration)"] }))

        let teacher = settings.teacher
        sheets.append(XLSXSheet(name: Sheet.profile, rows: [
            ["Schlüssel", "Wert"],
            ["Vorname", teacher.firstName], ["Nachname", teacher.lastName],
            ["Geburtstag", Cell.date(teacher.birthday)], ["Geschlecht", teacher.gender?.title ?? ""],
        ]))

        sheets.append(XLSXSheet(name: Sheet.app, rows: [
            ["Schlüssel", "Wert"],
            ["Erscheinungsbild", appearance.title],
        ]))

        return XLSX.write(sheets)
    }

    // MARK: Import

    struct ImportedSettings {
        var values: SchoolSettings.Values
        var appearance: AppAppearance?
    }

    /// Ersetzt die App-Daten durch den Inhalt der Datei.
    /// Gibt die übernommenen Einstellungen zurück (Aufrufer setzt sie).
    static func `import`(
        _ data: Data,
        context: ModelContext,
        currentSettings: SchoolSettings.Values
    ) throws -> (summary: ImportSummary, settings: ImportedSettings) {
        let workbook = try XLSX.read(data)
        guard workbook[Sheet.info] != nil || workbook[Sheet.classes] != nil else { throw ImportError.notAClassBuddyFile }

        func table(_ name: String) -> Table? { workbook[name].map(Table.init) }
        var summary = ImportSummary()

        // Vorhandene Dokument-Kacheln merken: ihre Dateien bleiben, wenn die ID im Import vorkommt.
        let existingFiles = try context.fetch(FetchDescriptor<DashboardLink>())
            .filter { $0.kind == .file }
            .reduce(into: [UUID: String]()) { $0[$1.id] = $1.location }

        try context.delete(model: Student.self)
        try context.delete(model: Lesson.self)
        try context.delete(model: DashboardLink.self)
        try context.delete(model: CalendarEntry.self)
        try context.delete(model: Holiday.self)
        try context.delete(model: SchoolClass.self)

        // Klassen
        var classesByID: [UUID: SchoolClass] = [:]
        for row in table(Sheet.classes)?.rows ?? [] {
            guard let shortName = row["Kürzel"].nonEmpty else { continue }
            let schoolClass = SchoolClass(
                id: UUID(uuidString: row["ID"]) ?? UUID(),
                shortName: shortName,
                subjects: Cell.parseList(row["Fächer"]),
                schoolYear: row["Schuljahr"],
                color: ClassColor(rawValue: row["Farbe"]) ?? .blue,
                createdAt: Cell.parseDateTime(row["Erstellt"]) ?? .now
            )
            schoolClass.dashboardOrder = Cell.parseList(row["Kachel-Reihenfolge"])
            context.insert(schoolClass)
            classesByID[schoolClass.id] = schoolClass
            summary.classes += 1
        }

        // Schüler
        for row in table(Sheet.students)?.rows ?? [] {
            guard let schoolClass = UUID(uuidString: row["Klassen-ID"]).flatMap({ classesByID[$0] }),
                  !(row["Vorname"].isEmpty && row["Nachname"].isEmpty)
            else { continue }
            context.insert(Student(
                id: UUID(uuidString: row["ID"]) ?? UUID(),
                firstName: row["Vorname"],
                lastName: row["Nachname"],
                birthday: Cell.parseDate(row["Geburtstag"]),
                gender: Cell.parseGender(row["Geschlecht"]),
                notes: row["Notizen"],
                createdAt: Cell.parseDateTime(row["Erstellt"]) ?? .now,
                schoolClass: schoolClass
            ))
            summary.students += 1
        }

        // Stunden
        for row in table(Sheet.lessons)?.rows ?? [] {
            guard let schoolClass = UUID(uuidString: row["Klassen-ID"]).flatMap({ classesByID[$0] }),
                  let weekday = Cell.parseWeekday(row["Wochentag"]),
                  let number = Int(row["Stunde"]), number >= 1
            else { continue }
            let isRecurring = Cell.parseBool(row["Wöchentlich"]) ?? true
            let date = Cell.parseDate(row["Datum"])
            guard isRecurring || date != nil else { continue }
            context.insert(Lesson(
                id: UUID(uuidString: row["ID"]) ?? UUID(),
                weekday: weekday,
                slotIndex: number - 1,
                subject: row["Fach"],
                isRecurring: isRecurring,
                date: isRecurring ? nil : date,
                schoolClass: schoolClass
            ))
            summary.lessons += 1
        }

        // Termine
        for row in table(Sheet.entries)?.rows ?? [] {
            guard let start = Cell.parseDateTime(row["Beginn"]) else { continue }
            let end = Cell.parseDateTime(row["Ende"]).map { max($0, start) } ?? start.addingTimeInterval(3600)
            context.insert(CalendarEntry(
                id: UUID(uuidString: row["ID"]) ?? UUID(),
                title: row["Titel"], start: start, end: end, notes: row["Notizen"]
            ))
            summary.entries += 1
        }

        // Kacheln
        var keptFileLocations: Set<String> = []
        for row in table(Sheet.links)?.rows ?? [] {
            guard let schoolClass = UUID(uuidString: row["Klassen-ID"]).flatMap({ classesByID[$0] }) else { continue }
            let id = UUID(uuidString: row["ID"]) ?? UUID()
            if row["Typ"].lowercased().hasPrefix("dok") {
                guard let location = existingFiles[id],
                      FileManager.default.fileExists(atPath: LinkFileStore.directory.appending(path: location).path())
                else {
                    summary.skippedDocuments += 1
                    continue
                }
                keptFileLocations.insert(location)
                context.insert(DashboardLink(id: id, title: row["Titel"], kind: .file, location: location, schoolClass: schoolClass))
            } else {
                guard let url = URL.web(row["Adresse / Datei"]) else { continue }
                context.insert(DashboardLink(id: id, title: row["Titel"], kind: .website, location: url.absoluteString, schoolClass: schoolClass))
            }
            summary.links += 1
        }

        // Ferien
        for row in table(Sheet.holidays)?.rows ?? [] {
            guard let start = Cell.parseDate(row["Beginn"]) else { continue }
            context.insert(Holiday(
                id: row["ID"].nonEmpty ?? UUID().uuidString,
                name: row["Name"],
                startDate: start,
                endDate: Cell.parseDate(row["Ende"]) ?? start,
                isSchoolHoliday: Cell.parseBool(row["Schulferien"]) ?? true
            ))
            summary.holidays += 1
        }

        try context.save()
        removeUnreferencedFiles(keeping: keptFileLocations)

        return (summary, importedSettings(from: workbook, current: currentSettings))
    }

    private static func importedSettings(from workbook: [String: [[String]]], current: SchoolSettings.Values) -> ImportedSettings {
        var values = current

        if let school = workbook[Sheet.school].map(KeyValues.init) {
            values.school = SchoolInfo(
                name: school["Name"], website: school["Website"], street: school["Straße"],
                postalCode: school["PLZ"], city: school["Ort"], phone: school["Telefon"], email: school["E-Mail"]
            )
        }
        if let day = workbook[Sheet.schoolDay].map(KeyValues.init) {
            values.dayStart = Cell.parseTime(day["Beginn"]) ?? values.dayStart
            values.dayEnd = Cell.parseTime(day["Ende"]) ?? values.dayEnd
            values.lessonDuration = Int(day["Stundenlänge (min)"]) ?? values.lessonDuration
            values.showWeekends = Cell.parseBool(day["Wochenende anzeigen"]) ?? values.showWeekends
            values.federalState = day["Bundesland"].nonEmpty
        }
        if let breaks = workbook[Sheet.breaks].map(Table.init) {
            values.breaks = breaks.rows.compactMap { row in
                guard let start = Cell.parseTime(row["Beginn"]), let duration = Int(row["Dauer (min)"]) else { return nil }
                return BreakTime(start: start, duration: duration)
            }
        }
        if let profile = workbook[Sheet.profile].map(KeyValues.init) {
            values.teacher = TeacherProfile(
                firstName: profile["Vorname"], lastName: profile["Nachname"],
                birthday: Cell.parseDate(profile["Geburtstag"]), gender: Cell.parseGender(profile["Geschlecht"])
            )
        }
        let appearance = workbook[Sheet.app].map(KeyValues.init).flatMap { app in
            AppAppearance.allCases.first { $0.title == app["Erscheinungsbild"] }
        }
        return ImportedSettings(values: values, appearance: appearance)
    }

    /// Kopierte Dokumente, die nach dem Import keiner Kachel mehr gehören, entfernen.
    private static func removeUnreferencedFiles(keeping locations: Set<String>) {
        let keptFolders = Set(locations.map { ($0 as NSString).deletingLastPathComponent })
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: LinkFileStore.directory.path())) ?? []
        for folder in folders where !keptFolders.contains(folder) {
            try? FileManager.default.removeItem(at: LinkFileStore.directory.appending(path: folder))
        }
    }
}

// MARK: - Tabellen-Hilfen

/// Tabelle mit Kopfzeile: Zugriff auf Zellen per Spaltenname.
private struct Table {
    struct Row {
        let values: [String: String]
        subscript(column: String) -> String {
            values[column]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    let rows: [Row]

    init(_ raw: [[String]]) {
        guard let header = raw.first else { rows = []; return }
        let names = header.map { $0.trimmingCharacters(in: .whitespaces) }
        rows = raw.dropFirst()
            .filter { $0.contains { !$0.isEmpty } }
            .map { cells in
                Row(values: Dictionary(
                    zip(names, cells).filter { !$0.0.isEmpty }.map { ($0.0, $0.1) },
                    uniquingKeysWith: { first, _ in first }
                ))
            }
    }
}

/// Zweispaltige Schlüssel/Wert-Tabelle.
private struct KeyValues {
    let values: [String: String]

    init(_ raw: [[String]]) {
        values = Dictionary(
            raw.dropFirst().compactMap { $0.count >= 1 ? ($0[0].trimmingCharacters(in: .whitespaces), $0.count > 1 ? $0[1] : "") : nil },
            uniquingKeysWith: { first, _ in first }
        )
    }

    subscript(key: String) -> String {
        values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Formatierung und tolerantes Parsen von Zellwerten.
/// Liest auch Werte, die Excel beim Bearbeiten umwandelt (Datums-/Zeit-Seriennummern).
private enum Cell {
    private static let calendar = Calendar.school
    private static let weekdays = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func dateTime(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return "\(self.date(date)) \(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0))"
    }

    static func bool(_ value: Bool) -> String { value ? "ja" : "nein" }
    static func list(_ values: [String]) -> String { values.joined(separator: "; ") }
    static func weekday(_ index: Int) -> String { weekdays.indices.contains(index) ? weekdays[index] : "" }

    static func parseList(_ text: String) -> [String] {
        text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func parseBool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "ja", "yes", "true", "wahr", "1", "x": true
        case "nein", "no", "false", "falsch", "0": false
        default: nil
        }
    }

    static func parseWeekday(_ text: String) -> Int? {
        if let number = Int(text), (1...7).contains(number) { return number - 1 }
        let lower = text.lowercased()
        return weekdays.firstIndex { $0.lowercased() == lower || $0.lowercased().prefix(2) == lower.prefix(2) && lower.count >= 2 }
    }

    static func parseGender(_ text: String) -> Gender? {
        let lower = text.lowercased()
        return Gender.allCases.first { $0.title == lower || String($0.title.prefix(1)) == lower || $0.rawValue == lower }
    }

    /// „2026-09-29“, „29.09.2026“ oder Excel-Seriennummer.
    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let serial = Double(trimmed) { return excelDate(serial) }
        let datePart = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        let iso = datePart.split(separator: "-").compactMap { Int($0) }
        if iso.count == 3 { return calendar.date(from: DateComponents(year: iso[0], month: iso[1], day: iso[2])) }
        let german = datePart.split(separator: ".").compactMap { Int($0) }
        if german.count == 3 {
            let year = german[2] < 100 ? 2000 + german[2] : german[2]
            return calendar.date(from: DateComponents(year: year, month: german[1], day: german[0]))
        }
        return nil
    }

    /// „2026-09-29 08:00“, Datum allein oder Excel-Seriennummer mit Bruchteil.
    static func parseDateTime(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let serial = Double(trimmed) { return excelDate(serial) }
        guard let day = parseDate(trimmed) else { return nil }
        let parts = trimmed.split(separator: " ")
        guard parts.count > 1, let minutes = parseTime(String(parts[1])) else { return day }
        return calendar.date(byAdding: .minute, value: minutes, to: day)
    }

    /// „08:05“ oder Excel-Zeit (Tagesbruchteil) → Minuten seit Mitternacht.
    static func parseTime(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let fraction = Double(trimmed), fraction < 1, !trimmed.contains(":") {
            return Int((fraction * 24 * 60).rounded())
        }
        let parts = trimmed.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }

    /// Excel zählt Tage ab 30.12.1899 (inkl. des historischen Schaltjahr-Fehlers).
    private static func excelDate(_ serial: Double) -> Date? {
        guard serial > 1, serial < 2_958_466,
              let base = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30)),
              let day = calendar.date(byAdding: .day, value: Int(serial), to: base)
        else { return nil }
        let minutes = Int(((serial - serial.rounded(.down)) * 24 * 60).rounded())
        return calendar.date(byAdding: .minute, value: minutes, to: day)
    }
}
