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
                    if let thumbnail {
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
                let data = photo.imageData
                thumbnail = await Task.detached { BoardPhotoImage.thumbnail(from: data, maxPixelSize: 900) }.value
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
