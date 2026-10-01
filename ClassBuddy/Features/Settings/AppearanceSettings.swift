import SwiftUI

/// Vorgaben als Farbkreise plus eigene Farbe (systemeigene Farbauswahl) – wirkt sofort.
struct AccentColorGrid: View {
    @Binding var selection: String
    @AppStorage("app.lastCustomAccent") private var lastCustomColor = "#2F6FDE"

    private var isCustom: Bool { !AppAccent.presets.contains { $0.id == selection } }

    var body: some View {
        // Bricht auf schmalen Bildschirmen in mehrere Zeilen um.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(AppAccent.presets) { preset in
                Circle()
                    .fill(Color(uiColor: preset.color).gradient)
                    .frame(width: 36, height: 36)
                    .overlay {
                        if preset.id == selection { check }
                    }
                    .onTapGesture {
                        Haptics.selection()
                        selection = preset.id
                    }
                    .hoverEffect(.lift)
                    .accessibilityLabel(Text(preset.name))
                    .accessibilityAddTraits(preset.id == selection ? .isSelected : [])
            }
            ColorPicker(
                "Eigene Farbe",
                selection: Binding(
                    get: { Color(hex: isCustom ? selection : lastCustomColor) ?? .blue },
                    set: { newColor in
                        lastCustomColor = newColor.hexString
                        selection = newColor.hexString
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 36, height: 36)
            .overlay {
                if isCustom { check }
            }
            .accessibilityAddTraits(isCustom ? .isSelected : [])
        }
        .padding(.vertical, 4)
    }

    private var check: some View {
        Image(icon: .check)
            .iconSize(18)
            .foregroundStyle(.white)
            .allowsHitTesting(false)
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
        } header: {
            Text("Icons")
        } footer: {
            Text("Fehlende Icons eines Pakets erscheinen im Iconoir-Stil. Pakete per Wischen entfernen.")
        }
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
        .swipeActions(edge: .trailing) {
            if case .pack(let pack) = theme {
                Button("Entfernen", icon: .trash, role: .destructive) {
                    manager.remove(pack)
                    HomeScreenAction.register()
                    toasts.success(loc("„\(pack.name)“ entfernt"))
                }
                // Lädt das zip erneut von derselben Adresse (ersetzt das installierte Paket).
                if let source = pack.sourceURL.flatMap(URL.init(string:)) {
                    Button("Aktualisieren", icon: .import) { update(from: source) }
                        .tint(accent)
                }
            }
        }
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
