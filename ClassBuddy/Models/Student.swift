import Foundation
import SwiftData
import UIKit

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
    var phone: String = ""
    var email: String = ""
    /// Weitere Kontaktangaben als Freitext (z. B. Eltern, Messenger).
    var otherContact: String = ""
    /// Profilfoto statt der Initialen: verkleinertes JPEG (`StudentPhoto`). Liegt nur im App-Container –
    /// durch die Sandbox für andere Apps unzugänglich und per iOS-Datenschutz verschlüsselt, solange
    /// ein Gerätecode gesetzt ist. Nicht im Excel-Export enthalten.
    @Attribute(.externalStorage) var photo: Data?
    var createdAt: Date
    var schoolClass: SchoolClass?

    /// Sitzplätze des Schülers (je Raum höchstens einer).
    @Relationship(deleteRule: .cascade, inverse: \SeatAssignment.student)
    var seatAssignments: [SeatAssignment] = []

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String,
        birthday: Date? = nil,
        gender: Gender? = nil,
        notes: String = "",
        phone: String = "",
        email: String = "",
        otherContact: String = "",
        photo: Data? = nil,
        createdAt: Date = .now,
        schoolClass: SchoolClass? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.birthday = birthday
        self.genderRaw = gender?.rawValue
        self.notes = notes
        self.phone = phone
        self.email = email
        self.otherContact = otherContact
        self.photo = photo
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

nonisolated enum Gender: String, CaseIterable, Codable, Identifiable {
    case female, male, diverse

    var id: String { rawValue }

    /// Wert im Excel-Backup und Erkennung beim Import (immer Deutsch).
    var title: String {
        switch self {
        case .female: "weiblich"
        case .male: "männlich"
        case .diverse: "divers"
        }
    }

    /// Anzeige in der App-Sprache (großgeschrieben, z. B. im Picker „♀ Weiblich“).
    var displayTitle: String {
        switch self {
        case .female: loc("Weiblich")
        case .male: loc("Männlich")
        case .diverse: loc("Divers")
        }
    }

    /// Geschlechtssymbol für den Avatar (in SF Symbols gibt es keine).
    /// U+FE0E erzwingt die Text- statt der Emoji-Darstellung.
    var symbol: String {
        switch self {
        case .female: "\u{2640}\u{FE0E}"  // ♀
        case .male: "\u{2642}\u{FE0E}"    // ♂
        case .diverse: "\u{26A7}\u{FE0E}" // ⚧
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
        var phone: String
        var email: String
        var otherContact: String
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
            phone: phone,
            email: email,
            otherContact: otherContact,
            createdAt: createdAt
        )
    }
}

/// Profilfotos: beim Übernehmen auf höchstens 512 px verkleinert (JPEG), beim Anzeigen zwischengespeichert.
nonisolated enum StudentPhoto {
    static let maxPixelSize: CGFloat = 512

    /// Verkleinert ein gewähltes Bild; `nil`, wenn es kein lesbares Bild ist.
    static func prepare(_ data: Data, maxPixel: CGFloat = maxPixelSize) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxPixel / max(longest, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.8)
    }

    /// NSCache ist threadsicher.
    nonisolated(unsafe) private static let cache = NSCache<NSData, UIImage>()

    /// Dekodiertes Bild, zwischengespeichert (Listen zeichnen Avatare sehr oft).
    static func image(from data: Data) -> UIImage? {
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
