import Foundation

// Export-Blätter für Checklisten, Schülerakte und Leistungen (Teil von `Backup`).
extension Backup {
    static func checklistsSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.checklists, rows: [
            ["ID", "Klassen-ID", "Klasse", "Titel", "Untertitel", "Fach", "Erstellt", "Bearbeitet", "Enddatum"],
        ] + classes.flatMap { schoolClass in
            schoolClass.checklists.sorted { $0.createdAt < $1.createdAt }.map {
                [$0.id.uuidString, schoolClass.id.uuidString, schoolClass.shortName, $0.title, $0.subtitle, $0.subject,
                 Cell.dateTime($0.createdAt), Cell.dateTime($0.updatedAt), Cell.date($0.dueDate)]
            }
        })
    }

    static func checklistChecksSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.checklistChecks, rows: [
            ["ID", "Checklisten-ID", "Checkliste", "Schüler-ID", "Schüler", "Abgehakt am"],
        ] + classes.flatMap(\.checklists).flatMap { checklist in
            checklist.checks.sorted { $0.checkedAt < $1.checkedAt }.compactMap { check in
                check.student.map {
                    [check.id.uuidString, checklist.id.uuidString, checklist.title, $0.id.uuidString, $0.fullName,
                     Cell.dateTime(check.checkedAt)]
                }
            }
        })
    }

    static func observationsSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.observations, rows: [
            ["ID", "Schüler-ID", "Schüler", "Fach", "Datum", "Stunde", "Art", "Skala", "Wert", "Notiz", "Erstellt", "Geändert", "Vorher"],
        ] + classes.flatMap(\.students).flatMap { student in
            student.observations.sorted { $0.date < $1.date }.map {
                [$0.id.uuidString, student.id.uuidString, student.fullName, $0.subject, Cell.dateTime($0.date), "\($0.slotIndex + 1)",
                 $0.kindRaw, $0.scaleRaw, "\($0.value)", $0.note, Cell.dateTime($0.createdAt),
                 $0.editedAt.map(Cell.dateTime) ?? "", $0.previousLabel]
            }
        })
    }

    static func absencesSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.absences, rows: [
            ["ID", "Schüler-ID", "Schüler", "Fach", "Tag", "Stunde", "Art", "Eingetroffen", "Erstellt"],
        ] + classes.flatMap(\.students).flatMap { student in
            student.absences.sorted { $0.day < $1.day }.map {
                [$0.id.uuidString, student.id.uuidString, student.fullName, $0.subject, Cell.date($0.day), "\($0.slotIndex + 1)",
                 $0.kindRaw, $0.arrivedAt.map(Cell.dateTime) ?? "", Cell.dateTime($0.createdAt)]
            }
        })
    }

    static func subjectSettingsSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.subjectSettings, rows: [
            ["ID", "Klassen-ID", "Klasse", "Fach", "Skala", "Notensystem", "Schriftliche Arbeiten"],
        ] + classes.flatMap { schoolClass in
            schoolClass.subjectSettings.map {
                [$0.id.uuidString, schoolClass.id.uuidString, schoolClass.shortName, $0.subject, $0.scaleRaw, $0.gradeSystemRaw,
                 Cell.bool($0.hasWrittenWork)]
            }
        })
    }

    static func assessmentsSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.assessments, rows: [
            ["ID", "Klassen-ID", "Klasse", "Fach", "Titel", "Art", "Bereich", "Datum", "Höchstpunktzahl", "Erstellt"],
        ] + classes.flatMap { schoolClass in
            schoolClass.assessments.sorted { $0.date < $1.date }.map {
                [$0.id.uuidString, schoolClass.id.uuidString, schoolClass.shortName, $0.subject, $0.title, $0.typeName, $0.areaRaw,
                 Cell.date($0.date), $0.maxPoints.map { "\($0)" } ?? "", Cell.dateTime($0.createdAt)]
            }
        })
    }

    static func assessmentResultsSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.assessmentResults, rows: [
            ["ID", "Leistungs-ID", "Leistung", "Schüler-ID", "Schüler", "Note", "Rohpunkte", "Fehlt", "Notiz", "Geändert", "Vorher"],
        ] + classes.flatMap(\.assessments).flatMap { assessment in
            assessment.results.compactMap { result in
                result.student.map {
                    [result.id.uuidString, assessment.id.uuidString, assessment.title, $0.id.uuidString, $0.fullName, result.grade,
                     result.rawPoints.map { "\($0)" } ?? "", Cell.bool(result.isMissing), result.note,
                     result.editedAt.map(Cell.dateTime) ?? "", result.previousGrade]
                }
            }
        })
    }

    static func periodGradesSheet(_ classes: [SchoolClass]) -> XLSXSheet {
        XLSXSheet(name: Sheet.periodGrades, rows: [
            ["ID", "Schüler-ID", "Schüler", "Fach", "Schuljahr", "Abschnitt", "Bereich", "Note", "Geändert", "Vorher"],
        ] + classes.flatMap(\.students).flatMap { student in
            student.periodGrades.map {
                [$0.id.uuidString, student.id.uuidString, student.fullName, $0.subject, $0.schoolYear, $0.periodRaw, $0.scopeRaw,
                 $0.grade, $0.editedAt.map(Cell.dateTime) ?? "", $0.previousGrade]
            }
        })
    }
}
