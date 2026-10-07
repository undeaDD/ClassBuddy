import Foundation
import SwiftData

// Schülerakte: Beobachtungen im Unterricht, Fehlzeiten und die Bewertungs-Einstellungen je Klasse + Fach.
// Die App rechnet keine Noten aus – sie sammelt und zeigt nur, was die Lehrkraft einträgt.

// MARK: - Schulform und Stufe

/// Schulform aus den Schuleinstellungen; bestimmt zusammen mit der Klassenbezeichnung die Vorgaben.
nonisolated enum SchoolType: String, Codable, CaseIterable, Identifiable {
    case primary, special, secondaryGeneral, secondaryIntermediate, comprehensive, grammar, vocational

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primary: loc("Grundschule")
        case .special: loc("Förderschule")
        case .secondaryGeneral: loc("Hauptschule")
        case .secondaryIntermediate: loc("Realschule")
        case .comprehensive: loc("Gesamtschule")
        case .grammar: loc("Gymnasium")
        case .vocational: loc("Berufskolleg")
        }
    }
}

/// Stufe einer Klasse: Grundschule, Sekundarstufe I oder Oberstufe.
nonisolated enum SchoolStage: String, Codable, CaseIterable {
    case primary, secondary, upper

    var title: String {
        switch self {
        case .primary: loc("Grundschule")
        case .secondary: loc("Sek. I")
        case .upper: loc("Oberstufe")
        }
    }

    /// Aus der Klassenbezeichnung („2a“, „7b“, „EF“, „Q1“, „11“) und der Schulform.
    static func detect(className: String, schoolType: SchoolType?) -> SchoolStage {
        let name = className.trimmingCharacters(in: .whitespaces).uppercased()
        let upperNames = ["EF", "E1", "E2", "Q1", "Q2", "Q3", "Q4", "J1", "J2", "K1", "K2", "11", "12", "13"]
        if upperNames.contains(where: { name.hasPrefix($0) }) { return schoolType == .primary ? .primary : .upper }
        if let grade = Int(name.prefix { $0.isNumber }) {
            switch grade {
            case 1...4: return .primary
            case 5...10: return schoolType == .primary ? .primary : .secondary
            default: return .upper
            }
        }
        return schoolType == .primary ? .primary : (schoolType == .vocational ? .upper : .secondary)
    }

    /// Jahrgang 1 oder 2 der Grundschule (noch ohne Noten).
    static func isEarlyPrimary(className: String) -> Bool {
        let grade = Int(className.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber })
        return grade == 1 || grade == 2
    }
}

// MARK: - Skalen

/// Skala für Beobachtungen im Unterricht. Der gespeicherte Wert gehört immer zur Skala der Beobachtung.
nonisolated enum ObservationScale: String, Codable, CaseIterable, Identifiable {
    case sevenStep, threeStep, thumbs, counter, smileys

    var id: String { rawValue }

    enum Tone { case negative, neutral, positive }

    struct Option: Hashable {
        let value: Int
        /// Text (Excel, Verlauf, Bedienungshilfen); mit `icon` zeigt die Oberfläche das Icon.
        let label: String
        var icon: AppIcon?
    }

    var title: String {
        switch self {
        case .sevenStep: loc("− − − bis + + + (7 Stufen)")
        case .threeStep: loc("− o +")
        case .thumbs: loc("Daumen hoch / runter")
        case .counter: loc("Beiträge zählen (+1)")
        case .smileys: loc("Smileys")
        }
    }

    var options: [Option] {
        switch self {
        case .sevenStep:
            [(-3, "− − −"), (-2, "− −"), (-1, "−"), (0, "o"), (1, "+"), (2, "+ +"), (3, "+ + +")]
                .map { Option(value: $0, label: $1) }
        case .threeStep: [(-1, "−"), (0, "o"), (1, "+")].map { Option(value: $0, label: $1) }
        case .thumbs:
            [
                Option(value: -1, label: loc("Daumen runter"), icon: .thumbsDown),
                Option(value: 1, label: loc("Daumen hoch"), icon: .thumbsUp),
            ]
        case .counter: [Option(value: 1, label: "+1")]
        case .smileys: [(-1, "🙁"), (0, "😐"), (1, "🙂")].map { Option(value: $0, label: $1) }
        }
    }

    func label(for value: Int) -> String {
        options.first { $0.value == value }?.label ?? "\(value)"
    }

    func icon(for value: Int) -> AppIcon? {
        options.first { $0.value == value }?.icon
    }

    static func tone(of value: Int) -> Tone {
        value < 0 ? .negative : (value > 0 ? .positive : .neutral)
    }
}

