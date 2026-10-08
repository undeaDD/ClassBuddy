import Foundation
import UIKit

/// Installiertes Icon-Paket (zip aus `scripts/build-icon-pack.sh`): `manifest.json` plus je Icon
/// eine PDF (`calendar.pdf` …). Liegt lokal in Application Support/IconPacks/<id>/.
nonisolated struct IconPack: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var author: String?
    var version: String?
    var license: String?
    var url: String?
    /// Adresse, von der das Paket geladen wurde (für „Aktualisieren“); nicht Teil des Manifests im zip.
    var sourceURL: String?

    var directory: URL { IconPackStore.directory.appending(path: id, directoryHint: .isDirectory) }

    func pdfURL(for icon: AppIcon) -> URL {
        directory.appending(path: "\(icon.rawValue).pdf")
    }
}

/// Installieren, Auflisten und Entfernen von Icon-Paketen.
nonisolated enum IconPackStore {
    enum InstallError: LocalizedError, Equatable {
        case notHTTPS
        case tooLarge
        case download(String)
        case invalidArchive
        case missingManifest
        case invalidManifest
        case noIcons

        var errorDescription: String? {
            switch self {
            case .notHTTPS: loc("Nur https-Adressen sind erlaubt.")
            case .tooLarge: loc("Das Paket ist zu groß (höchstens 20 MB).")
            case .download(let reason): loc("Download fehlgeschlagen: \(reason)")
            case .invalidArchive: loc("Die Datei ist kein gültiges zip-Archiv.")
            case .missingManifest: loc("manifest.json fehlt im Paket.")
            case .invalidManifest: loc("manifest.json ist ungültig (id und name nötig, id nur a–z, 0–9 und -).")
            case .noIcons: loc("Das Paket enthält keine passenden Icons.")
            }
        }
    }

    static let maxArchiveSize = 20 * 1024 * 1024
    static let maxIconSize = 512 * 1024

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "IconPacks", directoryHint: .isDirectory)
    }

    static func installed() -> [IconPack] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders
            .compactMap { folder in
                (try? Data(contentsOf: folder.appending(path: "manifest.json")))
                    .flatMap { try? JSONDecoder().decode(IconPack.self, from: $0) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Lädt ein Paket per https (ohne Cookies) und installiert es.
    static func download(from url: URL) async throws -> IconPack {
        guard url.scheme?.lowercased() == "https" else { throw InstallError.notHTTPS }
        let session = URLSession(configuration: .ephemeral)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw InstallError.download(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InstallError.download("HTTP \(http.statusCode)")
        }
        var pack = try install(archive: data)
        pack.sourceURL = url.absoluteString
        try JSONEncoder().encode(pack).write(to: pack.directory.appending(path: "manifest.json"))
        return pack
    }

    /// Prüft und installiert ein zip: nur `manifest.json` und `<bekanntes Icon>.pdf` werden übernommen.
    /// Ein Paket mit gleicher id wird ersetzt.
    static func install(archive data: Data) throws -> IconPack {
        guard data.count <= maxArchiveSize else { throw InstallError.tooLarge }
        guard let files = try? ZipArchive.read(data) else { throw InstallError.invalidArchive }
        // Dateien auch in einem Unterordner des zips finden (z. B. „FontAwesome/calendar.pdf“).
        let byName = Dictionary(files.map { (($0.key as NSString).lastPathComponent, $0.value) }, uniquingKeysWith: { first, _ in first })
        guard let manifestData = byName["manifest.json"] else { throw InstallError.missingManifest }
        guard let pack = try? JSONDecoder().decode(IconPack.self, from: manifestData),
              pack.id.range(of: "^[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil,
              !pack.name.trimmingCharacters(in: .whitespaces).isEmpty
        else { throw InstallError.invalidManifest }

        let icons = AppIcon.allCases.compactMap { icon -> (AppIcon, Data)? in
            guard let pdf = byName["\(icon.rawValue).pdf"], pdf.count <= maxIconSize, pdf.starts(with: Data("%PDF".utf8)) else { return nil }
            return (icon, pdf)
        }
        guard !icons.isEmpty else { throw InstallError.noIcons }

        let target = pack.directory
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: target)
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        try JSONEncoder().encode(pack).write(to: target.appending(path: "manifest.json"))
        for (icon, pdf) in icons {
            try pdf.write(to: pack.pdfURL(for: icon))
        }
        return pack
    }

    static func remove(_ pack: IconPack) {
        try? FileManager.default.removeItem(at: pack.directory)
    }

    /// Zeichnet die PDF eines Icons als Vorlagenbild (färbbar, Transparenz bleibt) in 24 pt,
    /// mit genug Pixeln für große Darstellungen (z. B. Leerzustände).
    static func image(for icon: AppIcon, in pack: IconPack) -> UIImage? {
        guard let provider = CGDataProvider(url: pack.pdfURL(for: icon) as CFURL),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1)
        else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let size: CGFloat = 24
        let format = UIGraphicsImageRendererFormat()
        format.scale = 8
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let cgContext = context.cgContext
            let scale = min(size / box.width, size / box.height)
            cgContext.translateBy(x: (size - box.width * scale) / 2, y: (size + box.height * scale) / 2)
            cgContext.scaleBy(x: scale, y: -scale)
            cgContext.translateBy(x: -box.minX, y: -box.minY)
            cgContext.drawPDFPage(page)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
