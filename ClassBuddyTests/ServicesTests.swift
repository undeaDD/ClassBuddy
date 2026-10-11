import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import ClassBuddy

/// Stundenplan-Nachschlagen, Kauf-Simulation, Bilder, Dateien der Kacheln und kleine App-Hilfen.
@Suite("App-Dienste: Stundenplan, Käufe, Bilder, Dateien, Hilfen")
@MainActor
struct ServicesTests {
    init() {
        AppLanguage.current = .german
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Calendar.school.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, Lesson.self, Holiday.self, DashboardLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static let slots = [
        LessonSlot(index: 0, start: 8 * 60, end: 8 * 60 + 45),
        LessonSlot(index: 1, start: 8 * 60 + 50, end: 9 * 60 + 35),
    ]

    /// Einfarbiges Testbild in fester Pixelgröße.
    private static func image(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    // MARK: Stundenplan

    @Test("Stundenplan: Einzelstunde vor wöchentlicher, Ferien streichen nur wöchentliche, erste Dopplung gewinnt")
    func lessonLookup() throws {
        let context = try Self.makeContext()
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathematik", "Physik"])
        context.insert(schoolClass)
        let monday = Self.date(2026, 10, 12)
        let holidayMonday = Self.date(2026, 10, 19)
        func lesson(_ slot: Int, _ subject: String, on date: Date? = nil) -> Lesson {
            Lesson(weekday: 0, slotIndex: slot, subject: subject, isRecurring: date == nil, date: date, schoolClass: schoolClass)
        }
        // Montags 1. Stunde wöchentlich (doppelt eingetragen), dazu Einzelstunden am 12. und in den Ferien.
        let lessons = [
            lesson(0, "Mathematik"),
            lesson(0, "Deutsch"),
            lesson(0, "Physik", on: monday.addingTimeInterval(3600)),
            lesson(1, "Mathematik", on: holidayMonday),
        ]
        lessons.forEach(context.insert)
        let holiday = Holiday(
            id: "h", name: "Herbstferien", startDate: holidayMonday, endDate: Self.date(2026, 10, 23), isSchoolHoliday: true
        )
        let schedule = LessonSchedule(lessons: lessons, holidays: [holiday], slots: Self.slots)

        #expect(schedule.lesson(on: monday, slotIndex: 0)?.subject == "Physik")
        #expect(schedule.lesson(on: Self.date(2026, 10, 26), slotIndex: 0)?.subject == "Mathematik")
        #expect(schedule.lesson(on: Self.date(2026, 10, 13), slotIndex: 0) == nil)
        #expect(schedule.lesson(on: holidayMonday, slotIndex: 0) == nil)
        #expect(schedule.lesson(on: holidayMonday, slotIndex: 1)?.subject == "Mathematik")
        #expect(schedule.holiday(on: Self.date(2026, 10, 21, 12))?.name == "Herbstferien")
        #expect(schedule.holiday(on: monday) == nil)

        // Montag 9:00: Physik (1. Stunde) ist vorbei, die nächste Stunde der Klasse liegt in den Ferien (Einzelstunde).
        let now = Self.date(2026, 10, 12, 9)
        #expect(BoardSubject.current(for: schoolClass, schedule: schedule, now: now) == "Physik")
        let next = schedule.nextLesson(forClass: schoolClass.id, after: now)
        #expect(next?.lesson.subject == "Mathematik")
        #expect(next?.slot.index == 1)
        #expect(next.map { Calendar.school.isDate($0.start, inSameDayAs: holidayMonday) } == true)

        let week = WeeklyWorkload.compute(schedule: schedule, now: now)
        #expect(week.totalMinutes == 45)
        #expect(week.doneMinutes == 45)
        #expect(WeeklyWorkload.hours(90) == "1,5 h")
    }

    // MARK: Käufe (Debug-Simulation)

    @Test("Kauf-Simulation: Testen und Kaufen schalten nur die Simulation weiter, Zustand bleibt gespeichert")
    func purchaseSimulation() async {
        let store = PurchaseStore()
        let previous = store.simulatedStatus
        defer { store.simulatedStatus = previous }

        store.simulatedStatus = .notStarted
        #expect(store.status == .notStarted)
        #expect(await store.startTrial() == .success)
        #expect(store.status == .trial(daysLeft: PurchaseStatus.trialDays))
        #expect(await store.buyFullVersion() == .success)
        #expect(store.status == .purchased)
        // Neue Instanz liest die gespeicherte Simulation.
        #expect(PurchaseStore().simulatedStatus == .purchased)

        for status in PurchaseStatus.debugCases {
            #expect(PurchaseStatus(debugKey: status.debugKey) == status)
        }
        #expect(PurchaseStatus(debugKey: "unbekannt") == nil)
        #expect(PurchaseStatus.loading.debugKey == "loading")
    }

    // MARK: Übersicht

    @Test("Übersicht: Geschlechterverteilung und relative Tage")
    func dashboardTexts() throws {
        let context = try Self.makeContext()
        #expect(DashboardText.genderBreakdown([]) == "Noch keine Schüler")
        let students = [
            Student(firstName: "A", lastName: "A", gender: .female),
            Student(firstName: "B", lastName: "B", gender: .female),
            Student(firstName: "C", lastName: "C", gender: .male),
            Student(firstName: "D", lastName: "D"),
        ]
        students.forEach(context.insert)
        let text = DashboardText.genderBreakdown(students)
        #expect(text.contains("50 %"))
        #expect(text.contains("25 %"))
        #expect(text.contains("? 25 %"))
        #expect(text.components(separatedBy: " · ").count == 3)

        #expect(DashboardText.relativeDay(.now) == "Heute")
        #expect(DashboardText.relativeDay(.now.addingTimeInterval(86_400)) == "Morgen")
        let later = Self.date(2030, 1, 15)
        #expect(DashboardText.relativeDay(later) == later.appDate)

        let sizes = CardSizes()
        sizes.values["tile"] = CGSize(width: 10, height: 20)
        #expect(sizes.values["tile"]?.height == 20)
    }

    @Test("Bild-Cache der Übersicht: Vorschau einmal erzeugen, danach aus dem Speicher")
    func dashboardImageCache() async throws {
        let url = URL.temporaryDirectory.appending(path: "cache-\(UUID().uuidString).png")
        try #require(Self.image(width: 1200, height: 600).pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(DashboardImageCache.cachedThumbnail(url) == nil)
        let thumbnail = try #require(await DashboardImageCache.thumbnail(for: url))
        #expect(max(thumbnail.size.width, thumbnail.size.height) <= 900)
        #expect(DashboardImageCache.cachedThumbnail(url) === thumbnail)
    }

    // MARK: Bilder

    @Test("Fotos: Tafelbild und Schülerfoto verkleinern, Vorschau erzeugen, kaputte Daten ablehnen")
    func photos() throws {
        let board = try #require(BoardPhotoImage.prepare(Self.image(width: 800, height: 400), maxPixel: 200))
        let boardImage = try #require(UIImage(data: board))
        #expect(max(boardImage.size.width * boardImage.scale, boardImage.size.height * boardImage.scale) <= 200)
        let thumbnail = try #require(BoardPhotoImage.thumbnail(from: board, maxPixelSize: 50))
        #expect(max(thumbnail.size.width, thumbnail.size.height) <= 50)
        #expect(BoardPhotoImage.thumbnail(from: Data("kein Bild".utf8), maxPixelSize: 50) == nil)

        let source = try #require(Self.image(width: 600, height: 600).pngData())
        let student = try #require(StudentPhoto.prepare(source, maxPixel: 64))
        #expect(StudentPhoto.image(from: student) != nil)
        #expect(StudentPhoto.prepare(Data("kein Bild".utf8)) == nil)
    }

    // MARK: Dateien der Kacheln

    @Test("Kachel-Dateien: Daten und Dateien kopieren, beim Entfernen wieder löschen")
    func linkFiles() throws {
        let path = try LinkFileStore.importData(Data("Hallo".utf8), filename: "notiz.txt")
        let stored = LinkFileStore.directory.appending(path: path)
        #expect(try String(contentsOf: stored, encoding: .utf8) == "Hallo")

        let source = URL.temporaryDirectory.appending(path: "blatt-\(UUID().uuidString).txt")
        try Data("Arbeitsblatt".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let copied = try LinkFileStore.importFile(from: source)
        #expect(copied.hasSuffix(source.lastPathComponent))
        #expect(FileManager.default.fileExists(atPath: LinkFileStore.directory.appending(path: copied).path(percentEncoded: false)))

        for location in [path, copied] {
            let link = DashboardLink(title: "Datei", kind: .file, location: location, schoolClass: nil)
            LinkFileStore.removeFile(of: link)
            #expect(!FileManager.default.fileExists(atPath: LinkFileStore.directory.appending(path: location).path(percentEncoded: false)))
        }
        // Websites liegen nicht im App-Container: nichts zu löschen.
        LinkFileStore.removeFile(of: DashboardLink(title: "Web", kind: .website, location: "https://example.org", schoolClass: nil))
    }

    // MARK: Hilfen

    @Test("Gerät und Installation: Kurzform des Modells, Installationsdatum")
    func installInfo() {
        #expect(InstallInfo.shortModel("iPhone15,2") == "p15,2")
        #expect(InstallInfo.shortModel("iPad13,4") == "t13,4")
        #expect(InstallInfo.shortModel("arm64") == "arm64")
        #expect(!InstallInfo.deviceModel.isEmpty)
        #expect(InstallInfo.shortDeviceModel == InstallInfo.shortModel(InstallInfo.deviceModel))
        #expect(InstallInfo.installDate.map { $0 <= .now } != false)
    }

    @Test("Haptik: nur mit eingeschalteter Einstellung, Aktion läuft immer")
    func haptics() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AppPreference.hapticFeedback)
        defer { defaults.set(previous, forKey: AppPreference.hapticFeedback) }

        for isEnabled in [false, true] {
            defaults.set(isEnabled, forKey: AppPreference.hapticFeedback)
            #expect(Haptics.isEnabled == isEnabled)
            var runs = 0
            Haptics.tapping { runs += 1 }()
            Haptics.selection()
            Haptics.notify(.success)
            #expect(runs == 1)
        }
    }

    @Test("Sicherheit: Privatsphäre-Modus ohne Abfrage einschalten, Sperre nur mit App-Sperre")
    func security() async {
        let defaults = UserDefaults.standard
        let previousPrivacy = defaults.object(forKey: "security.privacyMode")
        defer { defaults.set(previousPrivacy, forKey: "security.privacyMode") }

        defaults.set(false, forKey: "security.privacyMode")
        let security = AppSecurity()
        #expect(!security.isPrivacyModeOn)
        await security.togglePrivacyMode()
        #expect(security.isPrivacyModeOn)
        security.enablePrivacyMode()
        #expect(security.isPrivacyModeOn)
        #expect(defaults.bool(forKey: "security.privacyMode"))

        security.lock()
        #expect(security.isLocked == security.isAppLockEnabled || security.isLocked)
    }

    @Test("Sprache und Datumsformate in der App-Sprache")
    func languageAndDates() {
        #expect(AppLanguage.allCases.allSatisfy { !$0.title.isEmpty && !$0.backupTitle.isEmpty })
        let date = Self.date(2026, 10, 12, 9, 5)
        #expect(date.appFormatted(.dateTime.year()).contains("2026"))
        #expect(!date.appFormatted(date: .numeric, time: .shortened).isEmpty)
    }

    @Test("Wetter: Regen erkennen (Buddy hält dann still)")
    func rainyWeather() {
        #expect(WeatherCondition(code: 61).isRainy)
        #expect(WeatherCondition(code: 95).isRainy)
        #expect(!WeatherCondition(code: 0).isRainy)
        #expect(!WeatherCondition(code: 71).isRainy)
        #expect(WeatherCondition(apple: .rain).isRainy)
        #expect(!WeatherCondition(apple: .clear).isRainy)
    }

    @Test("Bedienelemente mit Icons lassen sich bauen (Label, Button, Löschen-Button)")
    func iconControls() {
        _ = Label("Löschen", icon: .trash)
        _ = Label(String("Löschen"), icon: .trash)
        _ = Button("Löschen", icon: .trash) {}
        _ = Button(String("Löschen"), icon: .trash) {}
        _ = Button("Löschen", destructiveIcon: .trash) {}
    }
}