/// Notensystem für schriftliche und sonstige Leistungen (Etappe 2).
nonisolated enum GradeSystem: String, Codable, CaseIterable, Identifiable {
    case grades, points, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grades: loc("Noten 1–6 mit Tendenz")
        case .points: loc("Punkte 0–15")
        case .none: loc("Keine Noten")
        }
    }
}

// MARK: - Einstellungen je Klasse + Fach

/// Bewertungs-Einstellungen einer Klasse in einem Fach; ohne Eintrag gelten die Vorgaben der Stufe.
@Model
final class SubjectSettings {
    @Attribute(.unique) var id: UUID
    var subject: String
    var scaleRaw: String
    var gradeSystemRaw: String
    var hasWrittenWork: Bool
    var schoolClass: SchoolClass?

    init(
        id: UUID = UUID(), subject: String, scale: ObservationScale, gradeSystem: GradeSystem, hasWrittenWork: Bool,
        schoolClass: SchoolClass?
    ) {
        self.id = id
        self.subject = subject
        self.scaleRaw = scale.rawValue
        self.gradeSystemRaw = gradeSystem.rawValue
        self.hasWrittenWork = hasWrittenWork
        self.schoolClass = schoolClass
    }

    var scale: ObservationScale {
        get { ObservationScale(rawValue: scaleRaw) ?? .sevenStep }
        set { scaleRaw = newValue.rawValue }
    }

    var gradeSystem: GradeSystem {
        get { GradeSystem(rawValue: gradeSystemRaw) ?? .grades }
        set { gradeSystemRaw = newValue.rawValue }
    }
}

/// Werte der Einstellungen (gespeichert oder Vorgabe).
nonisolated struct RecordSettings: Equatable {
    var scale: ObservationScale
    var gradeSystem: GradeSystem
    var hasWrittenWork: Bool
    var stage: SchoolStage

    /// Vorgaben: Grundschule Smileys (1–2) bzw. − o +, Sek. I 7 Stufen mit Noten, Oberstufe 7 Stufen mit Punkten.
    static func defaults(className: String, schoolType: SchoolType?) -> RecordSettings {
        let stage = SchoolStage.detect(className: className, schoolType: schoolType)
        switch stage {
        case .primary:
            let early = SchoolStage.isEarlyPrimary(className: className)
            return RecordSettings(
                scale: early ? .smileys : .threeStep, gradeSystem: early ? .none : .grades, hasWrittenWork: !early, stage: stage
            )
        case .secondary:
            return RecordSettings(scale: .sevenStep, gradeSystem: .grades, hasWrittenWork: true, stage: stage)
        case .upper:
            return RecordSettings(scale: .sevenStep, gradeSystem: .points, hasWrittenWork: true, stage: stage)
        }
    }
}

extension SchoolClass {
    func recordSettings(for subject: String, schoolType: SchoolType?) -> RecordSettings {
        var values = RecordSettings.defaults(className: shortName, schoolType: schoolType)
        if let stored = subjectSettings.first(where: { $0.subject == subject }) {
            values.scale = stored.scale
            values.gradeSystem = stored.gradeSystem
            values.hasWrittenWork = stored.hasWrittenWork
        }
        return values
    }

