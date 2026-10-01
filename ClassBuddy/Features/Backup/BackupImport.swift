import Foundation
import SwiftData

// Import-Teil von `Backup` (Wiederherstellen aus einer Excel-Datei).
extension Backup {
    // MARK: Import

    struct ImportedSettings {
        var values: SchoolSettings.Values
        var appearance: AppAppearance?
        var language: AppLanguage?
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

        func table(_ name: String) -> [Table.Row] { workbook[name].map(Table.init)?.rows ?? [] }

        // Vorhandene Dokument-/Bild-Kacheln merken: ihre Dateien bleiben, wenn die ID im Import vorkommt.
        let existingFiles = try context.fetch(FetchDescriptor<DashboardLink>())
            .filter { $0.kind.isStoredFile }
            .reduce(into: [UUID: String]()) { $0[$1.id] = $1.location }

        try context.delete(model: Student.self)
        try context.delete(model: Lesson.self)
        try context.delete(model: DashboardLink.self)
        try context.delete(model: CalendarEntry.self)
        try context.delete(model: Holiday.self)
        try context.delete(model: SchoolClass.self)

        var importer = Importer(context: context, existingFiles: existingFiles)
        importer.importClasses(table(Sheet.classes))
        importer.importStudents(table(Sheet.students))
        importer.importLessons(table(Sheet.lessons))
        importer.importEntries(table(Sheet.entries))
        importer.importLinks(table(Sheet.links))
        importer.importHolidays(table(Sheet.holidays))

        try context.save()
        removeUnreferencedFiles(keeping: importer.keptFileLocations)

        return (importer.summary, importedSettings(from: workbook, current: currentSettings))
    }

    /// Legt die Datensätze eines Imports an (je Blatt eine Methode).
    private struct Importer {
        let context: ModelContext
        let existingFiles: [UUID: String]
        var summary = ImportSummary()
        var classesByID: [UUID: SchoolClass] = [:]
        var keptFileLocations: Set<String> = []

        private func schoolClass(for row: Table.Row) -> SchoolClass? {
            UUID(uuidString: row["Klassen-ID"]).flatMap { classesByID[$0] }
        }

        mutating func importClasses(_ rows: [Table.Row]) {
            for row in rows {
                guard let shortName = row["Kürzel"].nonEmpty else { continue }
                let schoolClass = SchoolClass(
                    id: UUID(uuidString: row["ID"]) ?? UUID(),
                    shortName: shortName,
                    subjects: Cell.parseList(row["Fächer"]),
                    schoolYear: row["Schuljahr"],
                    color: .blue,
                    createdAt: Cell.parseDateTime(row["Erstellt"]) ?? .now
                )
                schoolClass.colorRaw = SchoolClass.sanitizedColorRaw(row["Farbe"])
                schoolClass.dashboardOrder = Cell.parseList(row["Kachel-Reihenfolge"])
                schoolClass.dashboardHidden = Cell.parseList(row["Ausgeblendete Kacheln"])
                schoolClass.dashboardRemoved = Cell.parseList(row["Entfernte Kacheln"])
                schoolClass.dashboardKnownCards = schoolClass.dashboardOrder + schoolClass.dashboardHidden + schoolClass.dashboardRemoved
                context.insert(schoolClass)
                classesByID[schoolClass.id] = schoolClass
                summary.classes += 1
            }
        }

        mutating func importStudents(_ rows: [Table.Row]) {
            for row in rows {
                guard let schoolClass = schoolClass(for: row),
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
        }

        mutating func importLessons(_ rows: [Table.Row]) {
            for row in rows {
                guard let schoolClass = schoolClass(for: row),
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
        }

        mutating func importEntries(_ rows: [Table.Row]) {
            for row in rows {
                guard let start = Cell.parseDateTime(row["Beginn"]) else { continue }
                let end = Cell.parseDateTime(row["Ende"]).map { max($0, start) } ?? start.addingTimeInterval(3600)
                context.insert(CalendarEntry(
                    id: UUID(uuidString: row["ID"]) ?? UUID(),
                    title: row["Titel"], start: start, end: end, notes: row["Notizen"],
                    schoolClass: schoolClass(for: row)
                ))
                summary.entries += 1
            }
        }

        mutating func importLinks(_ rows: [Table.Row]) {
            for row in rows {
                guard let schoolClass = schoolClass(for: row) else { continue }
                let id = UUID(uuidString: row["ID"]) ?? UUID()
                let kind = Cell.parseLinkKind(row["Typ"])
                if kind.isStoredFile {
                    guard let location = existingFiles[id],
                          FileManager.default.fileExists(atPath: LinkFileStore.directory.appending(path: location).path())
                    else {
                        summary.skippedDocuments += 1
                        continue
                    }
                    keptFileLocations.insert(location)
                    context.insert(DashboardLink(id: id, title: row["Titel"], kind: kind, location: location, schoolClass: schoolClass))
                } else {
                    let location = switch kind {
                    case .shortcut, .script: row["Adresse / Datei"].nonEmpty
                    default: URL.web(row["Adresse / Datei"])?.absoluteString
                    }
                    guard let location else { continue }
                    context.insert(DashboardLink(id: id, title: row["Titel"], kind: kind, location: location, schoolClass: schoolClass))
                }
                summary.links += 1
            }
        }

        mutating func importHolidays(_ rows: [Table.Row]) {
            for row in rows {
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
        }
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
                birthday: Cell.parseDate(profile["Geburtstag"]), gender: Cell.parseGender(profile["Geschlecht"]),
                subjects: Cell.parseList(profile["Hauptfächer"])
            )
        }
        let app = workbook[Sheet.app].map(KeyValues.init)
        let appearance = app.flatMap { app in AppAppearance.allCases.first { $0.title == app["Erscheinungsbild"] } }
        let language = app.flatMap { app in AppLanguage(backupTitle: app["Sprache"]) }
        return ImportedSettings(values: values, appearance: appearance, language: language)
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
