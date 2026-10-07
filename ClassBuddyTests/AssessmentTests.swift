import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Leistungen: Notenschlüssel, Notenspiegel, Noten, Excel")
struct AssessmentTests {
    init() {
        AppLanguage.current = .german
    }

    private static func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Assessment.self, AssessmentResult.self, PeriodGrade.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test("Notenschlüssel: Prozent → Punkte nach Abitur-Tabelle, mathematisch gerundet")
    func gradingKey() {
        #expect(GradingKey.points(raw: 50, max: 50) == 15)
        #expect(GradingKey.points(raw: 47.5, max: 50) == 15)
        #expect(GradingKey.points(raw: 47, max: 50) == 14)
        #expect(GradingKey.points(raw: 35, max: 50) == 10)
        #expect(GradingKey.points(raw: 16.5, max: 50) == 3)
        #expect(GradingKey.points(raw: 9, max: 50) == 0)
        #expect(GradingKey.points(raw: 10, max: 0) == nil)
        // 69,5 % → 70 % → 10 Punkte
        #expect(GradingKey.points(raw: 69.5, max: 100) == 10)
    }

    @Test("Punkte → Note mit Tendenz")
    func pointsToGrade() {
        #expect(GradingKey.grade(fromPoints: 15) == "1+")
        #expect(GradingKey.grade(fromPoints: 14) == "1")
        #expect(GradingKey.grade(fromPoints: 13) == "1−")
        #expect(GradingKey.grade(fromPoints: 10) == "2−")
        #expect(GradingKey.grade(fromPoints: 5) == "4")
        #expect(GradingKey.grade(fromPoints: 1) == "5−")
        #expect(GradingKey.grade(fromPoints: 0) == "6")
        #expect(GradingKey.grade(raw: 38, max: 50, system: .grades) == "2")
        #expect(GradingKey.grade(raw: 38, max: 50, system: .points) == "11")
    }

    @Test("Notenspiegel und Durchschnitt einer Arbeit")
    func distribution() {
        let grades = ["2+", "2", "3−", "1", "5"]
        let spiegel = GradeScale.distribution(grades, system: .grades)
        #expect(spiegel.map(\.amount) == [1, 2, 1, 0, 1, 0])
        #expect(GradeScale.average(grades, system: .grades) == 2.6)
        #expect(GradeScale.average(["15", "10", "8"], system: .points) == 11)
        #expect(GradeScale.average([], system: .grades) == nil)
        #expect(GradeScale.values(for: .points).first == "15")
    }

    @Test("Geänderte Note wird mit dem ursprünglichen Wert vermerkt; Note hebt „fehlt“ auf")
    func resultMarker() throws {
        let context = try Self.context()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        context.insert(schoolClass)
        let student = Student(firstName: "Emma", lastName: "S", schoolClass: schoolClass)
        context.insert(student)
        let assessment = Assessment(
            subject: "Mathematik", title: "KA 1", typeName: "Klassenarbeit", area: .written, schoolClass: schoolClass
        )
        context.insert(assessment)
        let result = assessment.ensureResult(for: student, in: context)
        result.isMissing = true
        result.setGrade("3")
        #expect(!result.isMissing)
        #expect(result.editedAt == nil)
        result.setGrade("2−")
        result.setGrade("2")
        #expect(result.previousGrade == "3")
        #expect(result.editedAt != nil)
        try context.save()
        #expect(assessment.grades == ["2"])
        #expect(assessment.ensureResult(for: student, in: context) === result)
    }

    @Test("Selbst eingetragene Noten: setzen, ändern mit Vermerk, löschen")
    func periodGrades() throws {
        let context = try Self.context()
        let student = Student(firstName: "Leon", lastName: "F")
        context.insert(student)
        let key = PeriodGradeKey(subject: "Mathematik", schoolYear: "2026/27", period: .half1)
        student.setPeriodGrade("3", for: key, in: context)
        student.setPeriodGrade("2−", for: key, in: context)
        let grade = try #require(student.periodGrade(key))
        #expect(grade.grade == "2−")
        #expect(grade.previousGrade == "3")
        student.setPeriodGrade("", for: key, in: context)
        try context.save()
        #expect(student.periodGrade(key) == nil)
    }

    @Test("Bereiche je Bundesland, umbenennbar; ohne schriftliche Arbeiten nur sonstige Arten")
    func areasAndTypes() {
        var values = SchoolSettings.Values()
        values.federalState = "DE-BY"
        #expect(values.areaName(.written) == "Große Leistungsnachweise")
        values.areaNames[AssessmentArea.written.rawValue] = "Schulaufgaben"
        #expect(values.areaName(.written) == "Schulaufgaben")
        #expect(values.selectableTypes(hasWrittenWork: false).allSatisfy { $0.area == .other })
        values.assessmentTypes[0].isHidden = true
        #expect(!values.selectableTypes(hasWrittenWork: true).contains { $0.id == values.assessmentTypes[0].id })
    }

    @Test("Excel-Export und -Import behalten Leistungen, Ergebnisse, Noten und Leistungsarten")
    func backupRoundTrip() throws {
        let context = try Self.context()
        let schoolClass = SchoolClass(shortName: "Q1", subjects: ["Informatik"])
        context.insert(schoolClass)
        let student = Student(firstName: "Sara", lastName: "L", schoolClass: schoolClass)
        context.insert(student)
        let assessment = Assessment(
            subject: "Informatik", title: "Klausur 1", typeName: "Klausur", area: .written, maxPoints: 60, schoolClass: schoolClass
        )
        context.insert(assessment)
        let result = assessment.ensureResult(for: student, in: context)
        result.rawPoints = 51
        result.setGrade("12")
        student.setPeriodGrade("11", for: PeriodGradeKey(subject: "Informatik", schoolYear: "2026/27", period: .quarter1), in: context)
        try context.save()

        var settings = SchoolSettings.Values()
        settings.assessmentTypes.append(AssessmentType(name: "Projekt", area: .other))
        settings.areaNames[AssessmentArea.other.rawValue] = "Mitarbeit"
        let data = try Backup.export(context: context, settings: settings, appearance: .system, funStats: [:])
        let imported = try Backup.import(data, context: context, currentSettings: SchoolSettings.Values())

        #expect(imported.summary.assessments == 1)
        #expect(imported.settings.values.assessmentTypes.contains { $0.name == "Projekt" })
        #expect(imported.settings.values.areaNames[AssessmentArea.other.rawValue] == "Mitarbeit")
        let restored = try #require(try context.fetch(FetchDescriptor<Assessment>()).first)
        #expect(restored.maxPoints == 60)
        #expect(restored.results.first?.grade == "12")
        #expect(restored.results.first?.rawPoints == 51)
        let restoredStudent = try #require(try context.fetch(FetchDescriptor<Student>()).first)
        #expect(restoredStudent.periodGrades.first?.grade == "11")
    }
}