    func setRecordSettings(_ values: RecordSettings, for subject: String, in context: ModelContext) {
        if let stored = subjectSettings.first(where: { $0.subject == subject }) {
            stored.scale = values.scale
            stored.gradeSystem = values.gradeSystem
            stored.hasWrittenWork = values.hasWrittenWork
        } else {
            context.insert(SubjectSettings(
                subject: subject, scale: values.scale, gradeSystem: values.gradeSystem,
                hasWrittenWork: values.hasWrittenWork, schoolClass: self
            ))
        }
    }
}

// MARK: - Beobachtungen

/// Eine Beobachtung im Unterricht: Bewertung auf der Skala, ein Ereignis (HA / Material fehlt) oder nur eine Notiz.
@Model
final class StudentObservation {
    enum Kind: String, CaseIterable, Identifiable {
        case rating, homework, material, note

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rating: loc("Bewertung")
            case .homework: loc("Hausaufgabe fehlt")
            case .material: loc("Material fehlt")
            case .note: loc("Notiz")
            }
        }
    }

    @Attribute(.unique) var id: UUID
    var subject: String
    var date: Date
    /// Stunde im Raster (-1 = ohne Stunde).
    var slotIndex: Int
    var kindRaw: String
    var scaleRaw: String
    var value: Int
    var note: String
    var createdAt: Date
    /// Nachträglich geändert: Zeitpunkt und vorheriger Wert (Anzeige „vorher …“).
    var editedAt: Date?
    var previousLabel: String
    var student: Student?

    init(
        id: UUID = UUID(), subject: String, date: Date = .now, slotIndex: Int = -1, kind: Kind, scale: ObservationScale,
        value: Int = 0, note: String = "", createdAt: Date = .now, student: Student?
    ) {
        self.id = id
        self.subject = subject
        self.date = date
        self.slotIndex = slotIndex
        self.kindRaw = kind.rawValue
        self.scaleRaw = scale.rawValue
        self.value = value
        self.note = note
        self.createdAt = createdAt
        self.previousLabel = ""
        self.student = student
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var scale: ObservationScale {
        get { ObservationScale(rawValue: scaleRaw) ?? .sevenStep }
        set { scaleRaw = newValue.rawValue }
    }

    /// Kurzform: Skalenwert, „HA“, „Material“ oder „Notiz“.
    var label: String {
        switch kind {
        case .rating: scale.label(for: value)
        case .homework: loc("HA fehlt")
        case .material: loc("Material fehlt")
        case .note: loc("Notiz")
        }
    }

    /// Änderung festhalten (nur wenn sich Art oder Wert ändern; der ursprüngliche Wert bleibt vermerkt).
    func update(kind: Kind, scale: ObservationScale, value: Int, note: String, date: Date, at now: Date = .now) {
        let oldLabel = label
        let changesRating = kind != self.kind || (kind == .rating && (value != self.value || scale != self.scale))
        self.kind = kind
        self.scale = scale
        self.value = value
        self.note = note
        self.date = date
        if changesRating {
            if previousLabel.isEmpty { previousLabel = oldLabel }
            editedAt = now
        }
    }
}

// MARK: - Fehlzeiten

/// Fehlzeit in einer Stunde: abwesend oder verspätet (mit Uhrzeit des Eintreffens).
@Model
final class Absence {
    enum Kind: String, CaseIterable, Identifiable {
        case absent, late

        var id: String { rawValue }

        var title: String {
            switch self {
            case .absent: loc("Abwesend")
            case .late: loc("Verspätet")
            }
        }
    }

    @Attribute(.unique) var id: UUID
    var subject: String
    /// Tagesbeginn.
    var day: Date
    var slotIndex: Int
    var kindRaw: String
    var arrivedAt: Date?
    var createdAt: Date
    var student: Student?

