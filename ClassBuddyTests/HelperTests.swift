import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import ClassBuddy

/// Navigation, Titel der Auswahllisten, Snapshots und kleine Helfer, die sonst nur Views benutzen.
@Suite("Navigation und Helfer")
@MainActor
struct HelperTests {
    init() {
        AppLanguage.current = .german
    }

    private static func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, Holiday.self, Checklist.self, ChecklistCheck.self, Room.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Montag, 5. Oktober 2026, um `hour`:`minute`.
    private static func monday(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.school.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute))!
    }

    // MARK: Navigation

    @Test("AppModel: Tabs öffnen, Ziele merken, Stacks zurücksetzen")
    func navigation() throws {
        let app = AppModel()
        app.selectedTab = .dashboard

        let before = app.stackID(for: .calendar)
        app.resetStack(of: .calendar)
        #expect(app.stackID(for: .calendar) == before + 1)

        let checklistID = UUID()
        app.openChecklist(checklistID)
        #expect(app.selectedTab == .checklists)
        #expect(app.checklistToOpen == checklistID)
        // Verlassen eines Tabs setzt dessen Stack zurück.
        let checklistsStack = app.stackID(for: .checklists)

        app.openBoard(subject: "Mathematik")
        #expect(app.selectedTab == .board)
        #expect(app.boardSubject == "Mathematik")
        #expect(app.stackID(for: .checklists) == checklistsStack + 1)

        let classID = UUID()
        app.openCalendar(focusing: classID, at: Self.monday(10, 30))
        #expect(app.selectedTab == .calendar)
        #expect(app.calendarFocusClassID == classID)
        #expect(app.calendarDate == Calendar.school.startOfDay(for: Self.monday(10)))

        app.openRooms(isPhone: true)
        #expect(app.isRoomsSheetPresented)
        app.openRooms(isPhone: false)
        #expect(app.selectedTab == .rooms)

        let room = Room(name: "R 204", subtitle: "", category: .classroom)
        app.openSeatingPlan(room: room, schoolClass: nil, subject: "")
        #expect(app.seatingPlan?.room.name == "R 204")
        #expect(app.seatingPlan?.subject == nil)
    }

    // MARK: Titel

    @Test("Auswahllisten haben Titel")
    func titles() {
        #expect(SchoolType.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(SchoolStage.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(ObservationScale.allCases.allSatisfy { !$0.title.isEmpty && !$0.options.isEmpty })
        #expect(GradeSystem.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(StudentObservation.Kind.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(Absence.Kind.allCases.map(\.title) == ["Abwesend", "Verspätet"])
        #expect(Gender.allCases.allSatisfy { !$0.displayTitle.isEmpty })
        #expect(HolidayImporter.displayName(ofState: "DE-NW") == "Nordrhein-Westfalen")
        #expect(HolidayImporter.displayName(ofState: "XX") == "XX")
        #expect(HolidayImporter.ImportError.badResponse(status: 500, detail: "kaputt").errorDescription?.contains("500: kaputt") == true)
        #expect(ChecklistTemplates.all.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty })
    }

    @Test("Klassenfarben: feste Farben und Rückfall auf Blau")
    func classColors() {
        #expect(Set(ClassColor.allCases.map(\.color.description)).count == ClassColor.allCases.count)
        let schoolClass = SchoolClass(shortName: "7b", color: .green)
        #expect(schoolClass.displayColor == SchoolClass.displayColor(for: ClassColor.green.rawValue))
        #expect(SchoolClass.displayColor(for: "gibt-es-nicht") == ClassColor.blue.color)
    }

    // MARK: Modelle

    @Test("Snapshots enthalten Klasse und Schüler")
    func snapshots() throws {
        let context = try Self.context()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        context.insert(schoolClass)
        let student = Student(firstName: "Anna", lastName: "Berg", schoolClass: schoolClass)
        student.phone = "030 123"
        context.insert(student)
        try context.save()

        let snapshot = schoolClass.snapshot
        #expect(snapshot.shortName == "7b")
        #expect(snapshot.students.map(\.firstName) == ["Anna"])
        #expect(student.snapshot.phone == "030 123")
    }

    @Test("Checklisten: überfällig, Bereich, Kopie, zuletzt bearbeitet")
    func checklists() throws {
        let context = try Self.context()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        context.insert(schoolClass)
        let student = Student(firstName: "Anna", lastName: "Berg", schoolClass: schoolClass)
        context.insert(student)

        let global = Checklist(title: "Bücher", createdAt: Self.monday(8), schoolClass: schoolClass)
        let math = Checklist(title: "Heft", subject: "Mathematik", createdAt: Self.monday(9), schoolClass: schoolClass)
        context.insert(global)
        context.insert(math)
        try context.save()

        #expect(global.scopeTitle == "Alle Fächer")
        #expect(math.scopeTitle == "Mathematik")
        #expect(schoolClass.latestChecklist?.id == math.id)

        #expect(!global.isOverdue)
        global.dueDate = Calendar.school.date(byAdding: .day, value: -2, to: Calendar.school.startOfDay(for: .now))
        #expect(global.isOverdue)
        global.check(student, in: context)
        #expect(!global.isOverdue)

        let copy = global.duplicate(in: context, at: Self.monday(12))
        #expect(copy.title == "Bücher (Kopie)")
        #expect(copy.dueDate == global.dueDate)
        #expect(copy.checks.isEmpty)
    }

    @Test("Laufende und vergangene Stunden einer Klasse")
    func lessonsOfClass() throws {
        let context = try Self.context()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        context.insert(schoolClass)
        // Montag (0), 1. Stunde (08:00–08:45).
        let lesson = Lesson(weekday: 0, slotIndex: 0, subject: "Mathematik", isRecurring: true, date: nil, schoolClass: schoolClass)
        context.insert(lesson)
        try context.save()
        let schedule = LessonSchedule(lessons: [lesson], holidays: [], slots: [LessonSlot(index: 0, start: 8 * 60, end: 8 * 60 + 45)])

        #expect(schedule.currentLesson(classID: schoolClass.id, now: Self.monday(8, 10))?.subject == "Mathematik")
        #expect(schedule.currentLesson(classID: schoolClass.id, now: Self.monday(9)) == nil)
        #expect(schedule.currentLesson(classID: UUID(), now: Self.monday(8, 10)) == nil)

        let starts = schedule.pastLessonStarts(classID: schoolClass.id, subject: "Mathematik", now: Self.monday(9), days: 15)
        #expect(starts == [Self.monday(8), Self.monday(8) - 7 * 86_400, Self.monday(8) - 14 * 86_400])
        #expect(schedule.pastLessonStarts(classID: schoolClass.id, subject: "Deutsch", now: Self.monday(9)).isEmpty)
    }

    // MARK: Widget

    @Test("Widget: laufende Stunde und die folgenden")
    func widgetUpcoming() {
        func lesson(_ start: Date, _ number: Int) -> WidgetSchedule.Lesson {
            WidgetSchedule.Lesson(
                start: start, end: start + 45 * 60, slotNumber: number, className: "7b", subject: "Mathe", room: nil,
                red: 0, green: 0, blue: 1
            )
        }
        let lessons = [lesson(Self.monday(9, 50), 3), lesson(Self.monday(8), 1), lesson(Self.monday(8, 50), 2)]

        let during = WidgetSchedule.upcoming(lessons, at: Self.monday(8, 55))
        #expect(during.current?.slotNumber == 2)
        #expect(during.next.map(\.slotNumber) == [3])

        let between = WidgetSchedule.upcoming(lessons, at: Self.monday(8, 47))
        #expect(between.current == nil)
        #expect(between.next.map(\.slotNumber) == [2, 3])

        let after = WidgetSchedule.upcoming(lessons, at: Self.monday(12))
        #expect(after.current == nil && after.next.isEmpty)
    }

    @Test("Widget: Stunden der nächsten Tage aus dem Stundenplan (ohne beendete, ohne Ferien)")
    func widgetSchedule() throws {
        let context = try Self.context()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["mathe"])
        context.insert(schoolClass)
        let lesson = Lesson(weekday: 0, slotIndex: 0, subject: "mathe", isRecurring: true, date: nil, schoolClass: schoolClass)
        context.insert(lesson)
        // Ferien in der Woche danach.
        let holiday = Holiday(
            id: "herbst", name: "Herbstferien",
            startDate: Self.monday(0) + 7 * 86_400, endDate: Self.monday(0) + 13 * 86_400, isSchoolHoliday: true
        )
        context.insert(holiday)
        try context.save()
        let slots = [LessonSlot(index: 0, start: 8 * 60, end: 8 * 60 + 45)]
        let schedule = LessonSchedule(lessons: [lesson], holidays: [holiday], slots: slots)

        let lessons = WidgetScheduleSync.upcoming(in: schedule, slots: slots, from: Self.monday(8, 30), days: 21)
        // Heute (läuft noch) und in drei Wochen; die Woche dazwischen sind Ferien.
        #expect(lessons.map(\.start) == [Self.monday(8), Self.monday(8) + 14 * 86_400])
        #expect(lessons.first?.className == "7b")
        #expect(lessons.first?.slotNumber == 1)
        #expect(WidgetScheduleSync.upcoming(in: schedule, slots: slots, from: Self.monday(9), days: 7).isEmpty)
    }
}
