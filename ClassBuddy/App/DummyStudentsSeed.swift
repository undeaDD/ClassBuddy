import SwiftData
import SwiftUI

// TEMPORÄR (PoC): legt einmalig Dummy-Schüler in der aktuell ausgewählten Klasse an.
// Wird mit dem nächsten Build wieder entfernt – die angelegten Daten bleiben erhalten.
enum DummyStudentsSeed {
    private static let doneKey = "poc.dummyStudentsSeeded"

    private static let names: [(String, String, Int)] = [
        ("Emma", "Schneider", 12), ("Leon", "Fischer", 13), ("Mia", "Weber", 12),
        ("Noah", "Meyer", 12), ("Hanna", "Wagner", 13), ("Paul", "Becker", 12),
        ("Lina", "Hoffmann", 12), ("Elias", "Schulz", 13), ("Sophie", "Koch", 12),
        ("Finn", "Richter", 12), ("Marie", "Klein", 13), ("Jonas", "Wolf", 12),
    ]

    static func seedIfNeeded(selectedClassID: UUID?, context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: doneKey), let selectedClassID else { return }
        let descriptor = FetchDescriptor<SchoolClass>(predicate: #Predicate { $0.id == selectedClassID })
        guard let schoolClass = try? context.fetch(descriptor).first else { return }

        let calendar = Calendar.current
        for (index, (first, last, age)) in names.enumerated() {
            let birthday = calendar.date(
                byAdding: DateComponents(year: -age, day: -(index * 23 % 300)),
                to: .now
            )
            context.insert(Student(firstName: first, lastName: last, birthday: birthday, schoolClass: schoolClass))
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
