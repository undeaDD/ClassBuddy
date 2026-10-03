import SwiftData
import SwiftUI

/// Räume der Schule als Karten mit Grundriss-Vorschau. Antippen öffnet den Editor,
/// langes Drücken Bearbeiten, Duplizieren und Entfernen; Karten lassen sich per Drag & Drop anordnen.
/// Räume gehören keiner Klasse. Im Privatsphäre-Modus nur lesend, Namen und Fächer verborgen.
struct RoomsView: View {
    @Environment(AppSecurity.self) private var security
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.device) private var device
    @Query(sort: [SortDescriptor(\Room.sortIndex), SortDescriptor(\Room.name)]) private var rooms: [Room]

    @State private var searchText = ""
    @State private var editorRoute: RoomEditorRoute?
    @State private var roomPendingDeletion: Room?

    private var canEdit: Bool { !security.isPrivacyModeOn }

    private var visibleRooms: [Room] { filtered(rooms) }

    var body: some View {
        content
            .background(Color(.systemGroupedBackground))
            .navigationTitle(AppTab.rooms.title)
            .navigationSubtitle(rooms.count == 1 ? loc("1 Raum") : loc("\(rooms.count) Räume"))
            .appChrome(tab: .rooms) {
                Button("Raum hinzufügen", icon: .plus) { editorRoute = .new }
                    .disabled(!canEdit)
            }
            .fullScreenCover(item: $editorRoute) { route in
                RoomEditorView(route: route, nextSortIndex: (rooms.map(\.sortIndex).max() ?? -1) + 1)
                    .softScrollEdges()
            }
            .confirmationDialog(
                "Raum entfernen?",
                isPresented: Binding(
                    get: { roomPendingDeletion != nil },
                    set: { if !$0 { roomPendingDeletion = nil } }
                ),
                presenting: roomPendingDeletion
            ) { room in
                Button("Entfernen", role: .destructive) { delete(room) }
            } message: { _ in
                Text("Grundriss und Sitzpläne des Raums werden gelöscht. Stunden im Kalender bleiben ohne Raum erhalten.")
            }
            .onChange(of: security.isPrivacyModeOn) { _, isOn in
                if isOn {
                    editorRoute = nil
                    roomPendingDeletion = nil
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if rooms.isEmpty {
            EmptyStateView(
                title: loc("Noch keine Räume"),
                message: loc("Zeichnen Sie den Grundriss eines Raums mit Tischen, Tafel, Tür und Fenstern."),
                symbol: AppTab.rooms.symbol
            ) {
                Button("Raum hinzufügen") { editorRoute = .new }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canEdit)
            }
        } else {
            ScrollView {
                grid(visibleRooms)
                    .padding(device.isPhone ? 16 : 24)
                    .animation(.smooth, value: rooms.map(\.sortIndex))
            }
            .searchable(text: $searchText, prompt: "Räume suchen")
            .overlay {
                if visibleRooms.isEmpty {
                    SearchEmptyStateView(text: searchText)
                }
            }
        }
    }

    private func grid(_ rooms: [Room]) -> some View {
        LazyVGrid(
            columns: device.isPhone
                ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                : [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)],
            alignment: .leading,
            spacing: device.isPhone ? 12 : 16
        ) {
            ForEach(rooms) { room in
                card(for: room)
            }
        }
    }

    private func card(for room: Room) -> some View {
        Button {
            Haptics.tap()
            if canEdit { editorRoute = .edit(room) }
        } label: {
            RoomCard(room: room)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .contextMenu {
            if canEdit {
                Button("Bearbeiten", icon: .editPencil) { editorRoute = .edit(room) }
                Button("Duplizieren", icon: .duplicate) { duplicate(room) }
                Button("Entfernen", destructiveIcon: .trash) { roomPendingDeletion = room }
            }
        }
        .draggable(room.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard canEdit, let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            move(dragged, onto: room)
            return true
        }
    }

    // MARK: Aktionen

    private func filtered(_ rooms: [Room]) -> [Room] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return rooms }
        return rooms.filter { room in
            ([room.name, room.subtitle, room.category.displayTitle]
                + room.assignments.map(SchoolClass.displayName(ofSubject:)))
                .contains { $0.localizedStandardContains(query) }
        }
    }

    /// Gezogenen Raum an die Stelle des Ziels setzen.
    private func move(_ draggedID: UUID, onto target: Room) {
        guard let dragged = rooms.first(where: { $0.id == draggedID }), dragged.id != target.id else { return }
        var ordered = rooms.filter { $0.id != dragged.id }
        let index = ordered.firstIndex { $0.id == target.id } ?? ordered.endIndex
        ordered.insert(dragged, at: index)
        for (index, room) in ordered.enumerated() { room.sortIndex = index }
        try? modelContext.save()
        Haptics.selection()
    }

    private func duplicate(_ room: Room) {
        let copy = Room(
            name: loc("\(room.name) (Kopie)"),
            subtitle: room.subtitle,
            category: room.category,
            assignments: room.assignments,
            sortIndex: room.sortIndex + 1
        )
        copy.equipment = room.equipment
        for other in rooms where other.sortIndex > room.sortIndex { other.sortIndex += 1 }
        modelContext.insert(copy)
        // Neue IDs: die Kopie hat eigene Tische (ohne Sitzplan).
        copy.replaceElements(with: room.shapes.map { RoomShape(kind: $0.kind, points: $0.points) }, in: modelContext)
        try? modelContext.save()
        toasts.success(loc("Raum dupliziert"))
    }

    private func delete(_ room: Room) {
        modelContext.delete(room)
        do {
            try modelContext.save()
            toasts.success(loc("Raum entfernt"))
        } catch {
            toasts.error(loc("Löschen fehlgeschlagen: \(error.localizedDescription)"))
        }
    }
}

/// Karte eines Raums: Grundriss-Vorschau, Name, Kategorie und Anzahl Plätze; feste Höhe.
struct RoomCard: View {
    let room: Room

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Grundriss enthält keine personenbezogenen Daten → bleibt im Privatsphäre-Modus sichtbar.
            RoomFloorPlanView(shapes: room.shapes, padding: 4, lineWidth: 1.2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name)
                    .font(.headline)
                    .lineLimit(1)
                    .cardPrivacy()
                    .leadingAligned()
                Text([room.category.displayTitle, room.seatCount == 1 ? loc("1 Platz") : loc("\(room.seatCount) Plätze")]
                    .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .leadingAligned()
                Text(room.subtitle.isEmpty ? room.assignmentsText : room.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .cardPrivacy()
                    .leadingAligned()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 220, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: cardShape)
        .contentShape(.hoverEffect, cardShape)
        .contentShape(.dragPreview, cardShape)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { RoomsView() }
}
