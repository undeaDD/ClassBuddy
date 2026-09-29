import Foundation
import SwiftData

/// Schülerin / Schüler einer Klasse. Alle Felder gelten als sensibel (`.sensitive()`).
@Model
final class Student {
    @Attribute(.unique) var id: UUID
    var firstName: String
    var lastName: String
    var birthday: Date?
    var notes: String
    var createdAt: Date
    var schoolClass: SchoolClass?

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        birthday: Date? = nil,
        notes: String = "",
        createdAt: Date = .now,
        schoolClass: SchoolClass? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.birthday = birthday
        self.notes = notes
        self.createdAt = createdAt
        self.schoolClass = schoolClass
    }

    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var initials: String {
        [firstName.first, lastName.first].compactMap { $0 }.map(String.init).joined()
    }

    var age: Int? {
        guard let birthday else { return nil }
        return Calendar.current.dateComponents([.year], from: birthday, to: .now).year
    }
}

// MARK: - Export

extension Student {
    struct Snapshot: Codable, Hashable {
        var id: UUID
        var firstName: String
        var lastName: String
        var birthday: Date?
        var notes: String
        var createdAt: Date
    }

    var snapshot: Snapshot {
        Snapshot(
            id: id,
            firstName: firstName,
            lastName: lastName,
            birthday: birthday,
            notes: notes,
            createdAt: createdAt
        )
    }
}
