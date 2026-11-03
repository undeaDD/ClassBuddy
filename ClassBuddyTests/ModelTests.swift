import Foundation
import SwiftData
import Testing
@testable import ClassBuddy

@Suite("Modelle")
struct ModelTests {
    /// Erwartete Texte sind deutsch – unabhängig von der Sprache des Simulators.
    init() {
        AppLanguage.current = .german
    }

    // MARK: Schüler

    @Test("Initialen und voller Name")
    func studentNames() {
        let student = Student(firstName: "Emma", lastName: "Schneider")
        #expect(student.initials == "ES")
        #expect(student.fullName == "Emma Schneider")
        #expect(Student(firstName: "Emma", lastName: "").fullName == "Emma")
    }

    @Test("Abschnittsbuchstabe: Umlaute und Akzente, Nicht-Buchstaben unter #", arguments: [
        ("Ölaf", "O"), ("émile", "E"), ("zoe", "Z"), ("1A", "#"), ("", "#"),
    ])
    func sectionLetter(firstName: String, expected: String) {
        #expect(Student(firstName: firstName, lastName: "").sectionLetter == expected)
    }

    @Test("Sortierung der Schülerliste: Nachname, Geschlecht, Geburtstag")
    func studentSorting() {
        let calendar = Calendar(identifier: .gregorian)
        let emma = Student(firstName: "Emma", lastName: "Zander",
                           birthday: calendar.date(from: DateComponents(year: 2014, month: 3, day: 9)), gender: .female)
        let ben = Student(firstName: "Ben", lastName: "Adler",
                          birthday: calendar.date(from: DateComponents(year: 2013, month: 3, day: 2)), gender: .male)
        let lea = Student(firstName: "Lea", lastName: "Adler")
        let students = [emma, ben, lea]
        let byLastName = StudentSort.lastName.sections(for: students)
        #expect(byLastName.map(\.title) == ["A", "Z"])
        #expect(byLastName[0].students.map(\.firstName) == ["Ben", "Lea"])
        #expect(StudentSort.gender.sections(for: students).map(\.title) == ["Weiblich", "Männlich", "Ohne Angabe"])
        let byBirthday = StudentSort.birthday.sections(for: students)
        #expect(byBirthday.map(\.title) == ["März", "Ohne Geburtstag"])
        #expect(byBirthday[0].students.map(\.firstName) == ["Ben", "Emma"])
    }

    // MARK: Sync-Grundlage

    @Test("Sichern stempelt lastModified, Löschen hinterlässt einen DeletedRecord")
    @MainActor
    func syncTracking() throws {
        SyncTracking.start()
        let container = try ModelContainer(
            for: SchoolClass.self, Student.self, DeletedRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = container.mainContext
        let student = Student(firstName: "Emma", lastName: "Schneider")
        context.insert(student)
        #expect(student.lastModified == .distantPast)
        let before = Date.now
        try context.save()
        #expect(student.lastModified >= before)

        let id = student.id.uuidString
        context.delete(student)
        try context.save()
        let deleted = try context.fetch(FetchDescriptor<DeletedRecord>())
        #expect(deleted.map(\.recordType) == ["Student"])
        #expect(deleted.map(\.recordID) == [id])
    }

    @Test("Alter aus dem Geburtstag")
    func age() throws {
        let birthday = try #require(Calendar.school.date(byAdding: .year, value: -12, to: .now))
        #expect(Student(firstName: "A", lastName: "B", birthday: birthday).age == 12)
        #expect(Student(firstName: "A", lastName: "B").age == nil)
    }

    @Test("Geschlechtssymbole werden als Text (nicht als Emoji) dargestellt")
    func genderSymbols() {
        for gender in Gender.allCases {
            #expect(gender.symbol.unicodeScalars.last == "\u{FE0E}")
        }
    }

    // MARK: Klassen

    @Test("Klassen-Titel und Detailzeile")
    func classLabels() {
        let schoolClass = SchoolClass(shortName: "7b", subjects: ["Mathe", "Physik"], schoolYear: "2026/27")
        #expect(schoolClass.title == "Klasse 7b")
        #expect(schoolClass.detailLine == "Mathe, Physik · 2026/27")
        #expect(SchoolClass(shortName: "Q1", subjects: [], schoolYear: "").detailLine.isEmpty)
    }

    @Test("Aktuelles Schuljahr im Format JJJJ/JJ")
    func currentSchoolYear() throws {
        let year = SchoolClass.currentSchoolYear
        #expect(year.wholeMatch(of: /\d{4}\/\d{2}/) != nil)
        let start = try #require(Int(year.prefix(4)))
        #expect(String(start + 1).suffix(2) == year.suffix(2))
    }

    @Test("Schüler werden nach Nachname, dann Vorname sortiert")
    func sortedStudents() {
        let schoolClass = SchoolClass(shortName: "7b")
        schoolClass.students = [
            Student(firstName: "Mia", lastName: "Weber"),
            Student(firstName: "Anna", lastName: "Becker"),
            Student(firstName: "Ben", lastName: "Becker"),
        ]
        #expect(schoolClass.sortedStudents.map(\.fullName) == ["Anna Becker", "Ben Becker", "Mia Weber"])
    }

    // MARK: Kacheln

    @Test("Kurzbefehl-URL kodiert Leerzeichen, Umlaute und &", arguments: [
        ("Unterricht beginnt", "shortcuts://run-shortcut?name=Unterricht%20beginnt"),
        ("Mathe & Physik", "shortcuts://run-shortcut?name=Mathe%20%26%20Physik"),
        ("Pause=Ruhe+", "shortcuts://run-shortcut?name=Pause%3DRuhe%2B"),
        ("Übung", "shortcuts://run-shortcut?name=%C3%9Cbung"),
    ])
    func shortcutURL(name: String, expected: String) {
        #expect(DashboardLink.shortcutURL(named: name)?.absoluteString == expected)
    }

    @Test("Kachel-Ziele und Detailzeilen")
    func linkTargets() {
        let website = DashboardLink(title: "", kind: .website, location: "https://schule.de/plan", schoolClass: nil)
        #expect(website.detail == "schule.de")
        #expect(!website.kind.isStoredFile)

        let file = DashboardLink(title: "", kind: .file, location: "ABC/Blatt.pdf", schoolClass: nil)
        #expect(file.detail == "Blatt.pdf")
        #expect(file.url?.lastPathComponent == "Blatt.pdf")
        #expect(file.kind.isStoredFile)

        let shortcut = DashboardLink(title: "", kind: .shortcut, location: "Timer", schoolClass: nil)
        #expect(shortcut.url?.scheme == "shortcuts")
        #expect(!shortcut.kind.isStoredFile)
        #expect(shortcut.cardID == "link.\(shortcut.id.uuidString)")
    }
}
