import Foundation
import SwiftData

// Austauschformat, Fortsetzung von `SyncPayloads.swift`: Checklisten und Schülerakte.

extension Checklist: SyncCodable {
    struct Payload: Codable {
        var title: String
        var subtitle: String
        var subject: String
        var createdAt: Date
        var updatedAt: Date
        var dueDate: Date?
        var schoolClass: String?
    }

    var payload: Payload {
        Payload(
            title: title, subtitle: subtitle, subject: subject, createdAt: createdAt, updatedAt: updatedAt, dueDate: dueDate,
            schoolClass: schoolClass?.syncID
        )
    }

    static func makeEmpty(syncID: String) -> Checklist? {
        UUID(syncID: syncID).map { Checklist(id: $0, title: "") }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        title = payload.title
        subtitle = payload.subtitle
        subject = payload.subject
        createdAt = payload.createdAt
        updatedAt = payload.updatedAt
        dueDate = payload.dueDate
        schoolClass = references.find(payload.schoolClass)
    }
}

extension SubjectSettings: SyncCodable {
    struct Payload: Codable {
        var subject: String
        var scaleRaw: String
        var gradeSystemRaw: String
        var hasWrittenWork: Bool
        var schoolClass: String?
    }

    var payload: Payload {
        Payload(
            subject: subject, scaleRaw: scaleRaw, gradeSystemRaw: gradeSystemRaw, hasWrittenWork: hasWrittenWork,
            schoolClass: schoolClass?.syncID
        )
    }

    static func makeEmpty(syncID: String) -> SubjectSettings? {
        UUID(syncID: syncID).map {
            SubjectSettings(id: $0, subject: "", scale: .sevenStep, gradeSystem: .grades, hasWrittenWork: false, schoolClass: nil)
        }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        subject = payload.subject
        scaleRaw = payload.scaleRaw
        gradeSystemRaw = payload.gradeSystemRaw
        hasWrittenWork = payload.hasWrittenWork
        schoolClass = references.find(payload.schoolClass)
    }
}

extension Assessment: SyncCodable {
    struct Payload: Codable {
        var subject: String
        var title: String
        var typeName: String
        var areaRaw: String
        var date: Date
        var maxPoints: Double?
        var createdAt: Date
        var schoolClass: String?
    }

    var payload: Payload {
        Payload(
            subject: subject, title: title, typeName: typeName, areaRaw: areaRaw, date: date, maxPoints: maxPoints,
            createdAt: createdAt, schoolClass: schoolClass?.syncID
        )
    }

    static func makeEmpty(syncID: String) -> Assessment? {
        UUID(syncID: syncID).map { Assessment(id: $0, subject: "", title: "", typeName: "", area: .written, schoolClass: nil) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        subject = payload.subject
        title = payload.title
        typeName = payload.typeName
        areaRaw = payload.areaRaw
        date = payload.date
        maxPoints = payload.maxPoints
        createdAt = payload.createdAt
        schoolClass = references.find(payload.schoolClass)
    }
}

extension SeatAssignment: SyncCodable {
    struct Payload: Codable {
        var element: String?
        var student: String?
        var createdAt: Date
    }

    var payload: Payload { Payload(element: element?.syncID, student: student?.syncID, createdAt: createdAt) }

    static func makeEmpty(syncID: String) -> SeatAssignment? {
        UUID(syncID: syncID).map { SeatAssignment(id: $0, element: nil, student: nil) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        element = references.find(payload.element)
        student = references.find(payload.student)
        createdAt = payload.createdAt
    }
}

extension ChecklistCheck: SyncCodable {
    struct Payload: Codable {
        var checkedAt: Date
        var checklist: String?
        var student: String?
    }

    var payload: Payload { Payload(checkedAt: checkedAt, checklist: checklist?.syncID, student: student?.syncID) }

    static func makeEmpty(syncID: String) -> ChecklistCheck? {
        UUID(syncID: syncID).map { ChecklistCheck(id: $0) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        checkedAt = payload.checkedAt
        checklist = references.find(payload.checklist)
        student = references.find(payload.student)
    }
}

extension StudentObservation: SyncCodable {
    struct Payload: Codable {
        var subject: String
        var date: Date
        var slotIndex: Int
        var kindRaw: String
        var scaleRaw: String
        var value: Int
        var note: String
        var createdAt: Date
        var editedAt: Date?
        var previousLabel: String
        var student: String?
    }

