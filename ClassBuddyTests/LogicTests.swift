import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import ClassBuddy

@Suite("Übersicht-Logik & Hilfen")
struct LogicTests {
    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        Calendar.school.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: Geburtstage

    @Test("Geburtstage: sortiert, heute zählt mit, gestern ist nächstes Jahr")
    func upcomingBirthdays() {
        let today = Self.date(2026, 9, 29, 10)
        let students = [
            Student(firstName: "Gestern", lastName: "", birthday: Self.date(2014, 9, 28)),
            Student(firstName: "Heute", lastName: "", birthday: Self.date(2014, 9, 29)),
            Student(firstName: "Übermorgen", lastName: "", birthday: Self.date(2013, 10, 1)),
            Student(firstName: "Ohne", lastName: ""),
        ]
        let upcoming = Birthdays.upcoming(in: students, today: today)

        #expect(upcoming.map(\.student.firstName) == ["Heute", "Übermorgen", "Gestern"])
        #expect(upcoming.map(\.daysUntil) == [0, 2, 364])
        #expect(upcoming.map(\.turningAge) == [12, 13, 13])
        #expect(Birthdays.detail(for: upcoming) == "Heute · wird 12")
    }

    @Test("Geburtstage: morgen, mehrere am selben Tag, leere Klasse")
    func birthdayDetails() {
        let today = Self.date(2026, 9, 29)
        let twins = [
            Student(firstName: "A", lastName: "", birthday: Self.date(2015, 9, 30)),
            Student(firstName: "B", lastName: "", birthday: Self.date(2015, 9, 30)),
        ]
        #expect(Birthdays.detail(for: Birthdays.upcoming(in: twins, today: today)) == "Morgen · wird 11 · +1")
        #expect(Birthdays.detail(for: []) == "Keine Geburtstage eingetragen")
    }

    @Test("Geburtstag am 29. Februar wird in Nicht-Schaltjahren am 1. März gefeiert")
    func leapDayBirthday() throws {
        let student = Student(firstName: "Leap", lastName: "", birthday: Self.date(2012, 2, 29))
        let next = try #require(Birthdays.upcoming(in: [student], today: Self.date(2026, 9, 29)).first)
        #expect(next.date == Self.date(2027, 3, 1))
        #expect(next.turningAge == 15)
    }

    // MARK: Aktuelle Stunde

    private static func schedule(withLesson: Bool) throws -> LessonSchedule {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self, DashboardLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        if withLesson {
            let schoolClass = SchoolClass(shortName: "7b")
            context.insert(schoolClass)
            context.insert(Lesson(weekday: 0, slotIndex: 0, subject: "Mathe", isRecurring: true, date: nil, schoolClass: schoolClass))
        }
        return LessonSchedule(lessons: try context.fetch(FetchDescriptor<Lesson>()), holidays: [], slots: SchoolSettings.Values().slots)
    }

    @Test("Laufende Stunde: Restzeit wird aufgerundet, Klasse und Fach im Detail")
    func runningLesson() throws {
        // Montag 08:22:10 → 1. Stunde bis 08:45 → 22 min 50 s → „23 min“
        let state = LessonProgress.state(
            schedule: try Self.schedule(withLesson: true), visibleWeekdays: Array(0..<5), now: Self.date(2026, 9, 28, 8, 22, 10)
        )
        #expect(state.value == "23 min")
        #expect(state.detail == "1. Stunde · 7b · Mathe")
    }

    @Test("Freie Stunde, Pause mit nächster Stunde, Wochenende")
    func otherStates() throws {
        let schedule = try Self.schedule(withLesson: false)
        let weekdays = Array(0..<5)

        let free = LessonProgress.state(schedule: schedule, visibleWeekdays: weekdays, now: Self.date(2026, 9, 28, 8, 50))
        #expect(free.detail == "2. Stunde · frei")

        let pause = LessonProgress.state(schedule: schedule, visibleWeekdays: weekdays, now: Self.date(2026, 9, 28, 9, 35))
        #expect(pause.value == "Keine aktive Stunde")
        #expect(pause.detail == "Nächste: 3. Stunde um 09:50")

        let saturday = LessonProgress.state(schedule: schedule, visibleWeekdays: weekdays, now: Self.date(2026, 10, 3, 9, 0))
        #expect(saturday.detail == "Heute kein Unterricht mehr")
    }

