import Foundation
import SwiftData

// Import-Teil von `Backup` (Wiederherstellen aus einer Excel-Datei).
extension Backup {
    // MARK: Import

    struct ImportedSettings {
        var values: SchoolSettings.Values
        var appearance: AppAppearance?
        var language: AppLanguage?
        var accent: String?
        var iconTheme: IconTheme?
        /// Zähler der Statistiken, nur wenn die Datei das Blatt enthält.
        var funStats: [FunStat: Int]?
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

        // Fotos stehen nicht in der Datei: die von Schülern mit gleicher ID behalten, alle anderen entfallen.
        let existingPhotos = try context.fetch(FetchDescriptor<Student>())
            .reduce(into: [UUID: Data]()) { photos, student in photos[student.id] = student.photo }

        // Tafelbilder stehen nicht in der Datei: die von Klassen mit gleicher ID (und weiterhin vorhandenem Fach) behalten.
        let boardPhotos = try context.fetch(FetchDescriptor<BoardPhoto>())
        let existingBoardPhotos = boardPhotos.compactMap { photo in
            photo.schoolClass.map { (classID: $0.id, subject: photo.subject, takenAt: photo.takenAt, data: photo.imageData) }
        }

        // Räume nur ersetzen, wenn die Datei sie enthält (ältere Exporte haben keine Raum-Blätter).
        // Sitzplan-Zuordnungen kommen aus dem Blatt „Sitzplätze“ (ältere Exporte: entfallen mit den Schülern).
        let replacesRooms = workbook[Sheet.rooms] != nil
        // Einzeln löschen und speichern, bevor neu angelegt wird: Sammel-Löschen scheitert, sobald Schüler mit
        // Beziehungen existieren, und gleiche IDs dürfen erst nach dem Löschen wieder eingefügt werden.
        boardPhotos.forEach(context.delete)
        try context.deleteEach(SeatAssignment.self, ChecklistCheck.self, Checklist.self, StudentObservation.self, Absence.self,
                               SubjectSettings.self, AssessmentResult.self, Assessment.self, PeriodGrade.self,
                               Student.self, Lesson.self, DashboardLink.self, CalendarEntry.self,
                               Holiday.self, SchoolClass.self)
        if replacesRooms {
            try context.deleteEach(RoomElement.self, Room.self)
        }
        try context.save()

        var importer = Importer(context: context, existingFiles: existingFiles, existingPhotos: existingPhotos)
        if replacesRooms {
            importer.importRooms(table(Sheet.rooms), elements: table(Sheet.roomElements))
        } else {
            importer.roomsByID = try context.fetch(FetchDescriptor<Room>()).reduce(into: [:]) { $0[$1.id] = $1 }
        }
        importer.importClasses(table(Sheet.classes))
        importer.importStudents(table(Sheet.students))
        importer.importLessons(table(Sheet.lessons))
        importer.importEntries(table(Sheet.entries))
        importer.importLinks(table(Sheet.links))
        importer.importHolidays(table(Sheet.holidays))
        importer.importSeats(table(Sheet.seats))
        importer.importChecklists(table(Sheet.checklists), checks: table(Sheet.checklistChecks))
        importer.importAssessments(
            table(Sheet.assessments), results: table(Sheet.assessmentResults), periodGrades: table(Sheet.periodGrades)
        )
        importer.importRecords(
            observations: table(Sheet.observations), absences: table(Sheet.absences), settings: table(Sheet.subjectSettings)
        )
        for photo in existingBoardPhotos {
            guard let schoolClass = importer.classesByID[photo.classID], schoolClass.subjects.contains(photo.subject) else { continue }
            context.insert(BoardPhoto(subject: photo.subject, takenAt: photo.takenAt, imageData: photo.data, schoolClass: schoolClass))
        }

        try context.save()
        removeUnreferencedFiles(keeping: importer.keptFileLocations)

        return (importer.summary, importedSettings(from: workbook, current: currentSettings))
    }

