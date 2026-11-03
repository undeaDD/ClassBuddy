import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Schülerakte: Stufen, Skalen, Beobachtungen, Fehlzeiten")
struct StudentRecordTests {
    init() {
        AppLanguage.current = .german
    }

    private static func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, StudentObservation.self, Absence.self, SubjectSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test("Stufe aus Klassenbezeichnung und Schulform")
    func stage() {
        #expect(SchoolStage.detect(className: "2a", schoolType: nil) == .primary)
        #expect(SchoolStage.detect(className: "7b", schoolType: .grammar) == .secondary)
        #expect(SchoolStage.detect(className: "Q1", schoolType: .grammar) == .upper)
        #expect(SchoolStage.detect(className: "EF", schoolType: nil) == .upper)
        #expect(SchoolStage.detect(className: "12", schoolType: nil) == .upper)
        #expect(SchoolStage.detect(className: "Bären", schoolType: .primary) == .primary)
        #expect(SchoolStage.isEarlyPrimary(className: "1c"))
        #expect(!SchoolStage.isEarlyPrimary(className: "3a"))
    }

    @Test("Vorgaben je Stufe")
    func defaults() {
        #expect(RecordSettings.defaults(className: "1a", schoolType: nil).scale == .smileys)
        #expect(RecordSettings.defaults(className: "1a", schoolType: nil).gradeSystem == .none)
        #expect(RecordSettings.defaults(className: "4a", schoolType: nil).scale == .threeStep)
        #expect(RecordSettings.defaults(className: "7b", schoolType: nil).scale == .sevenStep)
        #expect(RecordSettings.defaults(className: "Q2", schoolType: nil).gradeSystem == .points)
    }

    @Test("Bewertung: Vorgabe der Stufe, Wahl der Schule je Stufe, eigene Bewertung der Klasse")
    func settingsPerStageAndClass() throws {
        let context = try Self.context()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik", "Deutsch"])
        let upperClass = SchoolClass(shortName: "Q1")
        context.insert(schoolClass)
        context.insert(upperClass)
        var school = SchoolSettings.Values()
        school.schoolType = .grammar
        #expect(schoolClass.recordSettings(school: school).scale == .sevenStep)
        #expect(upperClass.recordSettings(school: school).gradeSystem == .points)

        // Schule: Sek. I mit Daumen, Oberstufe bleibt bei der Vorgabe.
        school.recordChoices[SchoolStage.secondary.rawValue] = RecordChoice(scale: .thumbs, gradeSystem: .grades, hasWrittenWork: true)
        #expect(schoolClass.recordSettings(school: school).scale == .thumbs)
        #expect(upperClass.recordSettings(school: school).scale == .sevenStep)

        // Klasse: eigene Bewertung, entfernen führt zurück zur Vorgabe der Schule.
        schoolClass.setRecordOverride(RecordChoice(scale: .counter, gradeSystem: .none, hasWrittenWork: false), in: context)
        try context.save()
        #expect(schoolClass.recordSettings(school: school).scale == .counter)
        schoolClass.setRecordOverride(nil, in: context)
        try context.save()
        #expect(schoolClass.recordSettings(school: school).scale == .thumbs)
        #expect(SchoolStage.stages(of: .grammar) == [.secondary, .upper])
    }

    @Test("Übernahme: genutzte Skala wird eigene Bewertung der Klasse, alte Einstellungen je Fach verschwinden")
    func migrateUsedScale() throws {
        let context = try Self.context()
        var school = SchoolSettings.Values()
        school.schoolType = .grammar
        let thumbsClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        let defaultClass = SchoolClass(shortName: "8a", subjects: ["Deutsch"])
        context.insert(thumbsClass)
        context.insert(defaultClass)
        let emma = Student(firstName: "Emma", lastName: "S", schoolClass: thumbsClass)
        let ben = Student(firstName: "Ben", lastName: "A", schoolClass: defaultClass)
        context.insert(emma)
        context.insert(ben)
        context.insert(StudentObservation(subject: "Mathematik", kind: .rating, scale: .thumbs, value: 1, student: emma))
        context.insert(StudentObservation(subject: "Deutsch", kind: .rating, scale: .sevenStep, value: 2, student: ben))
        context.insert(SubjectSettings(
            subject: "Mathematik", scale: .thumbs, gradeSystem: .points, hasWrittenWork: false, schoolClass: thumbsClass
        ))
        try context.save()

        SubjectSettings.migrate(school: school, in: context)
        #expect(thumbsClass.recordOverride == RecordChoice(scale: .thumbs, gradeSystem: .points, hasWrittenWork: false))
        #expect(defaultClass.recordOverride == nil)
        #expect(thumbsClass.subjectSettings.allSatisfy { $0.subject.isEmpty })
    }

