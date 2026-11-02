import Foundation
import SwiftData

// Austauschformat je Eintragstyp: alle gespeicherten Felder, Beziehungen als `syncID`. Neue Felder an einem Modell
// gehören auch hierher, sonst kommen sie auf anderen Geräten nicht an. Felder nur ergänzen (mit Standardwert beim
// Lesen), nie umbenennen: Pakete gelten nur zwischen gleicher App-Version, aber die Regel hält Altes lesbar.

/// Eintrag, den `SyncEngine` als Paket schreiben und wieder übernehmen kann.
protocol SyncCodable: SyncRecord, PersistentModel {
    associatedtype Payload: Codable
    var payload: Payload { get }
    /// Leerer Eintrag mit dieser ID, danach füllt `apply` alle Felder.
    static func makeEmpty(syncID: String) -> Self?
    func apply(_ payload: Payload, references: SyncReferences)
}

/// Bereits vorhandene oder im selben Paket angelegte Einträge, nach Typ und `syncID`.
@MainActor
final class SyncReferences {
    private var records: [String: any PersistentModel] = [:]

    func register(_ record: some SyncRecord & PersistentModel) {
        records[Self.key(type(of: record).syncRecordType, record.syncID)] = record
    }

    func find<T: SyncRecord & PersistentModel>(_ id: String?) -> T? {
        id.flatMap { records[Self.key(T.syncRecordType, $0)] as? T }
    }

    private static func key(_ type: String, _ id: String) -> String { "\(type)/\(id)" }
}

extension UUID {
    /// ID eines Eintrags aus einem Sync-Paket.
    init?(syncID: String) { self.init(uuidString: syncID) }
}

extension SchoolClass: SyncCodable {
    struct Payload: Codable {
        var shortName: String
        var subjects: [String]
        var schoolYear: String
        var colorRaw: String
        var levelRaw: String?
        var createdAt: Date
        var dashboardOrder: [String]
        var dashboardHidden: [String]
        var dashboardKnownCards: [String]
        var dashboardRemoved: [String]
        var lastGroupsData: Data?
        var quickNote: String
        var quickNoteEditedAt: Date?
    }

    var payload: Payload {
        Payload(
            shortName: shortName, subjects: subjects, schoolYear: schoolYear, colorRaw: colorRaw, levelRaw: levelRaw,
            createdAt: createdAt, dashboardOrder: dashboardOrder, dashboardHidden: dashboardHidden,
            dashboardKnownCards: dashboardKnownCards, dashboardRemoved: dashboardRemoved, lastGroupsData: lastGroupsData,
            quickNote: quickNote, quickNoteEditedAt: quickNoteEditedAt
        )
    }

    static func makeEmpty(syncID: String) -> SchoolClass? {
        UUID(syncID: syncID).map { SchoolClass(id: $0, shortName: "") }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        shortName = payload.shortName
        subjects = payload.subjects
        schoolYear = payload.schoolYear
        colorRaw = payload.colorRaw
        levelRaw = payload.levelRaw
        createdAt = payload.createdAt
        dashboardOrder = payload.dashboardOrder
        dashboardHidden = payload.dashboardHidden
        dashboardKnownCards = payload.dashboardKnownCards
        dashboardRemoved = payload.dashboardRemoved
        lastGroupsData = payload.lastGroupsData
        quickNote = payload.quickNote
        quickNoteEditedAt = payload.quickNoteEditedAt
    }
}

extension Room: SyncCodable {
    struct Payload: Codable {
        var name: String
        var subtitle: String
        var categoryRaw: String
        var assignments: [String]
        var equipment: [String]
        var sortIndex: Int
        var createdAt: Date
        var updatedAt: Date
    }

    var payload: Payload {
        Payload(
            name: name, subtitle: subtitle, categoryRaw: categoryRaw, assignments: assignments, equipment: equipment,
            sortIndex: sortIndex, createdAt: createdAt, updatedAt: updatedAt
        )
    }

    static func makeEmpty(syncID: String) -> Room? {
        UUID(syncID: syncID).map { Room(id: $0, name: "") }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        name = payload.name
        subtitle = payload.subtitle
        categoryRaw = payload.categoryRaw
        assignments = payload.assignments
        equipment = payload.equipment
        sortIndex = payload.sortIndex
        createdAt = payload.createdAt
        updatedAt = payload.updatedAt
    }
}

extension Student: SyncCodable {
    struct Payload: Codable {
        var firstName: String
        var lastName: String
        var birthday: Date?
        var genderRaw: String?
        var notes: String
        var phone: String
        var email: String
        var otherContact: String
        var photo: Data?
        var createdAt: Date
        var schoolClass: String?
    }

    var payload: Payload {
        Payload(
            firstName: firstName, lastName: lastName, birthday: birthday, genderRaw: genderRaw, notes: notes, phone: phone,
            email: email, otherContact: otherContact, photo: photo, createdAt: createdAt, schoolClass: schoolClass?.syncID
        )
    }

