// App-Store-Bilder aus Roh-Screenshots zusammensetzen (Hintergrund, Überschrift, Geräte im Ton-Look).
// Aufruf über scripts/appstore-images.sh (setzt das Arbeitsverzeichnis auf das Repo).
//
// Eingaben
//   Marketing/captions.json                         Texte (de/en) und Farben
//   build/AppStore/raw/<sprache>/<gerät>/<seite>.png  Roh-Screenshots (scripts/appstore-screenshots.sh)
//     Rückfall: docs/screenshots/<gerät>/<seite>.png, sonst ein beschrifteter Platzhalter
//   Marketing/Frames/<gerät>.png + <gerät>.json     optionale Geräterahmen (sonst gezeichneter Ton-Rahmen),
//     JSON: {"screen": [x, y, breite, höhe], "cornerRadius": r} in Pixeln des Rahmenbilds (Ursprung oben links)
//   docs/app-icon.png                               App-Icon für die Kopfzeile
// Ausgabe: build/AppStore/<sprache>/{header,search}.png, …/iphone|duo/NN-seite.png (1920 × 886),
//          …/ipad/NN-seite.png (1600 × 1200) – ohne Alphakanal, wie App Store Connect es verlangt.

import AppKit
import Foundation

// MARK: Konfiguration

struct Captions: Decodable {
    struct Colors: Decodable {
        let backgroundTop, backgroundBottom, title, subtitle, accent, clay: String
    }

    struct Header: Decodable {
        let title, subtitle, note: [String: String]
        let screens: [String: String]
    }

    struct Search: Decodable {
        let title: [String: String]
        let screens: [String]
    }

    struct Screen: Decodable {
        let id: String
        let title, subtitle: [String: String]
    }

    let colors: Colors
    let colorsDark: Colors
    let header: Header
    let search: Search
    let screens: [Screen]
}

enum Device: String, CaseIterable {
    case iphone, ipad, duo

    /// Seitenverhältnis des Bildschirms (Breite / Höhe) für Platzhalter ohne Screenshot.
    var placeholderAspect: CGFloat {
        switch self {
        case .iphone: 1206 / 2622
        case .ipad: 2064 / 2752
        case .duo: 1206 / 2622
        }
    }

    /// Rahmenstärke des gezeichneten Ton-Rahmens relativ zur Bildschirmbreite.
    var bezelRatio: CGFloat { self == .ipad ? 0.035 : 0.05 }
    /// Eckenradius des Bildschirms relativ zur Bildschirmbreite.
    var cornerRatio: CGFloat { self == .ipad ? 0.045 : 0.13 }

    var outputSize: CGSize { self == .ipad ? CGSize(width: 1600, height: 1200) : CGSize(width: 1920, height: 886) }
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let captions = try JSONDecoder().decode(Captions.self, from: Data(contentsOf: root.appending(path: "Marketing/captions.json")))
let languages = (ProcessInfo.processInfo.environment["LANGUAGES"] ?? "de").split(separator: " ").map(String.init)
let appearances = (ProcessInfo.processInfo.environment["APPEARANCES"] ?? "light dark").split(separator: " ").map(String.init)
/// Aktuelles Erscheinungsbild beim Rendern (Farben und Screenshots `-dark`).
nonisolated(unsafe) var isDark = false
var palette: Captions.Colors { isDark ? captions.colorsDark : captions.colors }

// MARK: Hilfen

func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return CGColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255, alpha: alpha
    )
}