    var payload: Payload {
        Payload(
            subject: subject, date: date, slotIndex: slotIndex, kindRaw: kindRaw, scaleRaw: scaleRaw, value: value, note: note,
            createdAt: createdAt, editedAt: editedAt, previousLabel: previousLabel, student: student?.syncID
        )
    }

    static func makeEmpty(syncID: String) -> StudentObservation? {
        UUID(syncID: syncID).map { StudentObservation(id: $0, subject: "", kind: .note, scale: .sevenStep, student: nil) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        subject = payload.subject
        date = payload.date
        slotIndex = payload.slotIndex
        kindRaw = payload.kindRaw
        scaleRaw = payload.scaleRaw
        value = payload.value
        note = payload.note
        createdAt = payload.createdAt
        editedAt = payload.editedAt
        previousLabel = payload.previousLabel
        student = references.find(payload.student)
    }
}

extension Absence: SyncCodable {
    struct Payload: Codable {
        var subject: String
        var day: Date
        var slotIndex: Int
        var kindRaw: String
        var arrivedAt: Date?
        var createdAt: Date
        var student: String?
    }

    var payload: Payload {
        Payload(
            subject: subject, day: day, slotIndex: slotIndex, kindRaw: kindRaw, arrivedAt: arrivedAt, createdAt: createdAt,
            student: student?.syncID
        )
    }

    static func makeEmpty(syncID: String) -> Absence? {
        UUID(syncID: syncID).map { Absence(id: $0, subject: "", day: .now, slotIndex: 0, kind: .absent, student: nil) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        subject = payload.subject
        day = payload.day
        slotIndex = payload.slotIndex
        kindRaw = payload.kindRaw
        arrivedAt = payload.arrivedAt
        createdAt = payload.createdAt
        student = references.find(payload.student)
    }
}

extension AssessmentResult: SyncCodable {
    struct Payload: Codable {
        var grade: String
        var rawPoints: Double?
        var isMissing: Bool
        var note: String
        var editedAt: Date?
        var previousGrade: String
        var assessment: String?
        var student: String?
    }

    var payload: Payload {
        Payload(
            grade: grade, rawPoints: rawPoints, isMissing: isMissing, note: note, editedAt: editedAt,
            previousGrade: previousGrade, assessment: assessment?.syncID, student: student?.syncID
        )
    }

    static func makeEmpty(syncID: String) -> AssessmentResult? {
        UUID(syncID: syncID).map { AssessmentResult(id: $0, assessment: nil, student: nil) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        grade = payload.grade
        rawPoints = payload.rawPoints
        isMissing = payload.isMissing
        note = payload.note
        editedAt = payload.editedAt
        previousGrade = payload.previousGrade
        assessment = references.find(payload.assessment)
        student = references.find(payload.student)
    }
}

extension PeriodGrade: SyncCodable {
    struct Payload: Codable {
        var subject: String
        var schoolYear: String
        var periodRaw: String
        var scopeRaw: String
        var grade: String
        var editedAt: Date?
        var previousGrade: String
        var student: String?
    }

    var payload: Payload {
        Payload(
            subject: subject, schoolYear: schoolYear, periodRaw: periodRaw, scopeRaw: scopeRaw, grade: grade, editedAt: editedAt,
            previousGrade: previousGrade, student: student?.syncID
        )
    }

    static func makeEmpty(syncID: String) -> PeriodGrade? {
        UUID(syncID: syncID).map {
            PeriodGrade(id: $0, subject: "", schoolYear: "", period: .half1, scope: .total, grade: "", student: nil)
        }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        subject = payload.subject
        schoolYear = payload.schoolYear
        periodRaw = payload.periodRaw
        scopeRaw = payload.scopeRaw
        grade = payload.grade
        editedAt = payload.editedAt
        previousGrade = payload.previousGrade
        student = references.find(payload.student)
    }
}
