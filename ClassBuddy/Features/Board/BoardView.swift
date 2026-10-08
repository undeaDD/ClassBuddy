import QuickLook
import SwiftData
import SwiftUI

/// Tafelbild-Tab: je Klasse und Fach das zuletzt gescannte Foto der Tafel als Kachel (das neue ersetzt das alte).
/// + in der Navigationsleiste fragt das Fach ab und scannt, Antippen öffnet das Foto in Quick Look
/// (Zoomen, Teilen, Drucken), langes Drücken entfernt es.
/// Das Fach der laufenden bzw. gerade beendeten Stunde steht vorn und ist mit dem Kalender-Symbol markiert.
/// Im Privatsphäre-Modus sind die Fotos unscharf, lassen sich nicht öffnen und nichts lässt sich ändern.
struct BoardView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.device) private var device
    @Query private var classes: [SchoolClass]
    @Query private var lessons: [Lesson]
    @Query private var holidays: [Holiday]

    /// Fach, für das gerade gescannt wird.
    @State private var scanSubject: String?
    @State private var isScanPromptPresented = false
    /// In der Abfrage gewähltes Fach – der Scanner startet erst nach deren Schließen (sonst kollidieren die Cover).
    @State private var pendingScanSubject: String?
    /// Foto als Datei für Quick Look.
    @State private var preview: URL?

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == app.selectedClassID }
    }

    var body: some View {
        ClassScopedView { schoolClass in
            content(for: schoolClass)
                .task(id: schoolClass.id) { openRequestedPhoto(in: schoolClass) }
        }
        .navigationTitle(AppTab.board.title)
        .appChrome(tab: .board) {
            if let selectedClass, !selectedClass.subjects.isEmpty {
                Button("Foto aufnehmen", icon: .plus) { isScanPromptPresented = true }
                    .disabled(security.isPrivacyModeOn)
            }
        }
        .onChange(of: app.boardSubject) {
            if let selectedClass { openRequestedPhoto(in: selectedClass) }
        }
        .fullScreenCover(isPresented: Binding(get: { scanSubject != nil }, set: { if !$0 { scanSubject = nil } })) {
            BoardScanner { image in
                let subject = scanSubject
                scanSubject = nil
                if let image, let subject { save(image, subject: subject) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isScanPromptPresented, onDismiss: startPendingScan) {
            if let selectedClass {
                BoardScanPrompt(
                    subjects: selectedClass.subjects, current: currentSubject(in: selectedClass),
                    existing: { selectedClass.boardPhoto(for: $0)?.takenAt },
                    onScan: { pendingScanSubject = $0 }
                )
            }
        }
        .quickLookPreview($preview)
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn { preview = nil }
        }
    }

    @ViewBuilder
    private func content(for schoolClass: SchoolClass) -> some View {
        let current = currentSubject(in: schoolClass)
        // Fach der aktuellen Stunde zuerst, sonst Reihenfolge der Fächer.
        let photos = schoolClass.subjects
            .sorted { $0 == current && $1 != current }
            .compactMap(schoolClass.boardPhoto(for:))
        if schoolClass.subjects.isEmpty {
            EmptyStateView(
                title: loc("Noch keine Fächer"),
                message: loc("Tragen Sie für die \(schoolClass.title) Fächer ein, um Tafelbilder zu speichern."),
                symbol: AppTab.board.symbol
            )
            .background(Color(.systemGroupedBackground))
        } else if photos.isEmpty {
            EmptyStateView(
                title: loc("Noch kein Tafelbild"),
                message: loc(
                    "Scannen Sie die Tafel am Ende der Stunde über + oben rechts. Ein neues Foto ersetzt immer das letzte des Fachs."
                ),
                symbol: AppTab.board.symbol
            )
            .background(Color(.systemGroupedBackground))
        } else {
            ScrollView {
                LazyVGrid(
                    // iPhone: volle Breite untereinander; iPad: Raster wie in der Übersicht.
                    columns: device.isPhone
                        ? [GridItem(.flexible(), spacing: 16)]
                        : [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(photos) { photo in
                        BoardPhotoCard(photo: photo, isCurrent: photo.subject == current) { open(photo) }
                            .disabled(security.isPrivacyModeOn)
                            .contextMenu {
                                if !security.isPrivacyModeOn {
                                    Button("Tafelbild entfernen", destructiveIcon: .trash) { remove(photo) }
                                }
                            }
                    }
                }
                .padding(24)
                .animation(.smooth, value: photos.map(\.id))
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    /// Fach der laufenden bzw. heute zuletzt beendeten Stunde der Klasse.
    private func currentSubject(in schoolClass: SchoolClass) -> String? {
        BoardSubject.current(for: schoolClass, schedule: LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots))
    }

    // MARK: Aktionen

    /// Kachel „Letztes Tafelbild“: Foto des Fachs direkt groß öffnen.
    private func openRequestedPhoto(in schoolClass: SchoolClass) {
        guard let subject = app.boardSubject else { return }
        app.boardSubject = nil
        if let photo = schoolClass.boardPhoto(for: subject) { open(photo) }
    }

    /// Foto in Quick Look öffnen (als JPEG-Datei mit sprechendem Namen); nicht im Privatsphäre-Modus.
    private func open(_ photo: BoardPhoto) {
        guard !security.isPrivacyModeOn else { return }
        let name = "\(photo.schoolClass?.shortName ?? "") \(SchoolClass.displayName(ofSubject: photo.subject))"
            .replacingOccurrences(of: "/", with: "-")
        let url = URL.temporaryDirectory.appending(path: loc("Tafelbild \(name).jpg"))
        do {
            try photo.imageData.write(to: url)
            preview = url
        } catch {
            toasts.error(loc("Das Foto konnte nicht geöffnet werden."))
        }
    }

    private func startPendingScan() {
        guard let subject = pendingScanSubject else { return }
        pendingScanSubject = nil
        startScan(for: subject)
    }

    private func startScan(for subject: String) {
        guard !security.isPrivacyModeOn else { return }
        guard BoardScanner.isSupported else {
            toasts.error(loc("Der Dokumentenscanner ist auf diesem Gerät nicht verfügbar."))
            return
        }
        scanSubject = subject
    }

    private func save(_ image: UIImage, subject: String) {
        guard let schoolClass = selectedClass else { return }
        Task {
            guard let data = await Task.detached(operation: { BoardPhotoImage.prepare(image) }).value else {
                toasts.error(loc("Das Foto konnte nicht übernommen werden."))
                return
            }
            schoolClass.setBoardPhoto(data, subject: subject, in: modelContext)
            do {
                try modelContext.save()
                FunStat.boardPhotos.increment()
                toasts.success(loc("Tafelbild gesichert"))
            } catch {
                toasts.error(loc("Tafelbild konnte nicht gesichert werden: \(error.localizedDescription)"))
            }
        }
    }

    private func remove(_ photo: BoardPhoto) {
        modelContext.delete(photo)
        do {
            try modelContext.save()
            toasts.success(loc("Tafelbild entfernt"))
        } catch {
            toasts.error(loc("Entfernen fehlgeschlagen: \(error.localizedDescription)"))
        }
    }
}

/// Kachel: Foto oben (füllt, beschnitten), darunter Fach und Aufnahmedatum.
private struct BoardPhotoCard: View {
    let photo: BoardPhoto
    /// Fach der aktuellen Stunde: Kalender-Symbol rechts im Fuß.
    let isCurrent: Bool
    let action: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: Haptics.tapping(action)) {
            // Das Foto füllt die ganze Kachel; der Fuß liegt durchscheinend darüber.
            Color(.tertiarySystemGroupedBackground)
                .frame(maxWidth: .infinity)
                .frame(height: cardHeight + 60)
                .overlay {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .sensitiveBlur(radius: 24)
                        } else {
                            ProgressView()
                        }
                    }
                .clipped()
                .overlay(alignment: .bottom) { footer }
                .clipShape(cardShape)
            .contentShape(.hoverEffect, cardShape)
            .contentShape(.contextMenuPreview, cardShape)
            .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .task(id: photo.id) {
            let data = photo.imageData
            thumbnail = await Task.detached { BoardPhotoImage.thumbnail(from: data, maxPixelSize: 1200) }.value
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SchoolClass.displayName(ofSubject: photo.subject))
                    .font(.headline)
                Text(LastBoardCard.dateText(photo.takenAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if isCurrent {
                Image(icon: .calendar)
                    .iconSize(22)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(loc("Aktuelle Stunde"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

/// Abfrage vor dem Scannen: Fach wählen (scrollbare Liste statt Menü, auch bei vielen Fächern).
/// Vorausgewählt ist das Fach der aktuellen Stunde, sonst das erste.
private struct BoardScanPrompt: View {
    @Environment(\.dismiss) private var dismiss
    let subjects: [String]
    let current: String?
    /// Aufnahmedatum eines vorhandenen Tafelbilds des Fachs (wird ersetzt).
    let existing: (String) -> Date?
    let onScan: (String) -> Void

    @State private var subject: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Fach", selection: $subject) {
                        ForEach(subjects, id: \.self) { subject in
                            HStack {
                                Text(SchoolClass.displayName(ofSubject: subject))
                                if subject == current {
                                    Spacer()
                                    Image(icon: .calendar)
                                        .iconSize(18)
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel(loc("Aktuelle Stunde"))
                                }
                            }
                            .tag(Optional(subject))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    if let subject, let date = existing(subject) {
                        let day = date.appDate
                        Text(loc("""
                            Für \(SchoolClass.displayName(ofSubject: subject)) gibt es schon ein Tafelbild vom \(day). \
                            Es wird durch das neue ersetzt.
                            """))
                            .foregroundStyle(.orange)
                    } else {
                        Text("Ein neues Foto ersetzt das bisherige Tafelbild des Fachs.")
                    }
                }
            }
            .navigationTitle("Tafelbild aufnehmen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton()
                        .toolbarGroupBackground()
                }
                ToolbarItem(placement: .confirmationAction) {
                    ConfirmButton(title: loc("Scannen")) {
                        if let subject { onScan(subject) }
                        dismiss()
                    }
                    .disabled(subject == nil)
                    .toolbarGroupBackground(prominent: true)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { subject = current ?? subjects.first }
    }
}
