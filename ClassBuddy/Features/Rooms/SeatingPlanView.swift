import SwiftUI

/// Sitzplan einer Klasse in einem Raum (geöffnet aus Kalender oder Übersicht).
struct SeatingPlanRoute: Identifiable {
    let id = UUID()
    let room: Room
    let schoolClass: SchoolClass?
}

/// Sitzplan – vorerst Platzhalter: Grundriss mit bereits zugeordneten Schülern, Teilen als PDF.
/// Zuordnen per Drag & Drop aus der Seitenleiste folgt in einer eigenen Ansicht.
struct SeatingPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSecurity.self) private var security
    let route: SeatingPlanRoute

    @State private var pdfURL: URL?

    private var subtitle: String {
        [route.room.name, route.schoolClass?.title ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Schülernamen auf den Tischen; im Privatsphäre-Modus keine (Canvas-Text lässt sich nicht schwärzen).
    private var labels: [UUID: String] {
        guard !security.isPrivacyModeOn else { return [:] }
        return SeatingPlanLabels.labels(for: route.room, schoolClass: route.schoolClass)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                RoomFloorPlanView(shapes: route.room.shapes, padding: 16, lineWidth: 2, labels: labels)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground), in: cardShape)
                Text("Hier ordnen Sie bald die Schülerinnen und Schüler per Drag & Drop den Tischen zu.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .padding(24)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sitzplan")
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen", icon: .xmark, role: .close) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let pdfURL, !security.isPrivacyModeOn {
                        ShareLink(item: pdfURL) {
                            Label("Drucken oder als PDF teilen", icon: .shareIos)
                        }
                    }
                }
            }
            .task(id: labels) {
                pdfURL = SeatingPlanPDF.make(room: route.room, subtitle: subtitle, labels: labels)
            }
        }
    }
}

enum SeatingPlanLabels {
    /// „Emma S.“ je Tisch für die Schüler der Klasse.
    static func labels(for room: Room, schoolClass: SchoolClass?) -> [UUID: String] {
        guard let schoolClass else { return [:] }
        var labels: [UUID: String] = [:]
        for element in room.elements where element.kind == .table {
            let names = element.seatAssignments
                .compactMap(\.student)
                .filter { $0.schoolClass?.id == schoolClass.id }
                .map(RandomStudentCard.shortName)
            if !names.isEmpty { labels[element.id] = names.joined(separator: ", ") }
        }
        return labels
    }
}

/// PDF des Grundrisses mit Sitzplan (A4 quer), immer im hellen Erscheinungsbild.
enum SeatingPlanPDF {
    static func make(room: Room, subtitle: String, labels: [UUID: String]) -> URL? {
        let page = CGSize(width: 842, height: 595)
        let content = VStack(alignment: .leading, spacing: 12) {
            Text("Sitzplan").font(.title.bold())
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
            RoomFloorPlanView(shapes: room.shapes, padding: 8, lineWidth: 1.5, labels: labels)
        }
        .padding(36)
        .frame(width: page.width, height: page.height, alignment: .topLeading)
        .background(.white)
        .environment(\.colorScheme, .light)

        let fileName = subtitle.replacingOccurrences(of: "/", with: "-")
        let url = URL.temporaryDirectory.appending(path: loc("Sitzplan \(fileName).pdf"))
        let renderer = ImageRenderer(content: content)
        var box = CGRect(origin: .zero, size: page)
        renderer.render { _, draw in
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return FileManager.default.fileExists(atPath: url.path()) ? url : nil
    }
}
