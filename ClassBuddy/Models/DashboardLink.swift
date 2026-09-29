import Foundation
import SwiftData

/// Eigene Kachel auf der Übersicht einer Klasse: Dokument (Kopie im App-Container)
/// oder Website.
@Model
final class DashboardLink {
    nonisolated enum Kind: String, Codable {
        case file
        case website
        case image
        /// Kurzbefehl der Kurzbefehle-App (`location` = exakter Name).
        case shortcut

        /// Dokument/Bild: Kopie im App-Container (`LinkFileStore`).
        var isStoredFile: Bool { self == .file || self == .image }
    }

    @Attribute(.unique) var id: UUID
    var title: String
    var kindRaw: String
    /// Website: absolute URL. Dokument: Pfad relativ zu `LinkFileStore.directory`.
    var location: String
    var createdAt: Date
    var schoolClass: SchoolClass?

    init(id: UUID = UUID(), title: String, kind: Kind, location: String, schoolClass: SchoolClass?) {
        self.id = id
        self.title = title
        self.kindRaw = kind.rawValue
        self.location = location
        self.createdAt = .now
        self.schoolClass = schoolClass
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .website }

    /// ID für die Kachel-Reihenfolge der Übersicht.
    var cardID: String { "link.\(id.uuidString)" }

    var url: URL? {
        switch kind {
        case .website: URL(string: location)
        case .file, .image: LinkFileStore.directory.appending(path: location)
        case .shortcut: Self.shortcutURL(named: location)
        }
    }

    /// Startet einen Kurzbefehl über die Kurzbefehle-App.
    static func shortcutURL(named name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        // `&`, `=` und `+` sind in Query-Werten erlaubt und würden den Namen abschneiden → selbst kodieren.
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "name", value: name.addingPercentEncoding(withAllowedCharacters: allowed)),
        ]
        return components.url
    }

    /// Zweite Zeile: Host der Website bzw. Dateiname.
    var detail: String {
        switch kind {
        case .website: url?.host() ?? location
        case .file, .image: (location as NSString).lastPathComponent
        case .shortcut: location
        }
    }
}

/// Ablage für Dokumente der Übersichts-Kacheln (lokal, nicht in iCloud).
nonisolated enum LinkFileStore {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "DashboardFiles", directoryHint: .isDirectory)
    }

    /// Kopiert eine Datei (z. B. aus der Dateien-App) in die App.
    /// Gibt den relativen Pfad zurück.
    static func importFile(from source: URL) throws -> String {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let folder = UUID().uuidString
        let target = directory.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let destination = target.appending(path: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        return "\(folder)/\(source.lastPathComponent)"
    }

    /// Speichert Daten (z. B. ein Foto aus der Mediathek) als Datei in der App.
    static func importData(_ data: Data, filename: String) throws -> String {
        let folder = UUID().uuidString
        let target = directory.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try data.write(to: target.appending(path: filename))
        return "\(folder)/\(filename)"
    }

    static func removeFile(of link: DashboardLink) {
        guard link.kind.isStoredFile else { return }
        let folder = directory.appending(path: (link.location as NSString).deletingLastPathComponent)
        try? FileManager.default.removeItem(at: folder)
    }
}

extension URL {
    /// Unsichere oder für Kacheln ungeeignete Schemata (Klartext, lokale Dateien, Skripte …).
    static let blockedLinkSchemes: Set<String> = [
        "http", "ftp", "ftps", "sftp", "file", "data", "javascript", "vbscript", "about", "blob",
        "ws", "wss", "smb", "afp", "ssh", "telnet", "vnc",
    ]

    /// Nutzereingabe → Link für Kacheln und die Schul-Website.
    /// Erlaubt: `https://…`, Adressen ohne Schema (werden zu https) und App-Links
    /// (`notability://…`, `mailto:`, `tel:` …). Abgelehnt: http, ftp, file, javascript usw.
    static func web(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }

        guard let scheme = explicitScheme(of: trimmed) else {
            let url = URL(string: "https://\(trimmed)")
            return url?.host() == nil ? nil : url
        }
        switch scheme {
        case "https":
            let url = URL(string: trimmed)
            return url?.host() == nil ? nil : url
        case _ where blockedLinkSchemes.contains(scheme):
            return nil
        default:
            // App-Link: Schema plus Inhalt nötig.
            return trimmed.count > scheme.count + 1 ? URL(string: trimmed) : nil
        }
    }

    /// Schema einer Eingabe („https“, „notability“ …) – „schule.de:8080“ ist ein Port, kein Schema.
    private static func explicitScheme(of text: String) -> String? {
        guard let match = text.firstMatch(of: /^([A-Za-z][A-Za-z0-9+.\-]*):(.*)$/) else { return nil }
        let rest = match.2
        if rest.first?.isNumber == true { return nil }
        return String(match.1).lowercased()
    }
}