    init(
        id: UUID = UUID(), subject: String, day: Date, slotIndex: Int, kind: Kind, arrivedAt: Date? = nil,
        createdAt: Date = .now, student: Student?
    ) {
        self.id = id
        self.subject = subject
        self.day = Calendar.school.startOfDay(for: day)
        self.slotIndex = slotIndex
        self.kindRaw = kind.rawValue
        self.arrivedAt = arrivedAt
        self.createdAt = createdAt
        self.student = student
    }

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .absent }
        set { kindRaw = newValue.rawValue }
    }

    /// Minuten nach Stundenbeginn (nur bei „verspätet“).
    func lateMinutes(slots: [LessonSlot]) -> Int? {
        guard kind == .late, let arrivedAt, let slot = slots.first(where: { $0.index == slotIndex }) else { return nil }
        let calendar = Calendar.school
        let minute = calendar.component(.hour, from: arrivedAt) * 60 + calendar.component(.minute, from: arrivedAt)
        return max(0, minute - slot.start)
    }
}

/// Stunde, in der gerade erfasst wird (Sitzplan): Tag, Stunde im Raster, Fach.
nonisolated struct LessonContext: Equatable {
    var day: Date
    var slotIndex: Int
    var subject: String
}

extension Student {
    func absence(in lesson: LessonContext) -> Absence? {
        absences.first { $0.slotIndex == lesson.slotIndex && Calendar.school.isDate($0.day, inSameDayAs: lesson.day) }
    }

    func observations(in subject: String) -> [StudentObservation] {
        observations.filter { $0.subject == subject }.sorted { $0.date > $1.date }
    }

    /// Abwesend ↔ nicht abwesend; aus „verspätet“ wird „abwesend“.
    func toggleAbsent(in lesson: LessonContext, context: ModelContext) {
        if let existing = absence(in: lesson) {
            if existing.kind == .absent {
                context.delete(existing)
            } else {
                existing.kind = .absent
                existing.arrivedAt = nil
            }
        } else {
            context.insert(Absence(subject: lesson.subject, day: lesson.day, slotIndex: lesson.slotIndex, kind: .absent, student: self))
        }
    }

    /// Verspätet mit der aktuellen Uhrzeit (auch aus „abwesend“); nochmal tippen nimmt es zurück.
    func toggleLate(in lesson: LessonContext, at now: Date = .now, context: ModelContext) {
        if let existing = absence(in: lesson) {
            if existing.kind == .late {
                context.delete(existing)
            } else {
                existing.kind = .late
                existing.arrivedAt = now
            }
        } else {
            context.insert(Absence(
                subject: lesson.subject, day: lesson.day, slotIndex: lesson.slotIndex, kind: .late, arrivedAt: now, student: self
            ))
        }
    }
}

// MARK: - Wer wurde lange nicht beobachtet?

nonisolated enum ObservationCoverage {
    /// Ab so vielen Stunden ohne Beobachtung wird der Tisch gestrichelt.
    static let threshold = 3

    /// Anzahl vergangener Stunden (Beginn ≤ jetzt) nach der letzten Beobachtung bzw. nach `since`.
    static func lessonsWithout(lastObservation: Date?, since: Date, lessonStarts: [Date]) -> Int {
        let reference = max(lastObservation ?? since, since)
        return lessonStarts.filter { $0 > reference }.count
    }
}

extension LessonSchedule {
    /// Beginn der vergangenen Stunden einer Klasse in einem Fach (höchstens `days` Tage zurück).
    func pastLessonStarts(classID: UUID, subject: String, now: Date = .now, days: Int = 56) -> [Date] {
        let calendar = Calendar.school
        let today = calendar.startOfDay(for: now)
        var starts: [Date] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for slot in slots {
                guard let lesson = lesson(on: day, slotIndex: slot.index),
                      lesson.schoolClass?.id == classID, lesson.subject == subject,
                      let start = calendar.date(byAdding: .minute, value: slot.start, to: day), start <= now
                else { continue }
                starts.append(start)
            }
        }
        return starts
    }

    /// Laufende Stunde einer Klasse (Fach und Stunde im Raster).
    func currentLesson(classID: UUID, now: Date = .now) -> (slotIndex: Int, subject: String)? {
        let calendar = Calendar.school
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard let slot = slots.first(where: { $0.start <= minute && minute < $0.end }),
              let lesson = lesson(on: now, slotIndex: slot.index), lesson.schoolClass?.id == classID
        else { return nil }
        return (slot.index, lesson.subject)
    }
}