    @Test("Lange Stunden werden in Stunden und Minuten angezeigt")
    func longLesson() {
        var values = SchoolSettings.Values()
        values.lessonDuration = 90
        values.breaks = []
        let schedule = LessonSchedule(lessons: [], holidays: [], slots: values.slots)

        let state = LessonProgress.state(schedule: schedule, visibleWeekdays: Array(0..<5), now: Self.date(2026, 9, 28, 8, 0))
        #expect(state.value == "1 h 30 min")
    }

    // MARK: Wochenstunden

    @Test("Wochenstunden: erledigt / gesamt, laufende Stunde anteilig, Ferien zählen nicht")
    func weeklyWorkload() throws {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, CalendarEntry.self, Holiday.self, DashboardLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let schoolClass = SchoolClass(shortName: "7b")
        context.insert(schoolClass)
        // Montag 1.+2. Stunde, Mittwoch 1. Stunde (je 45 min)
        for (weekday, slot) in [(0, 0), (0, 1), (2, 0)] {
            context.insert(Lesson(weekday: weekday, slotIndex: slot, subject: "", isRecurring: true, date: nil, schoolClass: schoolClass))
        }
        let lessons = try context.fetch(FetchDescriptor<Lesson>())
        let slots = SchoolSettings.Values().slots

        // Montag, 28.09.2026, 09:00: 1. Stunde fertig (45), 2. Stunde seit 15 min
        let monday = WeeklyWorkload.compute(
            schedule: LessonSchedule(lessons: lessons, holidays: [], slots: slots), now: Self.date(2026, 9, 28, 9, 0)
        )
        #expect(monday == WeeklyWorkload.Result(doneMinutes: 60, totalMinutes: 135))

        // Sonntag danach: alles erledigt
        let sunday = WeeklyWorkload.compute(
            schedule: LessonSchedule(lessons: lessons, holidays: [], slots: slots), now: Self.date(2026, 10, 4, 12, 0)
        )
        #expect(sunday.fraction == 1)

        // Mittwoch ist Feiertag → nur die zwei Montagsstunden
        let holiday = Holiday(
            id: "h", name: "Test", startDate: Self.date(2026, 9, 30), endDate: Self.date(2026, 9, 30), isSchoolHoliday: false
        )
        let withHoliday = WeeklyWorkload.compute(
            schedule: LessonSchedule(lessons: lessons, holidays: [holiday], slots: slots), now: Self.date(2026, 9, 28, 7, 0)
        )
        #expect(withHoliday == WeeklyWorkload.Result(doneMinutes: 0, totalMinutes: 90))
    }

    @Test("Stundenangabe im deutschen Format", arguments: [(0, "0 h"), (45, "0,8 h"), (90, "1,5 h"), (24 * 60, "24 h")])
    func hoursFormat(minutes: Int, expected: String) {
        #expect(WeeklyWorkload.hours(minutes) == expected)
    }

    @Test("Ohne Stunden ist der Fortschritt 0")
    func emptyWorkload() {
        #expect(WeeklyWorkload.Result(doneMinutes: 0, totalMinutes: 0).fraction == 0)
    }

    // MARK: Timer & Installation

    @Test("Timer-Restzeit", arguments: [(0.0, "00:00"), (59.2, "01:00"), (125, "02:05"), (3_725, "1:02:05")])
    func timerText(seconds: Double, expected: String) {
        let now = Self.date(2026, 9, 29, 10)
        #expect(ClassTimer.remainingText(until: now.addingTimeInterval(seconds), now: now) == expected)
    }

    nonisolated struct InstallCase: Sendable {
        var keys: Set<String> = []
        var debug = false
        var profile = false
        var environment: String?
        let expected: InstallInfo.Method
    }

    @Test("Installationsweg erkennen", arguments: [
        InstallCase(keys: ["ALTDeviceID"], debug: true, profile: true, expected: .sideloaded),
        InstallCase(debug: true, profile: true, expected: .xcode),
        InstallCase(profile: true, expected: .developer),
        InstallCase(environment: "Sandbox", expected: .testFlight),
        InstallCase(environment: "Production", expected: .appStore),
    ])
    func installMethod(test: InstallCase) {
        let method = InstallInfo.method(
            infoKeys: test.keys, isDebugBuild: test.debug, hasProvisioningProfile: test.profile, storeEnvironment: test.environment
        )
        #expect(method == test.expected)
    }