    @Test("Skalen: Beschriftung und Ton")
    func scales() {
        #expect(ObservationScale.sevenStep.label(for: -3) == "− − −")
        #expect(ObservationScale.sevenStep.label(for: 2) == "+ +")
        #expect(ObservationScale.threeStep.options.count == 3)
        #expect(ObservationScale.tone(of: -1) == .negative)
        #expect(ObservationScale.tone(of: 0) == .neutral)
    }

    @Test("Nachträgliche Änderung wird mit dem ursprünglichen Wert vermerkt")
    func editMarker() throws {
        let context = try Self.context()
        let student = Student(firstName: "Emma", lastName: "S")
        context.insert(student)
        let observation = StudentObservation(subject: "Mathematik", kind: .rating, scale: .sevenStep, value: 1, student: student)
        context.insert(observation)
        observation.update(kind: .rating, scale: .sevenStep, value: 1, note: "nur Notiz", date: observation.date)
        #expect(observation.editedAt == nil)
        observation.update(kind: .rating, scale: .sevenStep, value: 2, note: "", date: observation.date)
        observation.update(kind: .rating, scale: .sevenStep, value: 3, note: "", date: observation.date)
        #expect(observation.editedAt != nil)
        #expect(observation.previousLabel == "+")
        #expect(observation.label == "+ + +")
    }

    @Test("Abwesend und verspätet: umschalten, Uhrzeit, Minuten")
    func absences() throws {
        let context = try Self.context()
        let student = Student(firstName: "Tim", lastName: "N")
        context.insert(student)
        let day = Calendar.school.startOfDay(for: .now)
        let lesson = LessonContext(day: day, slotIndex: 0, subject: "Mathematik")
        student.toggleAbsent(in: lesson, context: context)
        #expect(student.absence(in: lesson)?.kind == .absent)

        let arrival = try #require(Calendar.school.date(byAdding: .minute, value: 8 * 60 + 12, to: day))
        student.toggleLate(in: lesson, at: arrival, context: context)
        let late = try #require(student.absence(in: lesson))
        #expect(late.kind == .late)
        #expect(late.arrivedAt == arrival)
        let slots = [LessonSlot(index: 0, start: 8 * 60, end: 8 * 60 + 45)]
        #expect(late.lateMinutes(slots: slots) == 12)

        student.toggleLate(in: lesson, context: context)
        try context.save()
        #expect(student.absence(in: lesson) == nil)
    }

    @Test("Seit wie vielen Stunden ohne Beobachtung")
    func coverage() {
        let now = Date.now
        let starts = (1...5).map { now.addingTimeInterval(Double(-$0) * 86_400) }
        #expect(ObservationCoverage.lessonsWithout(lastObservation: nil, since: .distantPast, lessonStarts: starts) == 5)
        let last = now.addingTimeInterval(-2.5 * 86_400)
        #expect(ObservationCoverage.lessonsWithout(lastObservation: last, since: .distantPast, lessonStarts: starts) == 2)
        let created = now.addingTimeInterval(-1.5 * 86_400)
        #expect(ObservationCoverage.lessonsWithout(lastObservation: nil, since: created, lessonStarts: starts) == 1)
    }

    @Test("Excel-Export und -Import behalten Beobachtungen, Fehlzeiten und Einstellungen")
    func backupRoundTrip() throws {
        let context = try Self.context()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        context.insert(schoolClass)
        let student = Student(firstName: "Emma", lastName: "S", schoolClass: schoolClass)
        context.insert(student)
        context.insert(StudentObservation(
            subject: "Mathematik", slotIndex: 2, kind: .rating, scale: .sevenStep, value: 2, student: student
        ))
        context.insert(Absence(subject: "Mathematik", day: .now, slotIndex: 2, kind: .late, arrivedAt: .now, student: student))
        schoolClass.setRecordOverride(RecordChoice(scale: .counter, gradeSystem: .grades, hasWrittenWork: true), in: context)
        try context.save()

        let data = try Backup.export(
            context: context, settings: SchoolSettings.Values(), appearance: .system, funStats: [:]
        )
        let result = try Backup.import(data, context: context, currentSettings: SchoolSettings.Values())
        #expect(result.summary.observations == 1)

        let imported = try #require(try context.fetch(FetchDescriptor<Student>()).first)
        #expect(imported.observations.first?.label == "+ +")
        #expect(imported.observations.first?.slotIndex == 2)
        #expect(imported.absences.first?.kind == .late)
        #expect(imported.schoolClass?.recordSettings(school: SchoolSettings.Values()).scale == .counter)
    }
}
