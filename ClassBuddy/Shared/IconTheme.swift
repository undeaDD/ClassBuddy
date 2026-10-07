import SwiftUI
import UIKit

/// Icon-Set der App (App-Einstellungen → Icons). Alle Icons laufen über `AppIcon` und den
/// `IconManager`: Wechselt das Theme, zeichnet SwiftUI alle Stellen neu, die ein Icon zeigen.
nonisolated enum IconTheme: Identifiable, Hashable, Sendable {
    /// Eingebaute Iconoir-SVGs (Assets.xcassets/Icons).
    case builtIn
    /// SF Symbols von Apple – ohne zusätzliche Dateien.
    case sfSymbols
    /// Installiertes Paket (zip mit PDFs, siehe `IconPackStore`).
    case pack(IconPack)

    static let storageKey = "app.iconTheme"
    static let builtInThemes: [IconTheme] = [.builtIn, .sfSymbols]

    /// Gespeicherte Kennung: `builtIn`, `sfSymbols` oder `pack:<id>`.
    var id: String {
        switch self {
        case .builtIn: "builtIn"
        case .sfSymbols: "sfSymbols"
        case .pack(let pack): "pack:\(pack.id)"
        }
    }

    /// Installiertes Paket, falls das Theme eines ist.
    var pack: IconPack? {
        if case .pack(let pack) = self { pack } else { nil }
    }

    var title: String {
        switch self {
        case .builtIn: "Iconoir"
        case .sfSymbols: "SF Symbols"
        case .pack(let pack): pack.name
        }
    }

    /// Entsprechendes SF Symbol je Icon (alle Namen gegen das System geprüft).
    static let sfSymbolNames: [AppIcon: String] = [
        .app: "app",
        .arrowUpRight: "arrow.up.right",
        .bank: "building.columns",
        .birthday: "birthday.cake",
        .board: "tv",
        .bottomTabs: "inset.filled.bottomhalf.rectangle",
        .box: "shippingbox",
        .bug: "ladybug",
        .calendar: "calendar",
        .check: "checkmark",
        .checkmarkOff: "circle",
        .checkmarkOn: "checkmark.circle",
        .cloudDownload: "icloud.and.arrow.down",
        .code: "chevron.left.forwardslash.chevron.right",
        .coinsSwap: "arrow.triangle.2.circlepath",
        .community: "person.3",
        .data: "cylinder.split.1x2",
        .dice: "dice",
        .donate: "cup.and.saucer",
        .duplicate: "plus.square.on.square",
        .editPencil: "pencil",
        .eyeClosed: "eye.slash",
        .eye: "eye",
        .fillColor: "paint.bucket.classic",
        .fit: "arrow.up.right.and.arrow.down.left.rectangle",
        .fingerprintLockCircle: "touchid",
        .floorLayout: "square.split.bottomrightquarter",
        .genderUnknown: "circle",
        .gift: "gift",
        .githubCircle: "externaldrive",
        .globe: "globe",
        .graduationCap: "graduationcap",
        .graphUp: "chart.line.uptrend.xyaxis",
        .helpCircle: "questionmark.circle",
        .homeAlt: "house",
        .homeTable: "square.grid.2x2",
        .image: "photo",
        .`import`: "square.and.arrow.down",
        .label: "textformat",
        .link: "link",
        .lockSlash: "lock.open",
        .lock: "lock",
        .moreHoriz: "ellipsis",
        .navArrowDown: "chevron.down",
        .navArrowLeft: "chevron.left",
        .navArrowRight: "chevron.right",
        .navArrowUp: "chevron.up",
        .notes: "note.text",
        .number1Circle: "1.circle",
        .page: "doc",
        .palette: "paintpalette",
        .phone: "phone",
        .plus: "plus",
        .quoteSolid: "quote.opening",
        .redo: "arrow.uturn.forward",
        .search: "magnifyingglass",
        .sendMail: "envelope",
        .settings: "gearshape",
        .shareIos: "square.and.arrow.up",
        .shortcuts: "bolt.fill",
        .shuffle: "shuffle",
        .sineWave: "waveform.path",
        .swipeLeftGesture: "arrow.down.left.topright.rectangle.fill",
        .thumbsDown: "hand.thumbsdown",
        .thumbsUp: "hand.thumbsup",
        .temperature: "thermometer.medium",
        .time: "clock",
        .timer: "timer",
        .toastError: "xmark.circle",
        .toastSuccess: "checkmark.circle",
        .toastWarning: "exclamationmark.triangle",
        .translate: "character.bubble",
        .trash: "trash",
        .undo: "arrow.uturn.backward",
        .userCircle: "person.crop.circle",
        .userXmark: "person.crop.circle.badge.xmark",
        .version: "info.circle",
        .volume: "speaker.wave.2",
        .www: "network",
        .xmark: "xmark",
    ]
}