func loadImage(_ url: URL) -> CGImage? {
    guard fileManager.fileExists(atPath: url.path), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func screenshot(_ device: Device, _ screen: String, language: String) -> CGImage? {
    let name = isDark ? "\(screen)-dark" : screen
    return loadImage(root.appending(path: "build/AppStore/raw/\(language)/\(device.rawValue)/\(name).png"))
        ?? loadImage(root.appending(path: "docs/screenshots/\(device.rawValue)/\(name).png"))
}

struct Frame {
    let image: CGImage
    /// Bildschirmbereich im Rahmenbild (Ursprung oben links).
    let screen: CGRect
    let cornerRadius: CGFloat

    static func load(_ device: Device) -> Frame? {
        struct Spec: Decodable { let screen: [CGFloat]; let cornerRadius: CGFloat }
        let base = root.appending(path: "Marketing/Frames/\(device.rawValue)")
        guard let image = loadImage(base.appendingPathExtension("png")),
              let data = try? Data(contentsOf: base.appendingPathExtension("json")),
              let spec = try? JSONDecoder().decode(Spec.self, from: data), spec.screen.count == 4
        else { return nil }
        return Frame(image: image, screen: CGRect(x: spec.screen[0], y: spec.screen[1], width: spec.screen[2], height: spec.screen[3]),
                     cornerRadius: spec.cornerRadius)
    }
}

let frames = Dictionary(uniqueKeysWithValues: Device.allCases.compactMap { device in Frame.load(device).map { (device, $0) } })

/// Zeichenfläche mit Koordinaten von oben links (wie in Design-Tools).
final class Canvas {
    let size: CGSize
    let context: CGContext

    init(_ size: CGSize) {
        self.size = size
        context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    }

    func background() {
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [color(palette.backgroundTop), color(palette.backgroundBottom)] as CFArray, locations: [0, 1]
        )!
        // Über Start und Ende hinaus weiterzeichnen – sonst bleiben die Ecken schwarz.
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.3, y: size.height),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Bild aufrecht zeichnen (Kontext ist gespiegelt).
    func draw(_ image: CGImage, in rect: CGRect) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// Text in einem Rechteck, umbrechend; gibt die tatsächlich belegte Höhe zurück.
    @discardableResult
    func text(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight, color hex: String,
              alignment: NSTextAlignment = .left) -> CGFloat {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineHeightMultiple = 1.05
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: color(hex)) ?? .black, .paragraphStyle: paragraph,
        ])
        let bounds = attributed.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
        attributed.draw(with: CGRect(origin: rect.origin, size: CGSize(width: rect.width, height: ceil(bounds.height))),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(bounds.height)
    }

    /// Gerät mit Screenshot; `screenHeight` = Höhe des Bildschirms, oben mittig an `top` / `centerX`.
    func device(_ device: Device, image: CGImage?, label: String, centerX: CGFloat, top: CGFloat, screenHeight: CGFloat) {
        let aspect = image.map { CGFloat($0.width) / CGFloat($0.height) } ?? device.placeholderAspect
        let screen = CGRect(x: centerX - screenHeight * aspect / 2, y: top, width: screenHeight * aspect, height: screenHeight)
        if let frame = frames[device] {
            let scale = screen.width / frame.screen.width
            let frameRect = CGRect(
                x: screen.minX - frame.screen.minX * scale, y: screen.minY - frame.screen.minY * scale,
                width: CGFloat(frame.image.width) * scale, height: CGFloat(frame.image.height) * scale
            )
            shadow(for: frameRect, radius: frame.cornerRadius * scale)
            screenContent(image, label: label, in: screen, radius: frame.cornerRadius * scale)
            draw(frame.image, in: frameRect)
        } else {
            // Ton-Rahmen: matte, helle Hülle mit weichem Schatten und leichter Kante.
            let bezel = screen.width * device.bezelRatio
            let radius = screen.width * device.cornerRatio
            let outer = screen.insetBy(dx: -bezel, dy: -bezel)
            shadow(for: outer, radius: radius + bezel)
            context.saveGState()
            context.addPath(CGPath(roundedRect: outer, cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
            context.clip()
            let clay = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: (isDark ? [color("#4A423B"), color(palette.clay), color("#24201C")]
                                : [color("#FFFFFF"), color(palette.clay), color("#DDD5CC")]) as CFArray, locations: [0, 0.55, 1]
            )!
            context.drawLinearGradient(clay, start: CGPoint(x: outer.minX, y: outer.minY), end: CGPoint(x: outer.maxX, y: outer.maxY), options: [])
            context.restoreGState()
            screenContent(image, label: label, in: screen, radius: radius)
        }
    }

    private func shadow(for rect: CGRect, radius: CGFloat) {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: rect.height * 0.025), blur: rect.height * 0.06,
                          color: color(isDark ? "#000000" : "#3B2A1A", alpha: isDark ? 0.6 : 0.28))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(color(palette.clay))
        context.fillPath()
        context.restoreGState()
    }

    private func screenContent(_ image: CGImage?, label: String, in rect: CGRect, radius: CGFloat) {
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        if let image {
            draw(image, in: rect)
        } else {
            context.setFillColor(color(isDark ? "#1C1C1E" : "#FFFFFF"))
            context.fill(rect)
            text("Screenshot\n„\(label)“", in: rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.45),
                 size: rect.width * 0.07, weight: .semibold, color: palette.subtitle, alignment: .center)
        }
        context.restoreGState()
    }

    func save(_ url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        print("  ✓ \(url.path.replacingOccurrences(of: root.path + "/", with: "")) (\(image.width) × \(image.height))")
    }
}

// MARK: Layouts

let output = root.appending(path: "build/AppStore")
let wide = CGSize(width: 5244, height: 2950)