    static func makeEmpty(syncID: String) -> Student? {
        UUID(syncID: syncID).map { Student(id: $0, firstName: "", lastName: "") }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        firstName = payload.firstName
        lastName = payload.lastName
        birthday = payload.birthday
        genderRaw = payload.genderRaw
        notes = payload.notes
        phone = payload.phone
        email = payload.email
        otherContact = payload.otherContact
        photo = payload.photo
        createdAt = payload.createdAt
        schoolClass = references.find(payload.schoolClass)
    }
}

extension RoomElement: SyncCodable {
    struct Payload: Codable {
        var kindRaw: String
        var points: [GridPoint]
        var order: Int
        var room: String?
    }

    var payload: Payload { Payload(kindRaw: kindRaw, points: points, order: order, room: room?.syncID) }

    static func makeEmpty(syncID: String) -> RoomElement? {
        UUID(syncID: syncID).map { RoomElement(id: $0, kind: .table, points: []) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        kindRaw = payload.kindRaw
        points = payload.points
        order = payload.order
        room = references.find(payload.room)
    }
}

extension Lesson: SyncCodable {
    struct Payload: Codable {
        var weekday: Int
        var slotIndex: Int
        var subject: String
        var isRecurring: Bool
        var weekInterval: Int
        var slotCount: Int
        var date: Date?
        var createdAt: Date
        var schoolClass: String?
        var room: String?
    }

    var payload: Payload {
        Payload(
            weekday: weekday, slotIndex: slotIndex, subject: subject, isRecurring: isRecurring, weekInterval: weekInterval,
            slotCount: slotCount, date: date, createdAt: createdAt, schoolClass: schoolClass?.syncID, room: room?.syncID
        )
    }

    static func makeEmpty(syncID: String) -> Lesson? {
        UUID(syncID: syncID).map { Lesson(id: $0, weekday: 0, slotIndex: 0, subject: "", isRecurring: true, date: nil, schoolClass: nil) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        weekday = payload.weekday
        slotIndex = payload.slotIndex
        subject = payload.subject
        isRecurring = payload.isRecurring
        weekInterval = payload.weekInterval
        slotCount = payload.slotCount
        date = payload.date
        createdAt = payload.createdAt
        schoolClass = references.find(payload.schoolClass)
        room = references.find(payload.room)
    }
}

extension CalendarEntry: SyncCodable {
    struct Payload: Codable {
        var title: String
        var start: Date
        var end: Date
        var notes: String
        var schoolClass: String?
        var room: String?
    }

    var payload: Payload {
        Payload(title: title, start: start, end: end, notes: notes, schoolClass: schoolClass?.syncID, room: room?.syncID)
    }

    static func makeEmpty(syncID: String) -> CalendarEntry? {
        UUID(syncID: syncID).map { CalendarEntry(id: $0, title: "", start: .now, end: .now) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        title = payload.title
        start = payload.start
        end = payload.end
        notes = payload.notes
        schoolClass = references.find(payload.schoolClass)
        room = references.find(payload.room)
    }
}

extension Holiday: SyncCodable {
    struct Payload: Codable {
        var name: String
        var startDate: Date
        var endDate: Date
        var isSchoolHoliday: Bool
    }

    var payload: Payload { Payload(name: name, startDate: startDate, endDate: endDate, isSchoolHoliday: isSchoolHoliday) }

    static func makeEmpty(syncID: String) -> Holiday? {
        Holiday(id: syncID, name: "", startDate: .now, endDate: .now, isSchoolHoliday: false)
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        name = payload.name
        startDate = payload.startDate
        endDate = payload.endDate
        isSchoolHoliday = payload.isSchoolHoliday
    }
}

extension DashboardLink: SyncCodable {
    struct Payload: Codable {
        var title: String
        var kindRaw: String
        var location: String
        var scriptState: String
        var createdAt: Date
        var schoolClass: String?
    }

    var payload: Payload {
        Payload(
            title: title, kindRaw: kindRaw, location: location, scriptState: scriptState, createdAt: createdAt,
            schoolClass: schoolClass?.syncID
        )
    }

    static func makeEmpty(syncID: String) -> DashboardLink? {
        UUID(syncID: syncID).map { DashboardLink(id: $0, title: "", kind: .website, location: "", schoolClass: nil) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        title = payload.title
        kindRaw = payload.kindRaw
        location = payload.location
        scriptState = payload.scriptState
        createdAt = payload.createdAt
        schoolClass = references.find(payload.schoolClass)
    }
}

extension BoardPhoto: SyncCodable {
    struct Payload: Codable {
        var subject: String
        var takenAt: Date
        var imageData: Data
        var schoolClass: String?
    }

    var payload: Payload { Payload(subject: subject, takenAt: takenAt, imageData: imageData, schoolClass: schoolClass?.syncID) }

    static func makeEmpty(syncID: String) -> BoardPhoto? {
        UUID(syncID: syncID).map { BoardPhoto(id: $0, subject: "", imageData: Data()) }
    }

    func apply(_ payload: Payload, references: SyncReferences) {
        subject = payload.subject
        takenAt = payload.takenAt
        imageData = payload.imageData
        schoolClass = references.find(payload.schoolClass)
    }
}
