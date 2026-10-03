import SwiftData
import SwiftUI

enum RoomEditorRoute: Identifiable {
    case new
    case edit(Room)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let room): room.id.uuidString
        }
    }

    var room: Room? {
        if case .edit(let room) = self { room } else { nil }
    }
}

/// Vollbild-Editor eines Raums: Grundriss auf dem Punktraster zeichnen, Details bearbeiten.
/// Speichern nur, wenn der Raum gültig ist und einen Namen hat.
struct RoomEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.device) private var device

    let room: Room?
    /// Reihenfolge eines neuen Raums (ans Ende der Übersicht).
    let nextSortIndex: Int

    @State private var model: RoomEditorModel
    @State private var details: RoomDetails
    private let initialDetails: RoomDetails
    @State private var isDetailsPresented = false
    @State private var isDiscardConfirmationPresented = false
    @State private var isLossConfirmationPresented = false

    init(route: RoomEditorRoute, nextSortIndex: Int = 0) {
        room = route.room
        self.nextSortIndex = nextSortIndex
        _model = State(initialValue: RoomEditorModel(shapes: route.room?.shapes ?? []))
        let details = RoomDetails(room: route.room)
        _details = State(initialValue: details)
        initialDetails = details
    }

    private var hasChanges: Bool { model.hasChanges || details != initialDetails }

    /// Hinweise, was zum Speichern fehlt (doppelte Meldungen zusammengefasst).
    private var hints: [String] {
        var hints: [String] = []
        if details.trimmedName.isEmpty { hints.append(loc("Geben Sie dem Raum unter „Details“ einen Namen.")) }
        for message in model.issues.map(\.message) where !hints.contains(message) {
            hints.append(message)
        }
        return hints
    }

    private var canSave: Bool { hints.isEmpty && hasChanges }

    var body: some View {
        NavigationStack {
            RoomCanvas(model: model)
                .ignoresSafeArea(.container, edges: .bottom)
                .overlay(alignment: .top) { hintBanner }
                .floatingBottomBar {
                    RoomToolbox(model: model, isCompact: device.isPhone) { isDetailsPresented = true }
                }
                // Kompakt ist die Toolbox zweizeilig.
                .onChange(of: device.isPhone, initial: true) { _, isPhone in model.bottomInset = isPhone ? 150 : 90 }
                .navigationTitle(details.trimmedName.isEmpty ? (room == nil ? loc("Neuer Raum") : loc("Raum")) : details.trimmedName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .sheet(isPresented: $isDetailsPresented) {
                    RoomDetailsView(details: $details)
                        .softScrollEdges()
                }
                .confirmationDialog("Änderungen verwerfen?", isPresented: $isDiscardConfirmationPresented) {
                    Button("Verwerfen", role: .destructive) { dismiss() }
                }
                .confirmationDialog(
                    "Sitzplan-Zuordnungen gehen verloren",
                    isPresented: $isLossConfirmationPresented
                ) {
                    Button("Trotzdem speichern", role: .destructive, action: save)
                } message: {
                    Text("\(lostAssignments) Zuordnungen hängen an geänderten oder entfernten Tischen und gehen verloren.")
                }
                .task {
                    // Neuer Raum: zuerst einen Namen vergeben.
                    if room == nil { isDetailsPresented = true }
                }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Verwerfen", icon: .xmark, role: .cancel) {
                if hasChanges { isDiscardConfirmationPresented = true } else { dismiss() }
            }
        }
        // iPhone: Einpassen und Details stehen in der Toolbox unten.
        if !device.isPhone {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Einpassen", icon: .fit) { model.fit() }
                Button("Details", icon: .moreHoriz) { isDetailsPresented = true }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .confirmationAction) {
            ConfirmButton(title: loc("Speichern"), action: attemptSave)
                .disabled(!canSave)
                .keyboardShortcut("s", modifiers: .command)
        }
    }

    @ViewBuilder
    private var hintBanner: some View {
        if let hint = hints.first {
            Text(hint)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(.smooth, value: hint)
        }
    }

    // MARK: Speichern

    /// Sitzplan-Zuordnungen an Tischen, die geändert, geteilt oder entfernt wurden.
    private var lostAssignments: Int {
        guard let room else { return 0 }
        let changed = RoomElementSync.changedTableIDs(old: room.shapes, new: model.shapes)
        return room.elements.filter { changed.contains($0.id) }.reduce(0) { $0 + $1.seatAssignments.count }
    }

    private func attemptSave() {
        guard canSave else { return }
        if lostAssignments > 0 { isLossConfirmationPresented = true } else { save() }
    }

    private func save() {
        let target = room ?? {
            let newRoom = Room(name: "", sortIndex: nextSortIndex)
            modelContext.insert(newRoom)
            return newRoom
        }()
        details.apply(to: target)
        target.replaceElements(with: model.shapes, in: modelContext)
        try? modelContext.save()
        dismiss()
    }
}

