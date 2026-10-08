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
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.device) private var device
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
    /// Gemessene Kachelgrößen – die Drag-Vorschau wird sonst in Idealgröße statt Grid-Breite gerendert.
    @State private var cardSizes: [String: CGSize] = [:]

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
            .sheet(isPresented: $isGalleryPresented, onDismiss: { performPendingTemplate(in: schoolClass) }, content: {
                CardGalleryView(
                    visibleBuiltIns: Set(visibleCardIDs(for: schoolClass).compactMap(DashboardBuiltInCard.init(rawValue:)))
                ) { template in
                    pendingTemplate = template
                }
                .appPresentationSizing(.page)
                .softScrollEdges()
            })
            .onChange(of: photoSelection) { _, item in
                guard let item else { return }
                photoSelection = nil
                Task { await importPhoto(item, into: schoolClass) }
            }
            .task(id: schoolClass.id) { registerNewCards(in: schoolClass) }
        }
        .navigationTitle(AppTab.dashboard.title)
        .appNavigationSubtitle(selectedClass.map { "\($0.title) · \($0.schoolYear)" } ?? "")
        .appChrome(tab: .dashboard) {
            if selectedClass != nil {
                Button(isArranging ? "Fertig" : "Kacheln anordnen", image: isArranging ? .check : .editPencil) {
                    isArranging.toggle()
                }
                .disabled(!canEdit)
            }
        }
        .sheet(item: $linkEditorRoute) { route in
            if case .edit(let link) = route, link.kind == .script {
                ScriptEditorView(link: link)
                    .softScrollEdges()
            } else {
                LinkEditorView(route: route)
                    .softScrollEdges()
            }
        }
        .quickLookPreview($previewURL)
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
            // iPhone: eine Spalte über die volle Breite; iPad: so viele 240–320 pt breite Spalten wie passen.
            columns: device.isPhone
                ? [GridItem(.flexible(), spacing: 16)]
                : [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(cardIDs, id: \.self) { cardID in
                arrangeableCard(cardID, in: schoolClass)
            }

            // Nicht beim Anordnen und nicht im Privatsphäre-Modus. Die Galerie hängt am Grid
            // (nicht an dieser Kachel), damit ihr Anker nie verschwindet.
            if showsAddCard, !isArranging, canEdit {
                AddCard { isGalleryPresented = true }
            }
        }
    }

    /// Bereich „Ausgeblendet“ – nur im Anordnen-Modus. Kacheln hierher ziehen blendet sie aus.
    private func hiddenSection(for schoolClass: SchoolClass) -> some View {
        let hidden = hiddenCardIDs(for: schoolClass)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Ausgeblendet", icon: .eyeClosed)
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
                // Vor dem Overlay, damit Auge und ✕ ruhig stehen bleiben.
                .wiggling(seed: cardID)
                // Die Kachel selbst ist nicht antippbar – ohne eigene Form greift das Ziehen nur an den Buttons.
                .contentShape(cardShape)
                .onGeometryChange(for: CGSize.self, of: \.size) { cardSizes[cardID] = $0 }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 8) {
                        Button(isHidden ? "Einblenden" : "Ausblenden", image: isHidden ? .eye : .eyeClosed) {
                            setHidden(!isHidden, cardID, in: schoolClass)
                        }
                        Button("Entfernen", icon: .xmark) {
                            removeCard(cardID, in: schoolClass)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .appGlassButtonStyle()
                    .buttonBorderShape(.circle)
                    .offset(x: 8, y: -8)
                }
                // Eigene Vorschau nur aus der Kachel – sonst hängen die Buttons abgeschnitten dran.
                .draggable(cardID) {
                    card(cardID, in: schoolClass)
                        .frame(width: cardSizes[cardID]?.width, height: cardSizes[cardID]?.height)
                        .contentShape(.dragPreview, cardShape)
                }
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
        let available = DashboardBuiltInCard.allCases.filter(\.isSupported).map(\.rawValue)
            + schoolClass.dashboardLinks.sorted { $0.createdAt < $1.createdAt }.map(\.cardID)
        let saved = schoolClass.dashboardOrder.filter(available.contains)
        return saved + available.filter { !saved.contains($0) }
    }

    private func visibleCardIDs(for schoolClass: SchoolClass) -> [String] {
        orderedCardIDs(for: schoolClass).filter {
            !schoolClass.dashboardHidden.contains($0) && !schoolClass.dashboardRemoved.contains($0)
        }
    }

    private func hiddenCardIDs(for schoolClass: SchoolClass) -> [String] {
        orderedCardIDs(for: schoolClass).filter {
            schoolClass.dashboardHidden.contains($0) && !schoolClass.dashboardRemoved.contains($0)
        }
    }

    /// ✕ im Anordnen-Modus: eigene Kacheln löschen, eingebaute ganz von der Übersicht nehmen.
    private func removeCard(_ cardID: String, in schoolClass: SchoolClass) {
        if let link = schoolClass.dashboardLinks.first(where: { $0.cardID == cardID }) {
            remove(link)
            return
        }
        schoolClass.dashboardHidden.removeAll { $0 == cardID }
        if !schoolClass.dashboardRemoved.contains(cardID) { schoolClass.dashboardRemoved.append(cardID) }
        try? modelContext.save()
        toasts.success(loc("Kachel entfernt"))
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
            schoolClass.dashboardRemoved.removeAll { $0 == card.rawValue }
            setHidden(false, card.rawValue, in: schoolClass)
        case .image:
            break // wird in der Galerie per Menü zu .photo bzw. .imageFile
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
        case .script:
            modelContext.insert(DashboardLink.newScript(in: schoolClass))
            try? modelContext.save()
            toasts.success(loc("Skript-Kachel hinzugefügt – lange drücken zum Bearbeiten"))
        case .request:
            openURL(AppInfo.mailURL(
                subject: loc("Kachel-Wunsch für ClassBuddy"),
                body: loc("Welche Kachel wünschen Sie sich und was soll sie zeigen?\n\n")
            ))
        }
    }

    // MARK: Eigene Kacheln

    private func open(_ link: DashboardLink) {
        guard let url = link.url else { return }
        switch link.kind {
        case .website, .shortcut: openURL(url)
        case .file, .image: previewURL = url
        case .script: break
        }
    }

    private func importFile(_ result: Result<URL, Error>, kind: DashboardLink.Kind, into schoolClass: SchoolClass) {
        do {
            let source = try result.get()
            let path = try LinkFileStore.importFile(from: source)
            let title = source.deletingPathExtension().lastPathComponent
            modelContext.insert(DashboardLink(title: title, kind: kind, location: path, schoolClass: schoolClass))
            try modelContext.save()
            toasts.success(kind == .image ? loc("Bild hinzugefügt") : loc("Dokument hinzugefügt"))
        } catch {
            toasts.error(loc("Import fehlgeschlagen: \(error.localizedDescription)"))
        }
    }

    private func importPhoto(_ item: PhotosPickerItem, into schoolClass: SchoolClass) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let path = try LinkFileStore.importData(data, filename: "Foto.\(fileExtension)")
            modelContext.insert(DashboardLink(title: "", kind: .image, location: path, schoolClass: schoolClass))
            try modelContext.save()
            toasts.success(loc("Foto hinzugefügt"))
        } catch {
            toasts.error(loc("Foto konnte nicht übernommen werden: \(error.localizedDescription)"))
        }
    }

    private func remove(_ link: DashboardLink) {
        LinkFileStore.removeFile(of: link)
        modelContext.delete(link)
        do {
            try modelContext.save()
            toasts.success(loc("Kachel entfernt"))
        } catch {
            toasts.error(loc("Entfernen fehlgeschlagen: \(error.localizedDescription)"))
        }
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
        case .randomStudent, .groups, .lastBoard, .checklists, .quickNote, .attendance:
            classToolCard(card, in: schoolClass)
        case .timer, .dateTime, .dailyBoost, .noiseMeter, .secretariat, .holidays:
            standaloneCard(card)
        case .currentLesson:
            CurrentLessonCard(
                schedule: LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots),
                visibleWeekdays: settings.visibleWeekdays
            ) {
                app.openCalendar(focusing: nil, at: .now)
            }
        case .weeklyHours:
            TimelineView(.periodic(from: .now, by: 60)) { context in
                WeeklyHoursCard(result: WeeklyWorkload.compute(
                    schedule: LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots),
                    now: context.date
                )) {
                    app.openCalendar(focusing: nil, at: .now)
                }
            }
        case .weather:
            WeatherCard(
                school: settings.values.school,
                federalStateName: HolidayImporter.federalStates.first { $0.code == settings.values.federalState }?.name
            )
        case .room:
            CurrentRoomCard(schedule: LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots), classID: schoolClass.id)
        }
    }

    /// Kacheln ohne Bezug zur Klasse und ohne Daten aus der Übersicht.
    @ViewBuilder
    private func standaloneCard(_ card: DashboardBuiltInCard) -> some View {
        switch card {
        case .timer: TimerCard()
        case .dateTime: DateTimeCard()
        case .noiseMeter: NoiseMeterCard()
        case .secretariat: SecretariatCard()
        case .holidays: HolidaysCard()
        default: DailyBoostCard()
        }
    }

    /// Eigene Kachel (Bild, Dokument, Website, Kurzbefehl) mit Bearbeiten-Menü.
    private func linkCard(_ link: DashboardLink, in schoolClass: SchoolClass) -> some View {
        Group {
            if link.kind == .image {
                ImageCard(link: link) { open(link) }
            } else if link.kind == .script {
                ScriptCard(link: link)
            } else {
                LinkCard(link: link) { open(link) }
            }
        }
        .contextMenu {
            if canEdit {
                Button("Bearbeiten", icon: .editPencil) { linkEditorRoute = .edit(link) }
                Button("Ausblenden", icon: .eyeClosed) { setHidden(true, link.cardID, in: schoolClass) }
                Button("Entfernen", destructiveIcon: .trash) { remove(link) }
            }
        }
    }

    /// Nächste Stunde der Klasse; öffnet den Kalender auf diese Klasse fokussiert.
    private func nextLessonCard(for schoolClass: SchoolClass) -> some View {
        let schedule = LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots)
        let next = schedule.nextLesson(forClass: schoolClass.id)
        return StatCard(
            title: loc("Nächste Stunde"),
            value: next.map { relativeDay($0.start) } ?? "–",
            detail: next.map { next in
                [loc("\(next.slot.number). Stunde, \(next.slot.start.clockString)"), SchoolClass.displayName(ofSubject: next.lesson.subject)]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
            } ?? loc("Noch keine Stunde im Kalender"),
            symbol: AppTab.calendar.symbol
        ) {
            app.openCalendar(focusing: schoolClass.id, at: next?.start)
        }
    }

    /// Nächster Geburtstag in der Klasse (heute zählt mit).
    private func nextBirthdayCard(for schoolClass: SchoolClass) -> some View {
        let upcoming = Birthdays.upcoming(in: schoolClass.students)
        return StatCard(
            title: DashboardBuiltInCard.nextBirthday.title,
            value: upcoming.first.map { RandomStudentCard.shortName($0.student) } ?? "–",
            detail: Birthdays.detail(for: upcoming),
            symbol: DashboardBuiltInCard.nextBirthday.symbol
        ) {
            app.open(.students)
        }
    }

    /// „♀ 46 % · ♂ 46 % · ⚧ 8 %“ (Anteile gerundet; ohne Angabe als „?“).
    private func genderBreakdown(_ students: [Student]) -> String {
        guard !students.isEmpty else { return loc("Noch keine Schüler") }
        let total = Double(students.count)
        var parts: [String] = Gender.allCases.compactMap { gender in
            let count = students.filter { $0.gender == gender }.count
            guard count > 0 else { return nil }
            return loc("\(gender.symbol) \(Int((Double(count) / total * 100).rounded())) %")
        }
        let unknown = students.filter { $0.gender == nil }.count
        if unknown > 0 { parts.append("? \(Int((Double(unknown) / total * 100).rounded())) %") }
        return parts.joined(separator: " · ")
    }

    private func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.school
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInTomorrow(date) { return loc("Morgen") }
        return date.appDate
    }
}
