import SwiftUI

/// Eine Zeile mit der systemeigenen Farbauswahl rechts – wirkt sofort.
/// Gespeicherte Vorgaben (`amber`, `blue` …) zeigt der Farbwähler als ihre Farbe an.
struct AccentColorRow: View {
    @Binding var selection: String

    var body: some View {
        ColorPicker(
            selection: Binding(
                get: { AppAccent.color(for: selection) },
                set: { selection = $0.hexString }
            ),
            supportsOpacity: false
        ) {
            Label("Akzentfarbe", icon: .fillColor)
        }
    }
}

/// Icon-Themes: eingebaut, SF Symbols und Pakete, die per URL geladen und lokal gespeichert werden
/// (zip, siehe `scripts/build-icon-pack.sh`).
/// Jede Zeile zeigt als Vorschau das Zahnrad im jeweiligen Stil; Pakete per Wischen entfernen.
struct IconThemeSection: View {
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.appAccent) private var accent
    @State private var isURLPromptPresented = false
    @State private var urlText = ""
    @State private var isDownloading = false

    private var manager: IconManager { IconManager.shared }

    var body: some View {
        Section {
            ForEach(manager.themes) { theme in
                row(for: theme)
            }
            Button {
                isURLPromptPresented = true
            } label: {
                SettingsActionLabel(title: loc("Paket von URL laden"), icon: .cloudDownload, isLoading: isDownloading)
            }
            .disabled(isDownloading)
            // An der Zeile, nicht an der Section (sonst hängt jede Zeile ein eigenes Alert an).
            .alert("Paket von URL laden", isPresented: $isURLPromptPresented) {
                TextField("https://…/paket.zip", text: $urlText)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Abbrechen", role: .cancel) {}
                Button("Laden") { download() }
            } message: {
                Text("Ein zip mit manifest.json und PDF-Icons, erstellt mit scripts/build-icon-pack.sh.")
            }
        } header: {
            Text("Icons")
        } footer: {
            Text("Fehlende Icons eines Pakets erscheinen im Iconoir-Stil. Pakete per Wischen entfernen.")
        }
    }

    private func row(for theme: IconTheme) -> some View {
        let isSelected = manager.theme == theme
        return Button {
            Haptics.selection()
            withAnimation(.smooth) { manager.theme = theme }
            HomeScreenAction.register()
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: theme.title).foregroundStyle(Color.primary)
                        if case .pack(let pack) = theme, let author = pack.author {
                            Text(verbatim: [author, pack.version].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    manager.preview(.settings, in: theme)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                Spacer()
                if isSelected {
                    Image(icon: .check)
                        .iconSize(20)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // Pakete: nach rechts wischen = Aktualisieren (lädt das zip erneut von derselben Adresse),
        // nach links wischen = Entfernen; beides auch per langem Drücken.
        .swipeActions(edge: .leading) {
            if let source = theme.pack?.sourceURL.flatMap({ URL(string: $0) }) {
                Button("Aktualisieren", icon: .import) { update(from: source) }
                    .tint(accent)
            }
        }
        .swipeActions(edge: .trailing) {
            if let pack = theme.pack {
                Button("Entfernen", icon: .trash, role: .destructive) { remove(pack) }
            }
        }
        .contextMenu {
            if let pack = theme.pack {
                if let source = pack.sourceURL.flatMap({ URL(string: $0) }) {
                    Button("Aktualisieren", icon: .import) { update(from: source) }
                }
                Button("Entfernen", destructiveIcon: .trash) { remove(pack) }
            }
        }
    }

    private func remove(_ pack: IconPack) {
        manager.remove(pack)
        HomeScreenAction.register()
        toasts.success(loc("„\(pack.name)“ entfernt"))
    }

    private func update(from url: URL) {
        isDownloading = true
        Task {
            defer { isDownloading = false }
            do {
                let pack = try await IconPackStore.download(from: url)
                manager.reloadPacks()
                withAnimation(.smooth) { manager.theme = .pack(pack) }
                HomeScreenAction.register()
                toasts.success(loc("„\(pack.name)“ aktualisiert"))
            } catch {
                toasts.error(error.localizedDescription)
            }
        }
    }

    private func download() {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme?.lowercased() == "https" else {
            toasts.error(loc("Nur https-Adressen sind erlaubt."))
            return
        }
        isDownloading = true
        Task {
            defer { isDownloading = false }
            do {
                finishInstall(try await IconPackStore.download(from: url))
                urlText = ""
            } catch {
                toasts.error(error.localizedDescription)
            }
        }
    }

    /// Installiertes Paket gleich aktivieren.
    private func finishInstall(_ pack: IconPack) {
        manager.reloadPacks()
        withAnimation(.smooth) { manager.theme = .pack(pack) }
        HomeScreenAction.register()
        toasts.success(loc("„\(pack.name)“ installiert"))
    }
}