/// Toolbox unten. Breit: Werkzeuge | Rückgängig/Wiederholen in einer Zeile.
/// Kompakt (iPhone): darüber zwei Blasen [Rückgängig, Wiederholen] [Einpassen, Details], darunter die Werkzeuge.
/// Werkzeuge mit kurzem Namen unter dem Icon; passt das nicht, nur Icons.
private struct RoomToolbox: View {
    let model: RoomEditorModel
    let isCompact: Bool
    let showDetails: () -> Void

    private static let tools: [RoomTool] = [.move] + RoomElementKind.allCases.map(RoomTool.pen) + [.eraser]

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            if isCompact {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        undoRedo(size: 36)
                        bubble {
                            iconButton(loc("Einpassen"), icon: .fit, size: 36) { model.fit() }
                            iconButton(loc("Details"), icon: .moreHoriz, size: 36, action: showDetails)
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        tools(showsLabels: true, size: 34)
                        tools(showsLabels: false, size: 32)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        tools(showsLabels: true, size: 36)
                        undoRedo(size: 36)
                    }
                    HStack(spacing: 10) {
                        tools(showsLabels: false, size: 32)
                        undoRedo(size: 32)
                    }
                }
            }
        }
    }

    private func tools(showsLabels: Bool, size: CGFloat) -> some View {
        HStack(spacing: showsLabels ? 2 : 0) {
            ForEach(Self.tools, id: \.self) { tool in
                toolButton(tool, showsLabel: showsLabels, size: size)
            }
        }
        // Links und rechts etwas Luft, damit „Maus“ und „Radierer“ nicht am Glasrand kleben.
        .padding(.horizontal, 4)
        .padding(4)
        .glassEffect(.regular.interactive(), in: showsLabels ? AnyShape(.rect(cornerRadius: 24)) : AnyShape(.capsule))
        .fixedSize()
    }

    private func undoRedo(size: CGFloat) -> some View {
        bubble {
            iconButton(loc("Rückgängig"), icon: .undo, size: size) { model.undo() }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            iconButton(loc("Wiederholen"), icon: .redo, size: size) { model.redo() }
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }

    private func bubble<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0, content: content)
            .padding(4)
            .glassEffect(.regular.interactive(), in: .capsule)
            .fixedSize()
    }

    private func color(of tool: RoomTool) -> Color {
        if case .pen(let kind) = tool { kind.color } else { .primary }
    }

    /// Auswahl als Kreis hinter dem Icon, der Name darunter.
    private func toolButton(_ tool: RoomTool, showsLabel: Bool, size: CGFloat) -> some View {
        let isSelected = model.tool == tool
        let color = color(of: tool)
        return Button {
            Haptics.selection()
            model.tool = tool
        } label: {
            VStack(spacing: 1) {
                tool.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.58, height: size * 0.58)
                    .foregroundStyle(color)
                    .frame(width: size, height: size)
                    .background(isSelected ? color.opacity(0.22) : .clear, in: .circle)
                if showsLabel {
                    Text(tool.shortTitle)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.bottom, 2)
                }
            }
            .frame(minWidth: size)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(tool.title)
    }

    private func iconButton(_ title: String, icon: AppIcon, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(icon: icon)
                .iconSize(size * 0.6)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }
}
