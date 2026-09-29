import SwiftData
import SwiftUI

// TEMPORÄR (PoC): ergänzt einmalig das Geschlecht bei den Dummy-Schülern und legt
// eine Person mit „divers“ an. Wird mit dem nächsten Build wieder entfernt –
// die Daten bleiben erhalten.
enum DummyStudentsSeed {
    private static let doneKey = "poc.dummyStudentsGenderSeeded"

    private static let female: Set<String> = ["Emma", "Mia", "Hanna", "Lina", "Sophie", "Marie"]
    private static let male: Set<String> = ["Leon", "Noah", "Paul", "Elias", "Finn", "Jonas"]

    static func applyIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: doneKey),
              let students = try? context.fetch(FetchDescriptor<Student>())
        else { return }

        for student in students where student.gender == nil {
            if female.contains(student.firstName) { student.gender = .female }
            if male.contains(student.firstName) { student.gender = .male }
        }

        // Eine Person „divers“ in die Klasse der Dummy-Schüler.
        if let dummyClass = students.first(where: { $0.firstName == "Emma" && $0.lastName == "Schneider" })?.schoolClass,
           !students.contains(where: { $0.firstName == "Alex" && $0.lastName == "Neumann" }) {
            let birthday = Calendar.current.date(byAdding: DateComponents(year: -12, day: -140), to: .now)
            context.insert(Student(
                firstName: "Alex", lastName: "Neumann", birthday: birthday,
                gender: .diverse, schoolClass: dummyClass
            ))
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
