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
        var skippedDocuments = 0 // Dokument- und Bild-Kacheln ohne Datei

        var text: String {
            var parts = [
                "\(classes) Klassen", "\(students) Schüler", "\(lessons) Stunden",
                "\(entries) Termine", "\(links) Kacheln", "\(holidays) Ferien/Feiertage",
            ]
            if skippedDocuments > 0 {
                parts.append("\(skippedDocuments) Dokument-/Bild-Kacheln übersprungen (Datei nicht auf diesem Gerät)")
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

        return XLSX.write([
            infoSheet(),
            classesSheet(classes),
            studentsSheet(classes),
            lessonsSheet(classes),
            entriesSheet(entries),
            linksSheet(classes),
            holidaysSheet(holidays),
        ] + settingsSheets(settings, appearance: appearance))
    }

    private static func infoSheet() -> XLSXSheet {
        XLSXSheet(name: Sheet.info, rows: [
            ["Schlüssel", "Wert"],
            ["Format", formatName],
            ["Formatversion", "\(formatVersion)"],
            ["Exportiert am", Cell.dateTime(.now)],
            ["App-Version", AppInfo.version],
        ])
    }

    private static func classesSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.classes, rows: [
            [
                "ID", "Kürzel", "Fächer", "Schuljahr", "Farbe", "Erstellt",
                "Kachel-Reihenfolge", "Ausgeblendete Kacheln", "Entfernte Kacheln",
            ],
        ] + classes.map {
            [$0.id.uuidString, $0.shortName, Cell.list($0.subjects), $0.schoolYear, $0.colorRaw,
             Cell.dateTime($0.createdAt), Cell.list($0.dashboardOrder), Cell.list($0.dashboardHidden),
             Cell.list($0.dashboardRemoved)]
        })
    }

    private static func studentsSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.students, rows: [
            ["ID", "Klassen-ID", "Klasse", "Vorname", "Nachname", "Geburtstag", "Geschlecht", "Notizen", "Erstellt"],
        ] + classes.flatMap { schoolClass in
            schoolClass.sortedStudents.map {
                [$0.id.uuidString, schoolClass.id.uuidString, schoolClass.shortName, $0.firstName, $0.lastName,
                 Cell.date($0.birthday), $0.gender?.title ?? "", $0.notes, Cell.dateTime($0.createdAt)]
            }
        })
    }

    private static func lessonsSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.lessons, rows: [
            ["ID", "Klassen-ID", "Klasse", "Wochentag", "Stunde", "Fach", "Wöchentlich", "Datum"],
        ] + classes.flatMap { schoolClass in
            schoolClass.lessons
                .sorted { ($0.weekday, $0.slotIndex) < ($1.weekday, $1.slotIndex) }
                .map {
                    [$0.id.uuidString, schoolClass.id.uuidString, schoolClass.shortName, Cell.weekday($0.weekday),
                     "\($0.slotIndex + 1)", $0.subject, Cell.bool($0.isRecurring), Cell.date($0.date)]
                }
        })
    }

    private static func entriesSheet(_ entries: [CalendarEntry]) -> XLSXSheet {
        XLSXSheet(name: Sheet.entries, rows: [
            ["ID", "Klassen-ID", "Klasse", "Titel", "Beginn", "Ende", "Notizen"],
        ] + entries.map {
            [$0.id.uuidString, $0.schoolClass?.id.uuidString ?? "", $0.schoolClass?.shortName ?? "",
             $0.title, Cell.dateTime($0.start), Cell.dateTime($0.end), $0.notes]
        })
    }

    private static func linksSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.links, rows: [
            ["ID", "Klassen-ID", "Klasse", "Typ", "Titel", "Adresse / Datei", "Erstellt"],
        ] + classes.flatMap { schoolClass in
            schoolClass.dashboardLinks.sorted { $0.createdAt < $1.createdAt }.map {
                [$0.id.uuidString, schoolClass.id.uuidString, schoolClass.shortName,
                 Cell.linkKind($0.kind), $0.title,
                 $0.kind.isStoredFile ? $0.detail : $0.location, Cell.dateTime($0.createdAt)]
            }
        })
    }

    private static func holidaysSheet(_ holidays: [Holiday]) -> XLSXSheet {
        XLSXSheet(name: Sheet.holidays, rows: [
            ["ID", "Name", "Beginn", "Ende", "Schulferien"],
        ] + holidays.map {
            [$0.id, $0.name, Cell.date($0.startDate), Cell.date($0.endDate), Cell.bool($0.isSchoolHoliday)]
        })
    }

    private static func settingsSheets(_ settings: SchoolSettings.Values, appearance: AppAppearance) -> [XLSXSheet] {
        let school = settings.school
        let teacher = settings.teacher
        return [
            XLSXSheet(name: Sheet.school, rows: [
                ["Schlüssel", "Wert"],
                ["Name", school.name], ["Website", school.website], ["Straße", school.street],
                ["PLZ", school.postalCode], ["Ort", school.city], ["Telefon", school.phone], ["E-Mail", school.email],
            ]),
            XLSXSheet(name: Sheet.schoolDay, rows: [
                ["Schlüssel", "Wert"],
                ["Beginn", settings.dayStart.clockString],
                ["Ende", settings.dayEnd.clockString],
                ["Stundenlänge (min)", "\(settings.lessonDuration)"],
                ["Wochenende anzeigen", Cell.bool(settings.showWeekends)],
                ["Bundesland", settings.federalState ?? ""],
            ]),
            XLSXSheet(name: Sheet.breaks, rows: [
                ["Beginn", "Dauer (min)"],
            ] + settings.breaks.sorted { $0.start < $1.start }.map { [$0.start.clockString, "\($0.duration)"] }),
            XLSXSheet(name: Sheet.profile, rows: [
                ["Schlüssel", "Wert"],
                ["Vorname", teacher.firstName], ["Nachname", teacher.lastName],
                ["Geburtstag", Cell.date(teacher.birthday)], ["Geschlecht", teacher.gender?.title ?? ""],
            ]),
            XLSXSheet(name: Sheet.app, rows: [
                ["Schlüssel", "Wert"],
                ["Erscheinungsbild", appearance.title],
            ]),
        ]
    }
}
