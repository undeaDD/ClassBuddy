import Foundation
import ImageIO
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// Tafelbild: ein Foto je Klasse und Fach (das neueste ersetzt das alte, kein Verlauf).
/// Nicht im Excel-Backup (wie alle Bilder der App); beim Import bleibt es für Klassen mit gleicher ID erhalten.
@Model
final class BoardPhoto {
    @Attribute(.unique) var id: UUID
    var subject: String
    var takenAt: Date
    @Attribute(.externalStorage) var imageData: Data
    var schoolClass: SchoolClass?

    init(id: UUID = UUID(), subject: String, takenAt: Date = .now, imageData: Data, schoolClass: SchoolClass? = nil) {
        self.id = id
        self.subject = subject
        self.takenAt = takenAt
        self.imageData = imageData
        self.schoolClass = schoolClass
    }
}

extension SchoolClass {
    func boardPhoto(for subject: String) -> BoardPhoto? {
        boardPhotos.first { $0.subject == subject }
    }

    /// Neuestes Tafelbild der Klasse (für die Kachel „Letztes Tafelbild“).
    var latestBoardPhoto: BoardPhoto? {
        boardPhotos.max { $0.takenAt < $1.takenAt }
    }

    /// Speichert ein neues Tafelbild und ersetzt das bisherige desselben Fachs.
    @discardableResult
    func setBoardPhoto(_ data: Data, subject: String, takenAt: Date = .now, in context: ModelContext) -> BoardPhoto {
        for old in boardPhotos where old.subject == subject {
            context.delete(old)
        }
        let photo = BoardPhoto(subject: subject, takenAt: takenAt, imageData: data, schoolClass: self)
        context.insert(photo)
        return photo
    }

    /// Tafelbilder von Fächern löschen, die die Klasse nicht mehr hat.
    func removeBoardPhotosOfRemovedSubjects(in context: ModelContext) {
        for photo in boardPhotos where !subjects.contains(photo.subject) {
            context.delete(photo)
        }
    }
}

nonisolated enum BoardPhotoImage {
    /// Verkleinert auf höchstens `maxPixel` (lange Seite) und speichert als JPEG – Tafeln brauchen keine 12 MP.
    static func prepare(_ image: UIImage, maxPixel: CGFloat = 2800, quality: CGFloat = 0.8) -> Data? {
        let longest = max(image.size.width, image.size.height) * image.scale
        let factor = min(1, maxPixel / max(longest, 1))
        let size = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Speicherschonendes Vorschaubild aus den gespeicherten Daten.
    static func thumbnail(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }
}

/// Fach der aktuellen Stunde: laufende Stunde der Klasse, sonst die heute zuletzt beendete.
enum BoardSubject {
    static func current(for schoolClass: SchoolClass, schedule: LessonSchedule, now: Date = .now) -> String? {
        let calendar = Calendar.school
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let today = schedule.slots
            .filter { $0.start <= minute }
            .compactMap { slot in schedule.lesson(on: now, slotIndex: slot.index).map { (slot, $0) } }
            .filter { $0.1.schoolClass?.id == schoolClass.id && schoolClass.subjects.contains($0.1.subject) }
        return today.last?.1.subject
    }
}