/// Liefert das Bild eines Icons im aktiven Theme. `theme` ist beobachtbar: Views, die beim Zeichnen
/// ein Icon abfragen, werden beim Wechsel automatisch neu gezeichnet.
@Observable
final class IconManager {
    static let shared = IconManager()

    var theme: IconTheme {
        didSet {
            UserDefaults.standard.set(theme.id, forKey: IconTheme.storageKey)
            packImages = [:]
        }
    }

    /// Installierte Pakete (Application Support/IconPacks).
    private(set) var packs: [IconPack]

    /// Gezeichnete Icons des aktiven Pakets (PDF → Bild nur einmal).
    @ObservationIgnored private var packImages: [AppIcon: UIImage] = [:]

    var themes: [IconTheme] { IconTheme.builtInThemes + packs.map(IconTheme.pack) }

    private init() {
        let installed = IconPackStore.installed()
        let stored = UserDefaults.standard.string(forKey: IconTheme.storageKey) ?? ""
        packs = installed
        theme = (IconTheme.builtInThemes + installed.map(IconTheme.pack)).first { $0.id == stored } ?? .builtIn
    }

    func image(_ icon: AppIcon) -> Image {
        switch theme {
        case .builtIn:
            Image(icon.resource)
        case .sfSymbols:
            IconTheme.sfSymbolNames[icon].map { Image(systemName: $0) } ?? Image(icon.resource)
        case .pack(let pack):
            packImage(icon, in: pack).map { Image(uiImage: $0) } ?? Image(icon.resource)
        }
    }

    func uiImage(_ icon: AppIcon) -> UIImage? {
        switch theme {
        case .builtIn:
            UIImage(resource: icon.resource)
        case .sfSymbols:
            IconTheme.sfSymbolNames[icon].flatMap { UIImage(systemName: $0) } ?? UIImage(resource: icon.resource)
        case .pack(let pack):
            packImage(icon, in: pack) ?? UIImage(resource: icon.resource)
        }
    }

    /// Vorschau eines Icons in einem bestimmten Theme (Auswahlliste in den Einstellungen).
    func preview(_ icon: AppIcon, in theme: IconTheme) -> Image {
        switch theme {
        case .builtIn: Image(icon.resource)
        case .sfSymbols: IconTheme.sfSymbolNames[icon].map { Image(systemName: $0) } ?? Image(icon.resource)
        case .pack(let pack): IconPackStore.image(for: icon, in: pack).map { Image(uiImage: $0) } ?? Image(icon.resource)
        }
    }

    func reloadPacks() {
        packs = IconPackStore.installed()
        if case .pack(let current) = theme, !packs.contains(where: { $0.id == current.id }) {
            theme = .builtIn
        }
    }

    func remove(_ pack: IconPack) {
        IconPackStore.remove(pack)
        reloadPacks()
    }

    private func packImage(_ icon: AppIcon, in pack: IconPack) -> UIImage? {
        if let cached = packImages[icon] { return cached }
        let image = IconPackStore.image(for: icon, in: pack)
        packImages[icon] = image
        return image
    }
}

extension AppIcon {
    /// Eingebautes SVG aus dem Asset-Katalog.
    var resource: ImageResource {
        ImageResource(name: rawValue, bundle: .main)
    }
}

// MARK: - Bequeme Varianten mit `icon:`

extension Image {
    /// Icon im aktiven Theme, z. B. `Image(icon: .trash)`.
    init(icon: AppIcon) {
        self = IconManager.shared.image(icon)
    }
}

extension Label where Title == Text, Icon == Image {
    init(_ titleKey: LocalizedStringKey, icon: AppIcon) {
        self.init { Text(titleKey) } icon: { Image(icon: icon) }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, icon: AppIcon) {
        self.init { Text(title) } icon: { Image(icon: icon) }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    init(_ titleKey: LocalizedStringKey, icon: AppIcon, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(titleKey, icon: icon) }
    }

    @_disfavoredOverload
    init<S: StringProtocol>(_ title: S, icon: AppIcon, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, icon: icon) }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    /// Löschen & Co. in Menüs (Kontextmenü, `Menu`): rote Schrift und **rotes** Icon – Menüs färben
    /// eigene Icons sonst nicht mit. Nicht für Wisch-Aktionen (dort weißes Icon auf Rot).
    init(_ titleKey: LocalizedStringKey, destructiveIcon icon: AppIcon, action: @escaping () -> Void) {
        self.init(role: .destructive, action: action) {
            SwiftUI.Label {
                Text(titleKey)
            } icon: {
                IconManager.shared.uiImage(icon)
                    .map { Image(uiImage: $0.withTintColor(.systemRed, renderingMode: .alwaysOriginal)) }
                    ?? Image(icon: icon)
            }
        }
    }
}