    @Test("Gerätemodell und OS-Version sind gesetzt")
    func deviceInfo() {
        #expect(InstallInfo.deviceModel.hasPrefix("iPad"))
        #expect(InstallInfo.osVersion.contains(UIDevice.current.systemVersion))
    }

    // MARK: Ferien-Import

    @Test("Ferien-API: Datum hin und zurück, ungültige Werte")
    func holidayDates() {
        #expect(HolidayImporter.parseDay("2026-10-17") == Self.date(2026, 10, 17))
        #expect(HolidayImporter.parseDay("2026-10") == nil)
        #expect(HolidayImporter.parseDay("abc") == nil)
        #expect(HolidayImporter.dayString(Self.date(2026, 3, 5, 23, 59)) == "2026-03-05")
    }

    @Test("Alle 16 Bundesländer mit eindeutigem Code")
    func federalStates() {
        let codes = HolidayImporter.federalStates.map(\.code)
        #expect(codes.count == 16)
        #expect(Set(codes).count == 16)
        #expect(codes.allSatisfy { $0.hasPrefix("DE-") })
    }

    // MARK: Favicons

    @Test("Favicons: Apple-Touch-Icon zuerst, relative Pfade, Groß-/Kleinschreibung, einfache Anführungszeichen")
    func faviconLinks() throws {
        let html = """
            <html><head>
            <link rel="stylesheet" href="/style.css">
            <LINK REL='icon' HREF='/favicon-32.png'>
            <link href="https://cdn.schule.de/touch.png" rel="apple-touch-icon" sizes="180x180">
            <link rel="shortcut icon" href="img/icon.ico">
            </head></html>
            """
        let base = try #require(URL(string: "https://schule.de/start/index.html"))
        let links = FaviconStore.iconLinks(in: html, baseURL: base).map(\.absoluteString)

        #expect(links == [
            "https://cdn.schule.de/touch.png",
            "https://schule.de/favicon-32.png",
            "https://schule.de/start/img/icon.ico",
        ])
    }

    // MARK: Mail, Farben, Anzeige

    @Test("Mail-Link: Empfänger, kodierter Betreff, Geräte-Infos im Text")
    func mailURL() throws {
        let url = AppInfo.mailURL(subject: "Idee & Wunsch", body: "Hallo")
        let text = url.absoluteString

        #expect(text.hasPrefix("mailto:dominic.drees@live.de?"))
        #expect(text.contains("subject=Idee%20%26%20Wunsch"))
        let body = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value)
        #expect(body.hasPrefix("Hallo"))
        #expect(body.contains("ClassBuddy"))
    }

    @Test("Hex-Farben hin und zurück", arguments: ["#9C6830", "#000000", "#FFFFFF", "#12AB34"])
    func hexRoundTrip(hex: String) throws {
        let color = try #require(Color(hex: hex))
        #expect(color.hexString == hex)
    }

    @Test("Ungültige Hex-Farben", arguments: ["", "#12", "#GGGGGG", "123456789"])
    func invalidHex(hex: String) {
        #expect(Color(hex: hex) == nil)
    }

    @Test("Klassenfarbe beim Import: Name, Hex (normalisiert) oder Blau")
    func sanitizedClassColor() {
        #expect(SchoolClass.sanitizedColorRaw("teal") == "teal")
        #expect(SchoolClass.sanitizedColorRaw(" #abcdef ") == "#ABCDEF")
        #expect(SchoolClass.sanitizedColorRaw("regenbogen") == "blue")
    }

    @Test("Kurzname für Kacheln", arguments: [("Emma", "Schneider", "Emma S."), ("Emma", "", "Emma")])
    func shortName(first: String, last: String, expected: String) {
        #expect(RandomStudentCard.shortName(Student(firstName: first, lastName: last)) == expected)
    }

    @Test("Erscheinungsbild → Fensterstil")
    func appearance() {
        #expect(AppAppearance.system.interfaceStyle == .unspecified)
        #expect(AppAppearance.light.interfaceStyle == .light)
        #expect(AppAppearance.dark.interfaceStyle == .dark)
    }

    @Test("Kachel-Wunsch ist keine hinzufügbare Kachel")
    func requestTemplate() {
        #expect(!CardTemplate.request.isReusable)
        #expect(!CardTemplate.reusable.contains(.request))
    }
}
