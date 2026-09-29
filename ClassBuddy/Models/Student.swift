import Foundation
import SwiftData

/// Schülerin / Schüler einer Klasse. Alle Felder gelten als sensibel (`.sensitive()`).
@Model
final class Student {
    @Attribute(.unique) var id: UUID
    var firstName: String
    var lastName: String
    var birthday: Date?
    /// `Gender.rawValue`; `nil` = keine Angabe.
    var genderRaw: String?
    var notes: String
    var createdAt: Date
    var schoolClass: SchoolClass?

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        birthday: Date? = nil,
        gender: Gender? = nil,
        notes: String = "",
        createdAt: Date = .now,
        schoolClass: SchoolClass? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.birthday = birthday
        self.genderRaw = gender?.rawValue
        self.notes = notes
        self.createdAt = createdAt
        self.schoolClass = schoolClass
    }

    var gender: Gender? {
        get { genderRaw.flatMap(Gender.init(rawValue:)) }
        set { genderRaw = newValue?.rawValue }
    }

    /// Anfangsbuchstabe des Vornamens für die alphabetischen Abschnitte.
    var sectionLetter: String {
        guard let first = firstName.first ?? lastName.first else { return "#" }
        let letter = String(first).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).uppercased()
        return letter.first?.isLetter == true ? letter : "#"
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

enum Gender: String, CaseIterable, Codable, Identifiable {
    case female, male, diverse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: "weiblich"
        case .male: "männlich"
        case .diverse: "divers"
        }
    }

    /// Kurzform für die Anzeige am Avatar.
    var shortTitle: String {
        switch self {
        case .female: "w"
        case .male: "m"
        case .diverse: "d"
        }
    }
}

// MARK: - Export

extension Student {
    struct Snapshot: Codable, Hashable {
        var id: UUID
        var firstName: String
        var lastName: String
        var birthday: Date?
        var gender: String?
        var notes: String
        var createdAt: Date
    }

    var snapshot: Snapshot {
        Snapshot(
            id: id,
            firstName: firstName,
            lastName: lastName,
            birthday: birthday,
            gender: genderRaw,
            notes: notes,
            createdAt: createdAt
        )
    }
}
