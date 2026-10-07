import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Notenübersicht und Exporte")
@MainActor
struct RecordExportTests {
    init() {
        AppLanguage.current = .german
    }

    private struct Fixture {
        let context: ModelContext
        let schoolClass: SchoolClass
        let emma: Student
        let leon: Student
        let assessment: Assessment
    }

    private static func fixture() throws -> Fixture {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, StudentObservation.self, Absence.self, Assessment.self, AssessmentResult.self,
            PeriodGrade.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"], schoolYear: "2026/27")
        context.insert(schoolClass)
        let emma = Student(firstName: "Emma", lastName: "Schneider", schoolClass: schoolClass)
        let leon = Student(firstName: "Leon", lastName: "Fischer", schoolClass: schoolClass)
        [emma, leon].forEach(context.insert)
        let assessment = Assessment(
            subject: "Mathematik", title: "KA 1", typeName: "Klassenarbeit", area: .written, schoolClass: schoolClass
        )
        context.insert(assessment)
        assessment.ensureResult(for: emma, in: context).setGrade("2−")
        assessment.ensureResult(for: leon, in: context).isMissing = true
        let day = Calendar.school.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9)) ?? .now
        context.insert(StudentObservation(subject: "Mathematik", date: day, kind: .rating, scale: .sevenStep, value: 2, student: emma))
        context.insert(StudentObservation(
            subject: "Mathematik", date: day.addingTimeInterval(600), kind: .rating, scale: .sevenStep, value: -1, student: emma
        ))
        context.insert(Absence(subject: "Mathematik", day: day, slotIndex: 1, kind: .absent, student: leon))
        context.insert(Absence(subject: "Mathematik", day: day, slotIndex: 2, kind: .late, arrivedAt: day, student: leon))
        emma.setPeriodGrade("2", for: PeriodGradeKey(subject: "Mathematik", schoolYear: "2026/27", period: .quarter1), in: context)
        try context.save()
        return Fixture(context: context, schoolClass: schoolClass, emma: emma, leon: leon, assessment: assessment)
    }

    @Test("Spalten und Zellen der Übersicht")
    func tableCells() throws {
        let fixture = try Self.fixture()
        let table = GradeOverviewTable(schoolClass: fixture.schoolClass, subject: "Mathematik")
        let column = { (id: String) in try #require(table.columns.first { $0.id == id }) }
        #expect(table.text(fixture.emma, try column("obs.count")) == "2")
        #expect(table.text(fixture.emma, try column("obs.recent")) == "− · + +")
        #expect(table.text(fixture.emma, try column("assessment.\(fixture.assessment.id)")) == "2−")
        #expect(table.text(fixture.leon, try column("assessment.\(fixture.assessment.id)")) == "fehlt")
        #expect(table.text(fixture.leon, try column("absences")) == "1 / 1")
        #expect(table.text(fixture.emma, try column("period.quarter1")) == "2")
        #expect(table.header.first == "Schüler")
        #expect(table.rows.count == 2)
    }

    @Test("Ausgeblendete Spaltengruppen fehlen")
    func hiddenGroups() throws {
        let fixture = try Self.fixture()
        let table = GradeOverviewTable(schoolClass: fixture.schoolClass, subject: "Mathematik", groups: [.grades])
        #expect(table.columns.allSatisfy { $0.group == .grades })
        #expect(table.columns.count == GradePeriod.allCases.count)
    }

    @Test("PDFs und Excel werden erzeugt")
    func exports() throws {
        let fixture = try Self.fixture()
        let table = GradeOverviewTable(schoolClass: fixture.schoolClass, subject: "Mathematik")
        let pdf = try #require(table.pdfFile())
        #expect(try Data(contentsOf: pdf).count > 1000)
        let participation = try #require(table.participationPDF())
        #expect(try Data(contentsOf: participation).count > 1000)
        let excel = try #require(table.excelFile())
        let workbook = try XLSX.read(try Data(contentsOf: excel))
        #expect(workbook.values.first?.count == 3)
        let student = try #require(StudentRecordPDF.make(student: fixture.emma, subject: "Mathematik"))
        #expect(try Data(contentsOf: student).count > 1000)
    }
}