/// Kopfzeile der Produktseite: Icon, Name, Claim links; iPad und iPhone rechts.
func header(_ language: String) throws {
    let canvas = Canvas(wide)
    canvas.background()
    let h = wide.height
    if let icon = loadImage(root.appending(path: "docs/app-icon.png")) {
        let size = h * 0.16
        let rect = CGRect(x: wide.width * 0.07, y: h * 0.26, width: size, height: size)
        canvas.context.saveGState()
        canvas.context.addPath(CGPath(roundedRect: rect, cornerWidth: size * 0.225, cornerHeight: size * 0.225, transform: nil))
        canvas.context.clip()
        canvas.draw(icon, in: rect)
        canvas.context.restoreGState()
    }
    let textX = wide.width * 0.07
    var y = h * 0.47
    y += canvas.text(captions.header.title[language] ?? "", in: CGRect(x: textX, y: y, width: wide.width * 0.4, height: h * 0.2),
                     size: h * 0.1, weight: .heavy, color: palette.title) + h * 0.015
    y += canvas.text(captions.header.subtitle[language] ?? "", in: CGRect(x: textX, y: y, width: wide.width * 0.38, height: h * 0.2),
                     size: h * 0.05, weight: .semibold, color: palette.subtitle) + h * 0.03
    canvas.text(captions.header.note[language] ?? "", in: CGRect(x: textX, y: y, width: wide.width * 0.38, height: h * 0.15),
                size: h * 0.032, weight: .medium, color: palette.accent)

    let ipadScreen = captions.header.screens["ipad"] ?? "dashboard"
    let iphoneScreen = captions.header.screens["iphone"] ?? "calendar"
    canvas.device(.ipad, image: screenshot(.ipad, ipadScreen, language: language), label: ipadScreen,
                  centerX: wide.width * 0.66, top: h * 0.12, screenHeight: h * 0.95)
    canvas.device(.iphone, image: screenshot(.iphone, iphoneScreen, language: language), label: iphoneScreen,
                  centerX: wide.width * 0.86, top: h * 0.3, screenHeight: h * 0.82)
    try canvas.save(output.appending(path: "\(folder(language))/header.png"))
}

/// Suchergebnis-Zeile: Überschrift oben, drei iPhones nebeneinander.
func search(_ language: String) throws {
    let canvas = Canvas(wide)
    canvas.background()
    let h = wide.height
    canvas.text(captions.search.title[language] ?? "", in: CGRect(x: wide.width * 0.1, y: h * 0.07, width: wide.width * 0.8, height: h * 0.2),
                size: h * 0.075, weight: .heavy, color: palette.title, alignment: .center)
    for (index, screen) in captions.search.screens.prefix(3).enumerated() {
        canvas.device(.iphone, image: screenshot(.iphone, screen, language: language), label: screen,
                      centerX: wide.width * (0.22 + 0.28 * CGFloat(index)), top: h * 0.25, screenHeight: h * 0.95)
    }
    try canvas.save(output.appending(path: "\(folder(language))/search.png"))
}

/// Einzelbild je Seite: iPhone/Duo quer (Text links, Gerät rechts), iPad mit Text oben.
func screenImages(_ device: Device, _ language: String) throws {
    for (index, screen) in captions.screens.enumerated() {
        let size = device.outputSize
        let canvas = Canvas(size)
        canvas.background()
        let title = screen.title[language] ?? ""
        let subtitle = screen.subtitle[language] ?? ""
        let image = screenshot(device, screen.id, language: language)
        if device == .ipad {
            var y = size.height * 0.07
            y += canvas.text(title, in: CGRect(x: size.width * 0.08, y: y, width: size.width * 0.84, height: size.height * 0.2),
                             size: size.height * 0.058, weight: .heavy, color: palette.title, alignment: .center)
            canvas.text(subtitle, in: CGRect(x: size.width * 0.1, y: y + size.height * 0.012, width: size.width * 0.8, height: size.height * 0.1),
                        size: size.height * 0.03, weight: .medium, color: palette.subtitle, alignment: .center)
            canvas.device(.ipad, image: image, label: screen.id, centerX: size.width / 2, top: size.height * 0.27, screenHeight: size.height * 1.05)
        } else {
            let textRect = CGRect(x: size.width * 0.07, y: 0, width: size.width * 0.46, height: size.height)
            let titleSize = size.height * 0.085
            let subtitleSize = size.height * 0.042
            // Vertikal mittig: Höhe grob schätzen (zwei Zeilen Titel, eine bis zwei Zeilen Untertitel).
            var y = size.height * 0.3
            y += canvas.text(title, in: CGRect(x: textRect.minX, y: y, width: textRect.width, height: size.height * 0.4),
                             size: titleSize, weight: .heavy, color: palette.title) + size.height * 0.03
            canvas.text(subtitle, in: CGRect(x: textRect.minX, y: y, width: textRect.width * 0.92, height: size.height * 0.3),
                        size: subtitleSize, weight: .medium, color: palette.subtitle)
            canvas.device(device, image: image, label: screen.id, centerX: size.width * 0.75, top: size.height * 0.12,
                          screenHeight: size.height * 1.15)
        }
        let name = String(format: "%02d-%@.png", index + 1, screen.id)
        try canvas.save(output.appending(path: "\(folder(language))/\(device.rawValue)/\(name)"))
    }
}

/// build/AppStore/de bzw. build/AppStore/de-dark
func folder(_ language: String) -> String { isDark ? "\(language)-dark" : language }

print("▸ Rahmen: " + (frames.isEmpty ? "gezeichneter Ton-Rahmen (keine Marketing/Frames/*.png)" : frames.keys.map(\.rawValue).sorted().joined(separator: ", ")))
for appearance in appearances {
isDark = appearance == "dark"
for language in languages {
    print("▸ \(folder(language))")
    try header(language)
    try search(language)
    for device in Device.allCases {
        try screenImages(device, language)
    }
}
}
print("✓ build/AppStore/")
