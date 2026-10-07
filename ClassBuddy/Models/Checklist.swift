import Foundation
import SwiftData

/// Checkliste einer Klasse, z. B. „Name in die Bücher eingetragen“: je Schüler abgehakt oder offen.
/// Gilt für ein Fach oder (leeres `subject`) für alle Fächer der Klasse.
@Model
final class Checklist {
    @Attribute(.unique) var id: UUID
    var title: String
    var subtitle: String
    /// Leer = für alle Fächer der Klasse.
    var subject: String
    var createdAt: Date
    var updatedAt: Date
    /// Optionales Enddatum (Tagesbeginn), z. B. „bis Freitag“.
    var dueDate: Date?
    var schoolClass: SchoolClass?

    @Relationship(deleteRule: .cascade, inverse: \ChecklistCheck.checklist)
    var checks: [ChecklistCheck] = []

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        subject: String = "",
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        schoolClass: SchoolClass? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.subject = subject
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.schoolClass = schoolClass
    }

    var isGlobal: Bool { subject.isEmpty }

    /// Enddatum überschritten und noch nicht alle abgehakt.
    var isOverdue: Bool {
        guard let dueDate else { return false }
        let progress = progress
        return Calendar.school.startOfDay(for: .now) > dueDate && progress.done < progress.total
    }

    /// „Alle Fächer“ bzw. Name des Fachs.
    var scopeTitle: String {
        isGlobal ? loc("Alle Fächer") : SchoolClass.displayName(ofSubject: subject)
    }
}

/// Ein abgehakter Schüler (offen = kein Eintrag).
@Model
final class ChecklistCheck {
    @Attribute(.unique) var id: UUID
    var checkedAt: Date
    var checklist: Checklist?
    var student: Student?

    init(id: UUID = UUID(), checkedAt: Date = .now, checklist: Checklist? = nil, student: Student? = nil) {
        self.id = id
        self.checkedAt = checkedAt
        self.checklist = checklist
        self.student = student
    }
}

extension Checklist {
    func check(for student: Student) -> ChecklistCheck? {
        checks.first { $0.student?.id == student.id }
    }

    func check(_ student: Student, at date: Date = .now, in context: ModelContext) {
        guard check(for: student) == nil else { return }
        context.insert(ChecklistCheck(checkedAt: date, checklist: self, student: student))
        updatedAt = date
    }

    func uncheck(_ student: Student, at date: Date = .now, in context: ModelContext) {
        guard let existing = check(for: student) else { return }
        context.delete(existing)
        updatedAt = date
    }

    /// Erledigt / gesamt, nur Schüler, die noch in der Klasse sind.
    var progress: (done: Int, total: Int) {
        let students = schoolClass?.students ?? []
        let ids = Set(students.map(\.id))
        let done = Set(checks.compactMap { $0.student?.id }).intersection(ids).count
        return (done, students.count)
    }

    /// Kopie mit gleichem Titel, Untertitel und Fach, ohne Haken.
    func duplicate(in context: ModelContext, at date: Date = .now) -> Checklist {
        let copy = Checklist(title: loc("\(title) (Kopie)"), subtitle: subtitle, subject: subject, createdAt: date, schoolClass: schoolClass)
        copy.dueDate = dueDate
        context.insert(copy)
        return copy
    }
}

extension SchoolClass {
    /// Checklisten von Fächern löschen, die die Klasse nicht mehr hat (wie bei den Tafelbildern).
    func removeChecklistsOfRemovedSubjects(in context: ModelContext) {
        for checklist in checklists where !checklist.isGlobal && !subjects.contains(checklist.subject) {
            context.delete(checklist)
        }
    }

    /// Zuletzt bearbeitete Checkliste (für die Kachel).
    var latestChecklist: Checklist? {
        checklists.max { $0.updatedAt < $1.updatedAt }
    }
}

/// Gruppen im Tab: Fach der aktuellen Stunde zuerst, dann „Alle Fächer“, dann die übrigen Fächer in Klassenreihenfolge.
nonisolated enum ChecklistGrouping {
    struct Group: Equatable {
        /// `nil` = alle Fächer.
        let subject: String?
        let isCurrent: Bool
        let ids: [UUID]
    }

    struct Item {
        let id: UUID
        let subject: String
        let updatedAt: Date
    }

    static func groups(_ items: [Item], subjects: [String], current: String?) -> [Group] {
        func ids(for subject: String) -> [UUID] {
            items.filter { $0.subject == subject }.sorted { $0.updatedAt > $1.updatedAt }.map(\.id)
        }
        var result: [Group] = []
        if let current, subjects.contains(current), !ids(for: current).isEmpty {
            result.append(Group(subject: current, isCurrent: true, ids: ids(for: current)))
        }
        if !ids(for: "").isEmpty {
            result.append(Group(subject: nil, isCurrent: false, ids: ids(for: "")))
        }
        for subject in subjects where subject != current && !ids(for: subject).isEmpty {
            result.append(Group(subject: subject, isCurrent: false, ids: ids(for: subject)))
        }
        return result
    }
}

/// Vorlagen beim Anlegen (antippen füllt Titel und Untertitel).
enum ChecklistTemplates {
    struct Template: Hashable {
        let title: String
        let subtitle: String
    }

    static var all: [Template] {
        [
            Template(title: loc("Name in die Bücher eingetragen"), subtitle: loc("Alle Schulbücher, bis Ende der Woche")),
            Template(title: loc("Vor der Klasse präsentiert"), subtitle: loc("Kurzvortrag, etwa 5 Minuten")),
            Template(title: loc("Elternbrief zurückgegeben"), subtitle: loc("Unterschrieben, für den Wandertag")),
            Template(title: loc("Einverständniserklärung abgegeben"), subtitle: loc("Fotos für die Schulhomepage")),
            Template(title: loc("Hausaufgabenheft unterschrieben"), subtitle: loc("Von einem Elternteil, wöchentlich")),
            Template(title: loc("Buch zurückgegeben"), subtitle: loc("Lektüre aus der Bibliothek")),
        ]
    }
}
