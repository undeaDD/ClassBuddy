import SwiftUI

extension DashboardView {
    /// Kacheln, die nur die Klasse brauchen (Zufallsauswahl, Gruppen, Tafelbild, Checklisten, Schnellnotiz, Anwesenheit).
    @ViewBuilder
    func classToolCard(_ card: DashboardBuiltInCard, in schoolClass: SchoolClass) -> some View {
        switch card {
        case .groups: GroupsCard(schoolClass: schoolClass)
        case .lastBoard: LastBoardCard(schoolClass: schoolClass)
        case .checklists: ChecklistsDashboardCard(schoolClass: schoolClass)
        case .quickNote: QuickNoteCard(schoolClass: schoolClass)
        case .attendance: AttendanceCard(schoolClass: schoolClass)
        default: RandomStudentCard(students: schoolClass.students)
        }
    }
}

/// Kachel „Letztes Tafelbild“: Vorschau des neuesten Tafelbilds der Klasse; öffnet den Tab mit diesem Fach.
struct LastBoardCard: View {
    @Environment(AppModel.self) private var app
    let schoolClass: SchoolClass

    @State private var thumbnail: UIImage?

    var body: some View {
        let card = DashboardBuiltInCard.lastBoard
        if let photo = schoolClass.latestBoardPhoto {
            Button(action: Haptics.tapping { app.openBoard(subject: photo.subject) }) {
                BoardImageCard(subject: SchoolClass.displayName(ofSubject: photo.subject), dateText: Self.dateText(photo.takenAt)) {
                    if let thumbnail = thumbnail ?? DashboardImageCache.cachedBoard(photo.id) {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .sensitiveBlur(radius: 24)
                    } else {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .accessibilityLabel(card.title)
            .task(id: photo.id) {
                thumbnail = await DashboardImageCache.board(photo)
            }
        } else {
            StatCard(
                title: card.title,
                value: "–",
                detail: schoolClass.subjects.isEmpty ? loc("Noch keine Fächer") : loc("Noch kein Tafelbild"),
                symbol: card.symbol,
                isSensitive: false
            ) {
                app.open(.board)
            }
        }
    }

    static func dateText(_ date: Date) -> String {
        let time = date.appTime
        if Calendar.current.isDateInToday(date) { return loc("Heute um \(time)") }
        return loc("Am \(date.appDate) um \(time)")
    }
}

/// Bild-Kachel des Tafelbilds (auch Galerie-Vorschau): Bild randlos, Fach und Datum unten auf Material.
struct BoardImageCard<Picture: View>: View {
    let subject: String
    let dateText: String
    @ViewBuilder let picture: Picture

    var body: some View {
        // Feste Kartengröße; das Bild liegt als Overlay darüber (wie bei Bild-Kacheln).
        Color(.secondarySystemGroupedBackground)
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .overlay { picture }
            .clipped()
            .overlay(alignment: .bottomLeading) { caption }
            .clipShape(cardShape)
            .contentShape(.hoverEffect, cardShape)
            .contentShape(.dragPreview, cardShape)
            .contentShape(cardShape)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subject)
                .font(.headline)
            Text(dateText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .rect(cornerRadius: 14, style: .continuous))
        .padding(12)
    }
}

/// Fertige Vorschaubilder der Übersicht im Speicher. Kacheln werden oft neu aufgebaut (Anordnen-Modus an/aus,
/// Scrollen im Lazy-Grid); ohne Cache lud und dekodierte jede neue Kachel ihr Bild erneut, das Tafelbild sogar
/// samt Foto-Daten aus der Datenbank auf dem Main Thread – der Anordnen-Modus ruckelte stark.
enum DashboardImageCache {
    nonisolated(unsafe) private static let images = NSCache<NSString, UIImage>()

    static func cachedThumbnail(_ url: URL) -> UIImage? {
        images.object(forKey: "file|\(url.path(percentEncoded: false))" as NSString)
    }

    static func thumbnail(for url: URL) async -> UIImage? {
        if let cached = cachedThumbnail(url) { return cached }
        let image = await Task.detached { Thumbnail.make(from: url, maxPixelSize: 900) }.value
        if let image { images.setObject(image, forKey: "file|\(url.path(percentEncoded: false))" as NSString) }
        return image
    }

    static func cachedBoard(_ id: UUID) -> UIImage? {
        images.object(forKey: "board|\(id.uuidString)" as NSString)
    }

    /// Foto-Daten nur lesen, wenn das Bild noch nicht im Speicher liegt.
    static func board(_ photo: BoardPhoto) async -> UIImage? {
        if let cached = cachedBoard(photo.id) { return cached }
        let data = photo.imageData
        let image = await Task.detached { BoardPhotoImage.thumbnail(from: data, maxPixelSize: 900) }.value
        if let image { images.setObject(image, forKey: "board|\(photo.id.uuidString)" as NSString) }
        return image
    }
}
