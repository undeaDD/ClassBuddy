import Foundation
import SwiftData

/// Regeln des Sitzplans: je Klasse höchstens ein Schüler pro Tisch, je Schüler höchstens ein Tisch pro Raum.
/// Ein Tisch kann so für mehrere Klassen (die den Raum nutzen) je einen Schüler tragen.
enum SeatingPlan {
    /// Tische des Raums in Zeichenreihenfolge.
    static func tables(in room: Room) -> [RoomElement] {
        room.elements.filter { $0.kind == .table }.sorted { $0.order < $1.order }
    }

    /// Tisch-ID → Schüler der Klasse auf diesem Tisch.
    static func occupants(in room: Room, schoolClass: SchoolClass) -> [UUID: Student] {
        var result: [UUID: Student] = [:]
        for table in tables(in: room) {
            let student = table.seatAssignments.compactMap(\.student).first { $0.schoolClass?.id == schoolClass.id }
            if let student { result[table.id] = student }
        }
        return result
    }

    /// Setzt den Schüler auf den Tisch. Sein bisheriger Platz im Raum und ein bisheriger Schüler
    /// derselben Klasse auf dem Tisch werden freigegeben.
    static func assign(_ student: Student, to table: RoomElement, in context: ModelContext) {
        guard let room = table.room else { return }
        let classID = student.schoolClass?.id
        let replaced = student.seatAssignments.filter { $0.element?.room?.id == room.id }
            + table.seatAssignments.filter { $0.student?.schoolClass?.id == classID }
        delete(replaced, in: context)
        let assignment = SeatAssignment(element: nil, student: nil)
        context.insert(assignment)
        assignment.element = table
        assignment.student = student
    }

    /// Zieht einen Schüler auf einen Tisch (aus der Liste oder von einem anderen Tisch).
    /// Kommt er von einem anderen Tisch und sitzt auf dem Ziel schon jemand der Klasse, tauschen beide die Plätze.
    static func move(_ student: Student, to table: RoomElement, in context: ModelContext) {
        guard let room = table.room else { return }
        let previous = student.seatAssignments.first { $0.element?.room?.id == room.id }?.element
        guard previous?.id != table.id else { return }
        let classID = student.schoolClass?.id
        let other = table.seatAssignments.compactMap(\.student).first { $0.schoolClass?.id == classID }
        assign(student, to: table, in: context)
        if let other, let previous {
            assign(other, to: previous, in: context)
        }
    }

    /// Gibt den Platz der Klasse auf diesem Tisch frei.
    static func clear(_ table: RoomElement, schoolClass: SchoolClass, in context: ModelContext) {
        delete(table.seatAssignments.filter { $0.student?.schoolClass?.id == schoolClass.id }, in: context)
    }

    /// Gibt alle Plätze der Klasse im Raum frei.
    static func clearAll(in room: Room, schoolClass: SchoolClass, in context: ModelContext) {
        for table in tables(in: room) {
            clear(table, schoolClass: schoolClass, in: context)
        }
    }

    /// Verteilt alle Schüler der Klasse zufällig neu. Liefert die Zahl der Schüler ohne Platz.
    @discardableResult
    static func shuffle(in room: Room, schoolClass: SchoolClass, in context: ModelContext) -> Int {
        clearAll(in: room, schoolClass: schoolClass, in: context)
        let tables = Dictionary(tables(in: room).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let students = Dictionary(schoolClass.students.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var generator = SystemRandomNumberGenerator()
        let plan = randomPlan(students: Array(students.keys), tables: Array(tables.keys), using: &generator)
        for (studentID, tableID) in plan {
            guard let student = students[studentID], let table = tables[tableID] else { continue }
            assign(student, to: table, in: context)
        }
        return students.count - plan.count
    }

    /// Zufällige Zuordnung Schüler → Tisch (rein, testbar). Gibt es mehr Schüler als Tische,
    /// bleiben die übrigen ohne Platz; gibt es mehr Tische, bleiben zufällige Tische frei.
    static func randomPlan<G: RandomNumberGenerator>(students: [UUID], tables: [UUID], using generator: inout G) -> [UUID: UUID] {
        let students = students.shuffled(using: &generator)
        let tables = tables.shuffled(using: &generator)
        return Dictionary(zip(students, tables).map { ($0, $1) }, uniquingKeysWith: { first, _ in first })
    }

    /// Löscht Zuordnungen und nimmt sie sofort aus den Beziehungen (sonst bis zum Speichern noch sichtbar).
    private static func delete(_ assignments: [SeatAssignment], in context: ModelContext) {
        let ids = Set(assignments.map(\.id))
        guard !ids.isEmpty else { return }
        for assignment in assignments {
            assignment.element?.seatAssignments.removeAll { ids.contains($0.id) }
            assignment.student?.seatAssignments.removeAll { ids.contains($0.id) }
            context.delete(assignment)
        }
    }
}
