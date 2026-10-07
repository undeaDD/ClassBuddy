import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

/// Kacheln der Übersicht: Katalog, Anwesenheit, Timer/Stoppuhr, Schnellnotiz, Kontakt-Links und Widget-Datei.
@Suite("Übersicht und Kacheln")
@MainActor
struct DashboardTests {
    init() {
        AppLanguage.current = .german
    }

    @Test("Jede eingebaute Kachel hat Titel, Beschreibung, Symbol und Vorschau; neue starten ausgeblendet")
    func catalog() {
        for card in DashboardBuiltInCard.allCases {
            #expect(!card.title.isEmpty, "\(card)")
            #expect(!card.summary.isEmpty, "\(card)")
            #expect(!card.previewValue.value.isEmpty, "\(card)")
        }
        #expect(Set(DashboardBuiltInCard.allCases.map(\.rawValue)).count == DashboardBuiltInCard.allCases.count)
        #expect(!DashboardBuiltInCard.students.isHiddenByDefault)
        #expect([DashboardBuiltInCard.holidays, .attendance, .quickNote, .secretariat].allSatisfy { $0.isHiddenByDefault })
        #expect(DashboardBuiltInCard.timer.title == "Timer & Stoppuhr")

        let templates = DashboardBuiltInCard.allCases.map(CardTemplate.builtIn) + CardTemplate.reusable + [.request]
        #expect(Set(templates.map(\.id)).count == templates.count)
        #expect(templates.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty })
        #expect(CardTemplate.builtIn(.weather).builtInCard == .weather)
        #expect(CardTemplate.website.builtInCard == nil)
        #expect(CardTemplate.reusable.allSatisfy { $0.isReusable })
    }

    @Test("Anwesenheit: je Schüler zählt der schwerste Eintrag des Tages")
    func attendance() throws {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Absence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik"])
        context.insert(schoolClass)
        let students = ["Anna", "Ben", "Cem", "Dana"].map { Student(firstName: $0, lastName: "X", schoolClass: schoolClass) }
        students.forEach(context.insert)
        let today = Calendar.school.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!
        let yesterday = Calendar.school.date(byAdding: .day, value: -1, to: today)!
        // Anna: verspätet und später abwesend → abwesend. Ben: verspätet. Cem: gestern abwesend (zählt nicht).
        context.insert(Absence(subject: "Mathematik", day: today, slotIndex: 0, kind: .late, student: students[0]))
        context.insert(Absence(subject: "Mathematik", day: today, slotIndex: 2, kind: .absent, student: students[0]))
        context.insert(Absence(subject: "Mathematik", day: today, slotIndex: 1, kind: .late, student: students[1]))
        context.insert(Absence(subject: "Mathematik", day: yesterday, slotIndex: 1, kind: .absent, student: students[2]))
        try context.save()

        let summary = AttendanceCard.summary(of: students, on: today)
        #expect(summary == AttendanceCard.Summary(absent: 1, late: 1, present: 3))
        #expect(AttendanceCard.summary(of: [], on: today) == AttendanceCard.Summary())
    }

    @Test("Timer und Stoppuhr: Zeitformat, Start und Stopp schließen sich aus")
    func timerAndStopwatch() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ClassTimer.remainingText(until: start + 125, now: start) == "02:05")
        #expect(ClassTimer.remainingText(until: start + 3_725, now: start) == "1:02:05")
        #expect(ClassTimer.remainingText(until: start, now: start + 10) == "00:00")
        #expect(ClassTimer.elapsedText(since: start, now: start + 59.9) == "00:59")
        #expect(ClassTimer.elapsedText(since: start, now: start + 7_200) == "2:00:00")

        let timer = ClassTimer()
        timer.stop()
        timer.stopStopwatch()
        timer.startStopwatch()
        #expect(timer.stopwatchStart != nil)
        timer.start(minutes: 5)
        #expect(timer.isRunning)
        #expect(timer.stopwatchStart == nil)
        timer.extend(byMinutes: 1)
        #expect(timer.durationMinutes == 6)
        timer.startStopwatch()
        #expect(!timer.isRunning)
        timer.stopStopwatch()
        #expect(timer.stopwatchStart == nil)
    }

    @Test("Schnellnotiz: Bearbeitet-Text")
    func quickNoteEdited() {
        #expect(QuickNoteCard.editedText(.now).hasPrefix("Heute um"))
        #expect(QuickNoteCard.editedText(Date(timeIntervalSince1970: 1_000_000_000)).hasPrefix("Am "))
    }

    @Test("Kontakt-Links: Telefon nur mit Ziffern, Mail nur mit @ und ohne Leerzeichen")
    func contactLinks() {
        #expect(ContactURL.phone("+49 (0) 30 / 123-45")?.absoluteString == "tel:+4903012345")
        #expect(ContactURL.phone("12") == nil)
        #expect(ContactURL.phone("keine Nummer") == nil)
        #expect(ContactURL.mail("anna.berg+schule@example.de")?.absoluteString == "mailto:anna.berg+schule@example.de")
        #expect(ContactURL.mail("anna berg@example.de") == nil)
        #expect(ContactURL.mail("anna.example.de") == nil)
    }

    @Test("Data Protection: Umstellung läuft genau einmal")
    func dataProtectionMigration() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.dataProtection.\(UUID().uuidString)"))
        DataProtectionMigration.runIfNeeded(defaults: defaults)
        #expect(defaults.bool(forKey: "dataProtection.completeMigrated.v1"))
        // Zweiter Aufruf: nichts mehr zu tun (kein Absturz, Merker bleibt).
        DataProtectionMigration.runIfNeeded(defaults: defaults)
        #expect(defaults.bool(forKey: "dataProtection.completeMigrated.v1"))
    }

    @Test(
        "Widget-Datei: Speichern und Laden",
        .enabled(if: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSchedule.appGroup) != nil)
    )
    func widgetFile() throws {
        let saved = WidgetSchedule.load()
        defer { try? WidgetSchedule.save(saved) }
        let lesson = WidgetSchedule.Lesson(
            start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_002_700), slotNumber: 1,
            className: "7b", subject: "Mathematik", room: "R 204", red: 0.1, green: 0.2, blue: 0.3
        )
        try WidgetSchedule.save([lesson])
        #expect(WidgetSchedule.load() == [lesson])
    }
}
