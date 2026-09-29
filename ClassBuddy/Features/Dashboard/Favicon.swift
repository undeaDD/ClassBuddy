import SwiftUI
import UIKit

/// Lädt und cacht Website-Icons (Favicons) lokal.
/// Fragt nur die Website selbst an – kein Drittanbieter-Dienst.
/// Reihenfolge: <link rel="apple-touch-icon"/"icon"> aus dem HTML,
/// dann /apple-touch-icon.png und /favicon.ico.
nonisolated enum FaviconStore {
    static var directory: URL {
        URL.cachesDirectory.appending(path: "Favicons", directoryHint: .isDirectory)
    }

    private static func cacheFile(for host: String) -> URL {
        let safe = host.lowercased().replacingOccurrences(of: "[^a-z0-9.-]", with: "_", options: .regularExpression)
        return directory.appending(path: "\(safe).png")
    }

    static func cachedImage(for host: String) -> UIImage? {
        guard let data = try? Data(contentsOf: cacheFile(for: host)) else { return nil }
        return UIImage(data: data)
    }

    /// Favicon laden (Cache zuerst). `nil`, wenn nichts Brauchbares gefunden wurde.
    static func image(for pageURL: URL) async -> UIImage? {
        guard let host = pageURL.host() else { return nil }
        if let cached = cachedImage(for: host) { return cached }

        for candidate in await candidates(for: pageURL) {
            guard let image = await download(candidate) else { continue }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? image.pngData()?.write(to: cacheFile(for: host))
            return image
        }
        return nil
    }

    private static func candidates(for pageURL: URL) async -> [URL] {
        var result: [URL] = []
        if let html = await fetchHTML(pageURL) {
            result += iconLinks(in: html, baseURL: pageURL)
        }
        if let root = URL(string: "/", relativeTo: pageURL) {
            result.append(root.appending(path: "apple-touch-icon.png"))
            result.append(root.appending(path: "favicon.ico"))
        }
        return result
    }

    private static func fetchHTML(_ url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return String(decoding: data.prefix(300_000), as: UTF8.self)
    }

    /// `<link rel="…icon…" href="…">` – Apple-Touch-Icons zuerst (größer, schärfer).
    private static func iconLinks(in html: String, baseURL: URL) -> [URL] {
        guard let linkRegex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var touch: [URL] = []
        var icons: [URL] = []
        for match in linkRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let rel = attribute("rel", in: tag)?.lowercased(), rel.contains("icon"),
                  let href = attribute("href", in: tag),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL
            else { continue }
            if rel.contains("apple-touch-icon") { touch.append(url) } else { icons.append(url) }
        }
        return touch + icons
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\(name)\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag)
        else { return nil }
        return String(tag[range])
    }

    private static func download(_ url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data),
              image.size.width >= 16
        else { return nil }
        return image
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Favicon einer Website, mit Platzhalter-Icon solange nichts geladen ist.
struct FaviconView: View {
    let url: URL?
    var size: CGFloat = 24
    var placeholder: AppSymbol = .custom(.www)

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: size * 0.22, style: .continuous))
            } else {
                placeholder.image
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            guard let url else { return }
            if let host = url.host(), let cached = FaviconStore.cachedImage(for: host) {
                image = cached
            } else {
                image = await FaviconStore.image(for: url)
            }
        }
    }
}