    /// Legt die Datensätze eines Imports an (je Blatt eine Methode).
    private struct Importer {
        let context: ModelContext
        let existingFiles: [UUID: String]
        let existingPhotos: [UUID: Data]
        var summary = ImportSummary()
        var classesByID: [UUID: SchoolClass] = [:]
        var roomsByID: [UUID: Room] = [:]
        var studentsByID: [UUID: Student] = [:]
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
                schoolClass.quickNote = row["Schnellnotiz"]
                schoolClass.quickNoteEditedAt = Cell.parseDateTime(row["Schnellnotiz bearbeitet"])
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
                let id = UUID(uuidString: row["ID"]) ?? UUID()
                let student = Student(
                    id: id,
                    firstName: row["Vorname"],
                    lastName: row["Nachname"],
                    birthday: Cell.parseDate(row["Geburtstag"]),
                    gender: Cell.parseGender(row["Geschlecht"]),
                    notes: row["Notizen"],
                    phone: row["Telefon"],
                    email: row["E-Mail"],
                    otherContact: row["Sonstiges"],
                    photo: existingPhotos[id],
                    createdAt: Cell.parseDateTime(row["Erstellt"]) ?? .now,
                    schoolClass: schoolClass
                )
                context.insert(student)
                studentsByID[id] = student
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
                let lesson = Lesson(
                    id: UUID(uuidString: row["ID"]) ?? UUID(),
                    weekday: weekday,
                    slotIndex: number - 1,
                    subject: row["Fach"],
                    isRecurring: isRecurring,
                    date: isRecurring ? nil : date,
                    schoolClass: schoolClass
                )
                context.insert(lesson)
                lesson.room = UUID(uuidString: row["Raum-ID"]).flatMap { roomsByID[$0] }
                summary.lessons += 1
            }
        }

        mutating func importEntries(_ rows: [Table.Row]) {
            for row in rows {
                guard let start = Cell.parseDateTime(row["Beginn"]) else { continue }
                let end = Cell.parseDateTime(row["Ende"]).map { max($0, start) } ?? start.addingTimeInterval(3600)
                let entry = CalendarEntry(
                    id: UUID(uuidString: row["ID"]) ?? UUID(),
                    title: row["Titel"], start: start, end: end, notes: row["Notizen"],
                    schoolClass: schoolClass(for: row)
                )
                context.insert(entry)
                entry.room = UUID(uuidString: row["Raum-ID"]).flatMap { roomsByID[$0] }
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
                          FileManager.default.fileExists(
                              atPath: LinkFileStore.directory.appending(path: location).path(percentEncoded: false)
                          )
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

        /// Räume mit Grundriss; dieselbe Gültigkeitsprüfung wie im Editor, ungültige Räume werden übersprungen.
        mutating func importRooms(_ rows: [Table.Row], elements elementRows: [Table.Row]) {
            let elementsByRoom = Dictionary(grouping: elementRows) { $0["Raum-ID"] }
            for row in rows {
                guard let name = row["Name"].nonEmpty else { continue }
                let id = UUID(uuidString: row["ID"]) ?? UUID()
                guard let shapes = Self.shapes(from: elementsByRoom[row["ID"]] ?? []), RoomValidation.isValid(shapes) else {
                    summary.invalidRooms.append(name)
                    continue
                }
                let room = Room(
                    id: id,
                    name: name,
                    subtitle: row["Untertitel"],
                    category: Cell.parseRoomCategory(row["Kategorie"]),
                    assignments: Cell.parseList(row["Fächer"]),
                    sortIndex: Int(row["Reihenfolge"]) ?? roomsByID.count,
                    createdAt: Cell.parseDateTime(row["Erstellt"]) ?? .now
                )
                room.equipment = Cell.parseList(row["Ausstattung"])
                context.insert(room)
                room.replaceElements(with: shapes, in: context)
                roomsByID[id] = room
                summary.rooms += 1
            }
        }

        /// Sitzplätze nach denselben Regeln wie im Sitzplan; Zeilen ohne passenden Tisch oder Schüler entfallen.
        mutating func importSeats(_ rows: [Table.Row]) {
            let tables = roomsByID.values.flatMap(SeatingPlan.tables(in:)).reduce(into: [UUID: RoomElement]()) { $0[$1.id] = $1 }
            for row in rows {
                guard let table = UUID(uuidString: row["Tisch-ID"]).flatMap({ tables[$0] }),
                      let student = UUID(uuidString: row["Schüler-ID"]).flatMap({ studentsByID[$0] })
                else { continue }
                SeatingPlan.assign(student, to: table, in: context)
                summary.seats += 1
            }
        }

        /// Raumelemente aus den Zeilen; `nil`, wenn eine Art oder ein Punkt nicht lesbar ist.
        private static func shapes(from rows: [Table.Row]) -> [RoomShape]? {
            var usedIDs: Set<UUID> = []
            var shapes: [RoomShape] = []
            for row in rows {
                guard let kind = Cell.parseRoomElementKind(row["Art"]), let points = Cell.parsePoints(row["Punkte"]) else { return nil }
                let id = UUID(uuidString: row["ID"]).flatMap { usedIDs.contains($0) ? nil : $0 } ?? UUID()
                usedIDs.insert(id)
                shapes.append(RoomShape(id: id, kind: kind, points: points))
            }
            return shapes
        }

        mutating func importChecklists(_ rows: [Table.Row], checks: [Table.Row]) {
            var checklistsByID: [UUID: Checklist] = [:]
            for row in rows {
                guard let schoolClass = UUID(uuidString: row["Klassen-ID"]).flatMap({ classesByID[$0] }) else { continue }
                let created = Cell.parseDateTime(row["Erstellt"]) ?? .now
                let checklist = Checklist(
                    id: UUID(uuidString: row["ID"]).flatMap { checklistsByID[$0] == nil ? $0 : nil } ?? UUID(),
                    title: row["Titel"],
                    subtitle: row["Untertitel"],
                    subject: row["Fach"],
                    createdAt: created,
                    updatedAt: Cell.parseDateTime(row["Bearbeitet"]) ?? created,
                    schoolClass: schoolClass
                )
                checklist.dueDate = Cell.parseDate(row["Enddatum"])
                context.insert(checklist)
                checklistsByID[checklist.id] = checklist
                summary.checklists += 1
            }
            for row in checks {
                guard let checklist = UUID(uuidString: row["Checklisten-ID"]).flatMap({ checklistsByID[$0] }),
                      let student = UUID(uuidString: row["Schüler-ID"]).flatMap({ studentsByID[$0] }),
                      checklist.check(for: student) == nil
                else { continue }
                context.insert(ChecklistCheck(
                    checkedAt: Cell.parseDateTime(row["Abgehakt am"]) ?? .now, checklist: checklist, student: student
                ))
            }
        }

        /// Leistungen mit Ergebnissen und die selbst eingetragenen Noten.
        mutating func importAssessments(_ rows: [Table.Row], results: [Table.Row], periodGrades: [Table.Row]) {
            var assessmentsByID: [UUID: Assessment] = [:]
            for row in rows {
                guard let schoolClass = UUID(uuidString: row["Klassen-ID"]).flatMap({ classesByID[$0] }) else { continue }
                let date = Cell.parseDate(row["Datum"]) ?? .now
                let assessment = Assessment(
                    id: UUID(uuidString: row["ID"]).flatMap { assessmentsByID[$0] == nil ? $0 : nil } ?? UUID(),
                    subject: row["Fach"], title: row["Titel"], typeName: row["Art"],
                    area: AssessmentArea(rawValue: row["Bereich"]) ?? .other, date: date,
                    maxPoints: Double(row["Höchstpunktzahl"].replacingOccurrences(of: ",", with: ".")),
                    createdAt: Cell.parseDateTime(row["Erstellt"]) ?? date, schoolClass: schoolClass
                )
                context.insert(assessment)
                assessmentsByID[assessment.id] = assessment
                summary.assessments += 1
            }
            for row in results {
                guard let assessment = UUID(uuidString: row["Leistungs-ID"]).flatMap({ assessmentsByID[$0] }),
                      let student = UUID(uuidString: row["Schüler-ID"]).flatMap({ studentsByID[$0] }),
                      assessment.result(for: student) == nil
                else { continue }
                let result = AssessmentResult(
                    grade: row["Note"], rawPoints: Double(row["Rohpunkte"].replacingOccurrences(of: ",", with: ".")),
                    isMissing: Cell.parseBool(row["Fehlt"]) ?? false, assessment: assessment, student: student
                )
                result.note = row["Notiz"]
                result.editedAt = Cell.parseDateTime(row["Geändert"])
                result.previousGrade = row["Vorher"]
                context.insert(result)
            }
            for row in periodGrades {
                guard let student = UUID(uuidString: row["Schüler-ID"]).flatMap({ studentsByID[$0] }),
                      let period = GradePeriod(rawValue: row["Abschnitt"]), let scope = GradeScope(rawValue: row["Bereich"]),
                      !row["Note"].isEmpty
                else { continue }
                let grade = PeriodGrade(
                    subject: row["Fach"], schoolYear: row["Schuljahr"], period: period, scope: scope, grade: row["Note"], student: student
                )
                grade.editedAt = Cell.parseDateTime(row["Geändert"])
                grade.previousGrade = row["Vorher"]
                context.insert(grade)
            }
        }

        /// Schülerakte: Beobachtungen, Fehlzeiten und Bewertungs-Einstellungen.
        mutating func importRecords(observations: [Table.Row], absences: [Table.Row], settings: [Table.Row]) {
            for row in observations {
                guard let student = UUID(uuidString: row["Schüler-ID"]).flatMap({ studentsByID[$0] }),
                      let date = Cell.parseDateTime(row["Datum"])
                else { continue }
                let observation = StudentObservation(
                    subject: row["Fach"], date: date, slotIndex: (Int(row["Stunde"]) ?? 0) - 1,
                    kind: StudentObservation.Kind(rawValue: row["Art"]) ?? .note,
                    scale: ObservationScale(rawValue: row["Skala"]) ?? .sevenStep,
                    value: Int(row["Wert"]) ?? 0, note: row["Notiz"], createdAt: Cell.parseDateTime(row["Erstellt"]) ?? date,
                    student: student
                )
                observation.editedAt = Cell.parseDateTime(row["Geändert"])
                observation.previousLabel = row["Vorher"]
                context.insert(observation)
                summary.observations += 1
            }
            for row in absences {
                guard let student = UUID(uuidString: row["Schüler-ID"]).flatMap({ studentsByID[$0] }),
                      let day = Cell.parseDate(row["Tag"])
                else { continue }
                context.insert(Absence(
                    subject: row["Fach"], day: day, slotIndex: (Int(row["Stunde"]) ?? 0) - 1,
                    kind: Absence.Kind(rawValue: row["Art"]) ?? .absent, arrivedAt: Cell.parseDateTime(row["Eingetroffen"]),
                    createdAt: Cell.parseDateTime(row["Erstellt"]) ?? day, student: student
                ))
            }
            for row in settings {
                guard let schoolClass = UUID(uuidString: row["Klassen-ID"]).flatMap({ classesByID[$0] }),
                      !schoolClass.subjectSettings.contains(where: { $0.subject == row["Fach"] })
                else { continue }
                context.insert(SubjectSettings(
                    subject: row["Fach"], scale: ObservationScale(rawValue: row["Skala"]) ?? .sevenStep,
                    gradeSystem: GradeSystem(rawValue: row["Notensystem"]) ?? .grades,
                    hasWrittenWork: Cell.parseBool(row["Schriftliche Arbeiten"]) ?? true, schoolClass: schoolClass
                ))
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
        let accent = app.map { $0["Akzentfarbe"].trimmingCharacters(in: .whitespaces) }.flatMap { AppAccent.isValid($0) ? $0 : nil }
        let iconTheme = app.flatMap { app in IconManager.shared.themes.first { $0.title == app["Icons"] } }
        let funStats = workbook[Sheet.funStats].map(KeyValues.init).map { sheet in
            FunStat.allCases.reduce(into: [FunStat: Int]()) { result, stat in
                if let value = Int(sheet[stat.backupKey]) { result[stat] = value }
            }
        }
        if let type = app.flatMap({ SchoolType(rawValue: $0["Schulform"]) }) { values.schoolType = type }
        if let app {
            values.areaNames = [
                AssessmentArea.written.rawValue: app["Bereich schriftlich"], AssessmentArea.other.rawValue: app["Bereich sonstige"],
            ].filter { !$0.value.isEmpty }
        }
        if let types = workbook[Sheet.assessmentTypes].map(Table.init), !types.rows.isEmpty {
            values.assessmentTypes = types.rows.compactMap { row in
                guard !row["Name"].isEmpty else { return nil }
                return AssessmentType(
                    id: UUID(uuidString: row["ID"]) ?? UUID(), name: row["Name"],
                    area: AssessmentArea(rawValue: row["Bereich"]) ?? .other, isHidden: Cell.parseBool(row["Ausgeblendet"]) ?? false
                )
            }
        }
        return ImportedSettings(
            values: values, appearance: appearance, language: language, accent: accent, iconTheme: iconTheme, funStats: funStats
        )
    }

    /// Kopierte Dokumente, die nach dem Import keiner Kachel mehr gehören, entfernen.
    private static func removeUnreferencedFiles(keeping locations: Set<String>) {
        let keptFolders = Set(locations.map { ($0 as NSString).deletingLastPathComponent })
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: LinkFileStore.directory.path(percentEncoded: false))) ?? []
        for folder in folders where !keptFolders.contains(folder) {
            try? FileManager.default.removeItem(at: LinkFileStore.directory.appending(path: folder))
        }
    }
}
