import PhotosUI
import QuickLook
import SwiftData
import SwiftUI

/// Startseite der ausgewählten Klasse: Kachel-Grid aus Kennzahlen und eigenen
/// Kacheln (Dokumente, Bilder, Websites).
///
/// - Normal: Kacheln antippen öffnet sie; eigene Kacheln per langem Druck bearbeiten/entfernen.
/// - „Anordnen“: Kacheln per Drag & Drop sortieren, per Auge aus-/einblenden oder in den
///   Bereich „Ausgeblendet“ ziehen, der nur in diesem Modus sichtbar ist.
/// Reihenfolge und Sichtbarkeit gelten je Klasse. Im Privatsphäre-Modus: Inhalte
/// ausgeblendet, keine Änderungen.
struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSecurity.self) private var security
    @Environment(SchoolSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var lessons: [Lesson]
    @Query private var holidays: [Holiday]
    @Query private var classes: [SchoolClass]

    @State private var isArranging = false
    @State private var isGalleryPresented = false
    /// In der Galerie gewählte Vorlage – wird erst nach dem Schließen der Galerie
    /// ausgeführt (sonst kollidieren Sheet und Picker/Editor).
    @State private var pendingTemplate: CardTemplate?
    @State private var isFileImporterPresented = false
    @State private var isImageImporterPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var linkEditorRoute: LinkEditorRoute?
    @State private var previewURL: URL?
    @State private var importError: String?

    private var canEdit: Bool { !security.isPrivacyModeOn }

    private var selectedClass: SchoolClass? {
        classes.first { $0.id == app.selectedClassID }
    }

    var body: some View {
        ClassScopedView { schoolClass in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    cardGrid(visibleCardIDs(for: schoolClass), in: schoolClass, showsAddCard: true)

                    if isArranging {
                        hiddenSection(for: schoolClass)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(24)
                .animation(.smooth, value: schoolClass.dashboardOrder)
                .animation(.smooth, value: schoolClass.dashboardHidden)
                .animation(.smooth, value: isArranging)
            }
            .background(Color(.systemGroupedBackground))
            .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.item]) { result in
                importFile(result, kind: .file, into: schoolClass)
            }
            .fileImporter(isPresented: $isImageImporterPresented, allowedContentTypes: [.image]) { result in
                importFile(result, kind: .image, into: schoolClass)
            }
            .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoSelection, matching: .images)
            .onChange(of: photoSelection) { _, item in
                guard let item else { return }
                photoSelection = nil
                Task { await importPhoto(item, into: schoolClass) }
            }
            .task(id: schoolClass.id) { registerNewCards(in: schoolClass) }
        }
        .navigationTitle(AppTab.dashboard.title)
        .appChrome(tab: .dashboard) {
            if selectedClass != nil {
                Button(isArranging ? "Fertig" : "Anordnen") { isArranging.toggle() }
                    .disabled(!canEdit)
            }
        }
        .sheet(item: $linkEditorRoute) { route in
            LinkEditorView(route: route)
        }
        .quickLookPreview($previewURL)
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .onChange(of: security.isPrivacyModeOn) { _, isOn in
            if isOn {
                isArranging = false
                linkEditorRoute = nil
                isGalleryPresented = false
                previewURL = nil
            }
        }
        .onChange(of: app.selectedClassID) { isArranging = false }
    }

    // MARK: Grid

    private func cardGrid(_ cardIDs: [String], in schoolClass: SchoolClass, showsAddCard: Bool) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(cardIDs, id: \.self) { cardID in
                arrangeableCard(cardID, in: schoolClass)
            }

            if showsAddCard {
                // Im Privatsphäre-Modus nur ausblenden, nicht entfernen: Verschwindet
                // der Anker eines offenen Dialogs, stürzt UIKit beim Schließen ab.
                AddCard { isGalleryPresented = true }
                    .sheet(isPresented: $isGalleryPresented, onDismiss: { performPendingTemplate(in: schoolClass) }, content: {
                        CardGalleryView(
                            visibleBuiltIns: Set(visibleCardIDs(for: schoolClass).compactMap(DashboardBuiltInCard.init(rawValue:)))
                        ) { template in
                            pendingTemplate = template
                        }
                        .presentationSizing(.page)
                    })
                    .opacity(canEdit ? 1 : 0)
                    .allowsHitTesting(canEdit)
                    .accessibilityHidden(!canEdit)
            }
        }
    }

    /// Bereich „Ausgeblendet“ – nur im Anordnen-Modus. Kacheln hierher ziehen blendet sie aus.
    private func hiddenSection(for schoolClass: SchoolClass) -> some View {
        let hidden = hiddenCardIDs(for: schoolClass)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Ausgeblendet", image: .eyeClosed)
                .font(.headline)
                .foregroundStyle(.secondary)

            Group {
                if hidden.isEmpty {
                    Text("Kacheln hierher ziehen oder über das Auge ausblenden.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 110)
                } else {
                    cardGrid(hidden, in: schoolClass, showsAddCard: false)
                        .padding(16)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first else { return false }
                setHidden(true, dragged, in: schoolClass)
                return true
            }
        }
    }

    /// Kachel inkl. Anordnen-Verhalten: Ziehen, Ablegen, Aus-/Einblenden-Button.
    @ViewBuilder
    private func arrangeableCard(_ cardID: String, in schoolClass: SchoolClass) -> some View {
        let isHidden = schoolClass.dashboardHidden.contains(cardID)
        if isArranging {
            card(cardID, in: schoolClass)
                .allowsHitTesting(false)
                .opacity(isHidden ? 0.55 : 1)
                .overlay(alignment: .topTrailing) {
                    Button(isHidden ? "Einblenden" : "Ausblenden", image: isHidden ? .eye : .eyeClosed) {
                        setHidden(!isHidden, cardID, in: schoolClass)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .offset(x: 8, y: -8)
                }
                .draggable(cardID)
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first else { return false }
                    drop(dragged, onto: cardID, in: schoolClass)
                    return true
                }
        } else {
            card(cardID, in: schoolClass)
        }
    }

    // MARK: Reihenfolge & Sichtbarkeit

    /// Alle Kacheln in gespeicherter Reihenfolge; neue hinten, gelöschte fallen raus.
    private func orderedCardIDs(for schoolClass: SchoolClass) -> [String] {
        let available = DashboardBuiltInCard.allCases.map(\.rawValue)
            + schoolClass.dashboardLinks.sorted { $0.createdAt < $1.createdAt }.map(\.cardID)
        let saved = schoolClass.dashboardOrder.filter(available.contains)
        return saved + available.filter { !saved.contains($0) }
    }

    private func visibleCardIDs(for schoolClass: SchoolClass) -> [String] {
        orderedCardIDs(for: schoolClass).filter { !schoolClass.dashboardHidden.contains($0) }
    }

    private func hiddenCardIDs(for schoolClass: SchoolClass) -> [String] {
        orderedCardIDs(for: schoolClass).filter { schoolClass.dashboardHidden.contains($0) }
    }

    /// Neue Kacheln einmalig registrieren; standardmäßig ausgeblendete landen in „Ausgeblendet“.
    private func registerNewCards(in schoolClass: SchoolClass) {
        let new = orderedCardIDs(for: schoolClass).filter { !schoolClass.dashboardKnownCards.contains($0) }
        guard !new.isEmpty else { return }
        let hiddenByDefault = new.filter { DashboardBuiltInCard(rawValue: $0)?.isHiddenByDefault == true }
        schoolClass.dashboardKnownCards += new
        schoolClass.dashboardHidden += hiddenByDefault.filter { !schoolClass.dashboardHidden.contains($0) }
        try? modelContext.save()
    }

    /// Abgelegt auf einer Kachel: an deren Platz verschieben und deren Sichtbarkeit übernehmen.
    private func drop(_ dragged: String, onto target: String, in schoolClass: SchoolClass) {
        guard dragged != target else { return }
        var order = orderedCardIDs(for: schoolClass)
        guard let from = order.firstIndex(of: dragged), let to = order.firstIndex(of: target) else { return }
        order.remove(at: from)
        order.insert(dragged, at: to)
        schoolClass.dashboardOrder = order
        setHidden(schoolClass.dashboardHidden.contains(target), dragged, in: schoolClass)
    }

    private func setHidden(_ hidden: Bool, _ cardID: String, in schoolClass: SchoolClass) {
        schoolClass.dashboardHidden.removeAll { $0 == cardID }
        if hidden { schoolClass.dashboardHidden.append(cardID) }
        try? modelContext.save()
    }

    // MARK: Galerie

    private func performPendingTemplate(in schoolClass: SchoolClass) {
        guard let template = pendingTemplate else { return }
        pendingTemplate = nil
        switch template {
        case .builtIn(let card):
            setHidden(false, card.rawValue, in: schoolClass)
        case .photo:
            isPhotoPickerPresented = true
        case .imageFile:
            isImageImporterPresented = true
        case .document:
            isFileImporterPresented = true
        case .website:
            linkEditorRoute = .new(.website, schoolClass)
        case .shortcut:
            linkEditorRoute = .new(.shortcut, schoolClass)
        }
    }

    // MARK: Eigene Kacheln

    private func open(_ link: DashboardLink) {
        guard let url = link.url else { return }
        switch link.kind {
        case .website, .shortcut: openURL(url)
        case .file, .image: previewURL = url
        }
    }

    private func importFile(_ result: Result<URL, Error>, kind: DashboardLink.Kind, into schoolClass: SchoolClass) {
        do {
            let source = try result.get()
            let path = try LinkFileStore.importFile(from: source)
            let title = source.deletingPathExtension().lastPathComponent
            modelContext.insert(DashboardLink(title: title, kind: kind, location: path, schoolClass: schoolClass))
            try modelContext.save()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importPhoto(_ item: PhotosPickerItem, into schoolClass: SchoolClass) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let path = try LinkFileStore.importData(data, filename: "Foto.\(fileExtension)")
            modelContext.insert(DashboardLink(title: "", kind: .image, location: path, schoolClass: schoolClass))
            try modelContext.save()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func remove(_ link: DashboardLink) {
        LinkFileStore.removeFile(of: link)
        modelContext.delete(link)
        try? modelContext.save()
    }
}

// MARK: - Kacheln

extension DashboardView {
    @ViewBuilder
    func card(_ cardID: String, in schoolClass: SchoolClass) -> some View {
        if let builtIn = DashboardBuiltInCard(rawValue: cardID) {
            builtInCard(builtIn, in: schoolClass)
        } else if let link = schoolClass.dashboardLinks.first(where: { $0.cardID == cardID }) {
            linkCard(link, in: schoolClass)
        }
    }

    @ViewBuilder
    private func builtInCard(_ card: DashboardBuiltInCard, in schoolClass: SchoolClass) -> some View {
        switch card {
        case .students:
            StatCard(
                title: card.title,
                value: "\(schoolClass.students.count)",
                detail: genderBreakdown(schoolClass.students),
                symbol: card.symbol
            ) {
                app.open(.students)
            }
        case .nextLesson:
            nextLessonCard(for: schoolClass)
        case .nextBirthday:
            nextBirthdayCard(for: schoolClass)
        case .randomStudent:
            RandomStudentCard(students: schoolClass.students)
        case .timer:
            StatCard(title: card.title, value: "Starten", detail: "Öffnet die Uhr-App", symbol: card.symbol) {
                // Öffnet direkt den Timer-Tab der Uhr-App.
                if let url = URL(string: "clock-timer://") { openURL(url) }
            }
        case .currentLesson:
            CurrentLessonCard(
                schedule: LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots),
                visibleWeekdays: settings.visibleWeekdays
            ) {
                app.openCalendar(focusing: nil, at: .now)
            }
        }
    }

    /// Eigene Kachel (Bild, Dokument, Website, Kurzbefehl) mit Bearbeiten-Menü.
    private func linkCard(_ link: DashboardLink, in schoolClass: SchoolClass) -> some View {
        Group {
            if link.kind == .image {
                ImageCard(link: link) { open(link) }
            } else {
                LinkCard(link: link) { open(link) }
            }
        }
        .contextMenu {
            if canEdit {
                Button("Bearbeiten", image: .editPencil) { linkEditorRoute = .edit(link) }
                Button("Ausblenden", image: .eyeClosed) { setHidden(true, link.cardID, in: schoolClass) }
                Button("Entfernen", image: .trash, role: .destructive) { remove(link) }
            }
        }
    }

    /// Nächste Stunde der Klasse; öffnet den Kalender auf diese Klasse fokussiert.
    private func nextLessonCard(for schoolClass: SchoolClass) -> some View {
        let schedule = LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots)
        let next = schedule.nextLesson(forClass: schoolClass.id)
        return StatCard(
            title: "Nächste Stunde",
            value: next.map { relativeDay($0.start) } ?? "–",
            detail: next.map { next in
                ["\(next.slot.number). Stunde, \(next.slot.start.clockString)", next.lesson.subject]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            } ?? "Noch keine Stunde im Kalender",
            symbol: AppTab.calendar.symbol
        ) {
            app.openCalendar(focusing: schoolClass.id, at: next?.start)
        }
    }

    /// Nächster Geburtstag in der Klasse (heute zählt mit).
    private func nextBirthdayCard(for schoolClass: SchoolClass) -> some View {
        let calendar = Calendar.school
        let today = calendar.startOfDay(for: .now)
        let upcoming = schoolClass.students.compactMap { student -> (student: Student, date: Date)? in
            guard let birthday = student.birthday else { return nil }
            let parts = calendar.dateComponents([.month, .day], from: birthday)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            guard let next = calendar.nextDate(after: yesterday, matching: parts, matchingPolicy: .nextTime) else { return nil }
            return (student, next)
        }
        .sorted { $0.date < $1.date }

        let detail: String
        if let first = upcoming.first, let birthday = first.student.birthday {
            let days = calendar.dateComponents([.day], from: today, to: first.date).day ?? 0
            let age = calendar.component(.year, from: first.date) - calendar.component(.year, from: birthday)
            let when = days == 0 ? "Heute 🎉" : days == 1 ? "Morgen" : "in \(days) Tagen"
            let sameDay = upcoming.filter { calendar.isDate($0.date, inSameDayAs: first.date) }.count - 1
            detail = "\(when) · wird \(age)" + (sameDay > 0 ? " · +\(sameDay)" : "")
        } else {
            detail = "Keine Geburtstage eingetragen"
        }

        return StatCard(
            title: DashboardBuiltInCard.nextBirthday.title,
            value: upcoming.first.map { RandomStudentCard.shortName($0.student) } ?? "–",
            detail: detail,
            symbol: DashboardBuiltInCard.nextBirthday.symbol
        ) {
            app.open(.students)
        }
    }

    /// „♀ 46 % · ♂ 46 % · ⚧ 8 %“ (Anteile gerundet; ohne Angabe als „?“).
    private func genderBreakdown(_ students: [Student]) -> String {
        guard !students.isEmpty else { return "Noch keine Schüler" }
        let total = Double(students.count)
        var parts: [String] = Gender.allCases.compactMap { gender in
            let count = students.filter { $0.gender == gender }.count
            guard count > 0 else { return nil }
            return "\(gender.symbol) \(Int((Double(count) / total * 100).rounded())) %"
        }
        let unknown = students.filter { $0.gender == nil }.count
        if unknown > 0 { parts.append("? \(Int((Double(unknown) / total * 100).rounded())) %") }
        return parts.joined(separator: " · ")
    }

    private func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.school
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInTomorrow(date) { return "Morgen" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
