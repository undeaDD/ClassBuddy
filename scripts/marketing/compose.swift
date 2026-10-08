// App-Store-Bilder aus Roh-Screenshots: Tafel-Hintergrund, Kreideschrift, Geräte-Bezels (leicht gedreht).
// Aufruf über scripts/appstore-images.sh (setzt das Arbeitsverzeichnis auf das Repo).
//
// Eingaben
//   Marketing/captions.json                            Texte, Farben, Seiten fürs Store-Panorama (`storeScreens`)
//   Marketing/Frames/<gerät>.json                      Bildschirmbereich im Bezel (im Repo)
//   Marketing/Assets/<gerät>.png, chalkboard.jpg, chalk.ttf   Bezels, Tafel, Kreideschrift (nicht im Repo)
//   build/AppStore/raw/<sprache>/<gerät>/<seite>[-dark].png   Roh-Screenshots (scripts/appstore-screenshots.sh)
// Fehlt ein Asset, gibt es Ersatz: gezeichneter Rahmen, Verlauf, Systemschrift, beschrifteter Platzhalter.
//
// Ausgabe (ohne Alphakanal): build/AppStore/<sprache>[-dark]/
//   header.png, search.png                     5244 × 2950
//   iphone/NN-seite.png                        1206 × 2622 (Hochformat, 6,3″) – Tafel läuft als Panorama über alle Bilder
//   duo/NN-seite.png                           1398 × 2034 (Hochformat)        – ebenso
//   ipad/NN-seite.png                          2064 × 2752 (Hochformat, 13″)   – ebenso
// (Bildschirmfotos brauchen die nativen Display-Größen; 1920 × 886 bzw. 1600 × 1200 sind nur für App-Vorschau-Videos.)

import AppKit
import CoreImage
import CoreText
import Foundation

// MARK: Konfiguration

struct Captions: Decodable {
    struct Chalk: Decodable {
        let title, subtitle, accent: String
    }

    struct Header: Decodable {
        let title, subtitle: [String: String]
    }

    struct Search: Decodable {
        /// Seite fürs Suchergebnis-Bild (Titel der Seite links, iPhone rechts); der App Store zeigt nur eins.
        let screens: [String]
    }

    struct Screen: Decodable {
        let id: String
        let title, subtitle: [String: String]
    }

    let chalk: Chalk
    let storeScreens: [String]
    /// Store-Bilder, die auch im hellen Satz dunkle Screenshots zeigen (Abwechslung im Panorama).
    let darkStoreScreens: [String]?
    let header: Header
    let search: Search
    let screens: [Screen]
}

enum Device: String, CaseIterable {
    case iphone, ipad, duo
    case duoOpen = "duo-open"

    /// Seitenverhältnis des Bildschirms (Breite / Höhe) für Platzhalter ohne Bezel und Screenshot.
    var placeholderAspect: CGFloat {
        switch self {
        case .iphone: 1206 / 2622
        case .ipad: 2064 / 2752
        case .duo: 1398 / 2034
        case .duoOpen: 2853 / 2007
        }
    }
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let assets = root.appending(path: "Marketing/Assets")
let captions = try JSONDecoder().decode(Captions.self, from: Data(contentsOf: root.appending(path: "Marketing/captions.json")))
let languages = (ProcessInfo.processInfo.environment["LANGUAGES"] ?? "de").split(separator: " ").map(String.init)
let appearances = (ProcessInfo.processInfo.environment["APPEARANCES"] ?? "light dark").split(separator: " ").map(String.init)
/// Aktuelles Erscheinungsbild beim Rendern (nur die Screenshots wechseln, die Tafel bleibt).
nonisolated(unsafe) var isDark = false

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

func screenshot(_ device: Device, _ screen: String, language: String, forceDark: Bool = false) -> CGImage? {
    let name = isDark || forceDark ? "\(screen)-dark" : screen
    return loadImage(root.appending(path: "build/AppStore/raw/\(language)/\(device.rawValue)/\(name).png"))
}

struct Frame {
    let image: CGImage
    /// Bildschirmbereich im Bezel (Ursprung oben links).
    let screen: CGRect
    /// Exakte Form des Displays (weiß = sichtbar), aus der Transparenz des Bezels gelesen. Apple-Displays haben
    /// „kontinuierliche“ Ecken (keine Kreisbögen), der geschlossene Duo links gerade und rechts runde Ecken –
    /// ein Radius passt nie genau, die Maske schon.
    let mask: CGImage?

    static func load(_ device: Device) -> Frame? {
        struct Spec: Decodable { let image: String; let screen: [CGFloat] }
        guard let data = try? Data(contentsOf: root.appending(path: "Marketing/Frames/\(device.rawValue).json")),
              let spec = try? JSONDecoder().decode(Spec.self, from: data), spec.screen.count == 4,
              let image = loadImage(assets.appending(path: spec.image))
        else { return nil }
        let screen = CGRect(x: spec.screen[0], y: spec.screen[1], width: spec.screen[2], height: spec.screen[3])
        return Frame(image: image, screen: screen, mask: screenMask(of: image, screen: screen))
    }

    /// Je Zeile des Bildschirmbereichs von außen nach innen: Der Bildschirm beginnt beim ersten durchsichtigen Pixel
    /// hinter dem (undurchsichtigen) Rand des Bezels – links wie rechts. Dazwischen wird alles gezeichnet; Dynamic Island
    /// bzw. Kameraloch liegen als Teil des Bezels ohnehin obenauf. (Von der Mitte aus zu suchen scheitert genau dort.)
    private static func screenMask(of image: CGImage, screen: CGRect) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let maskWidth = Int(screen.width), maskHeight = Int(screen.height)
        let minX = Int(screen.minX), maxX = Int(screen.maxX) - 1
        var mask = [UInt8](repeating: 0, count: maskWidth * maskHeight)
        func transparent(_ x: Int, _ y: Int) -> Bool {
            x < 0 || x >= width || pixels[(y * width + x) * 4 + 3] < 128
        }
        /// Erstes durchsichtiges Pixel nach einem undurchsichtigen, von `start` in Richtung `step` (höchstens bis `limit`).
        func edge(from start: Int, step: Int, limit: Int, row y: Int) -> Int? {
            var x = start
            var sawBezel = false
            while x != limit + step {
                if transparent(x, y) {
                    if sawBezel { return x }
                } else {
                    sawBezel = true
                }
                x += step
            }
            return nil
        }
        for row in 0..<maskHeight {
            let y = Int(screen.minY) + row
            guard y < height,
                  let left = edge(from: max(minX - 4, 0), step: 1, limit: maxX, row: y),
                  let right = edge(from: min(maxX + 4, width - 1), step: -1, limit: minX, row: y),
                  left <= right
            else { continue }
            for x in max(left, minX)...min(right, maxX) { mask[row * maskWidth + x - minX] = 255 }
        }
        let provider = CGDataProvider(data: Data(mask) as CFData)!
        return CGImage(
            width: maskWidth, height: maskHeight, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: maskWidth,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

let frames = Dictionary(uniqueKeysWithValues: Device.allCases.compactMap { device in Frame.load(device).map { (device, $0) } })
let chalkboard = loadImage(assets.appending(path: "chalkboard.jpg"))
let ciContext = CIContext()
/// Tafel je Zielgröße einmal vorbereitet: weich hochskaliert (Lanczos) und leicht weichgezeichnet –
/// die Vorlage ist klein, sonst würde ihre Körnung bei 5- bis 8-facher Vergrößerung zu sichtbaren Quadraten.
nonisolated(unsafe) var preparedBoards: [String: CGImage] = [:]

func preparedChalkboard(for size: CGSize) -> CGImage? {
    guard let chalkboard else { return nil }
    let key = "\(Int(size.width))x\(Int(size.height))"
    if let cached = preparedBoards[key] { return cached }
    let scale = max(size.width / CGFloat(chalkboard.width), size.height / CGFloat(chalkboard.height))
    let input = CIImage(cgImage: chalkboard)
    let lanczos = CIFilter(name: "CILanczosScaleTransform", parameters: [
        kCIInputImageKey: input, kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1,
    ])!.outputImage!
    let blurred = lanczos.clampedToExtent().applyingGaussianBlur(sigma: scale * 0.55).cropped(to: lanczos.extent)
    let image = ciContext.createCGImage(blurred, from: lanczos.extent)
    preparedBoards[key] = image
    return image
}

/// Kreideschrift aus Marketing/Assets/chalk.ttf, sonst SF Pro Rounded.
let chalkFontName: String? = {
    let url = assets.appending(path: "chalk.ttf")
    guard fileManager.fileExists(atPath: url.path),
          let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
          let descriptor = descriptors.first
    else { return nil }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    return CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(descriptor, 12, nil)) as String
}()

func font(size: CGFloat, bold: Bool) -> NSFont {
    if let chalkFontName, let chalk = NSFont(name: chalkFontName, size: size) { return chalk }
    let base = NSFont.systemFont(ofSize: size, weight: bold ? .heavy : .medium)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

/// Rechteck mit eigenem Radius je Ecke (oben links, oben rechts, unten links, unten rechts; Ursprung oben links).
func roundedPath(_ rect: CGRect, radii: [CGFloat]) -> CGPath {
    let r = radii.map { min($0, rect.width / 2, rect.height / 2) }
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + r[0], y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - r[1], y: rect.minY))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r[1]), radius: r[1])
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r[3]))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r[3], y: rect.maxY), radius: r[3])
    path.addLine(to: CGPoint(x: rect.minX + r[2], y: rect.maxY))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r[2]), radius: r[2])
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r[0]))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r[0], y: rect.minY), radius: r[0])
    path.closeSubpath()
    return path
}

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
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    }

    /// Tafel über ein Panorama aus `count` Bildern; dieses Bild ist Nummer `index` (0 = links).
    func background(index: Int = 0, count: Int = 1) {
        let panorama = CGSize(width: size.width * CGFloat(count), height: size.height)
        let offset = size.width * CGFloat(index)
        guard let chalkboard else {
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [color("#2F4A3A"), color("#1E3127")] as CFArray, locations: [0, 1]
            )!
            context.drawLinearGradient(gradient, start: CGPoint(x: -offset, y: 0), end: CGPoint(x: panorama.width - offset, y: size.height),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            return
        }
        // Füllend skalieren (wie „aspect fill“), mittig; jedes Bild zeigt seinen Ausschnitt.
        let board = preparedChalkboard(for: panorama) ?? chalkboard
        let scale = max(panorama.width / CGFloat(board.width), panorama.height / CGFloat(board.height))
        let drawn = CGSize(width: CGFloat(board.width) * scale, height: CGFloat(board.height) * scale)
        draw(board, in: CGRect(
            x: (panorama.width - drawn.width) / 2 - offset, y: (panorama.height - drawn.height) / 2,
            width: drawn.width, height: drawn.height
        ))
        // Leicht abdunkeln, damit Kreide und Geräte besser stehen.
        context.setFillColor(color("#000000", alpha: 0.18))
        context.fill(CGRect(origin: .zero, size: size))
    }

    /// Bild aufrecht zeichnen (Kontext ist gespiegelt).
    func draw(_ image: CGImage, in rect: CGRect) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// Kreidetext in einem Rechteck, umbrechend; gibt die belegte Höhe zurück.
    /// Wird verkleinert, bis er in die Höhe passt und kein Wort breiter als das Rechteck ist (die Kreideschrift ist breit).
    @discardableResult
    func text(_ string: String, in rect: CGRect, size maxSize: CGFloat, bold: Bool, color hex: String,
              alignment: NSTextAlignment = .left) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineHeightMultiple = 0.95
        func attributed(_ size: CGFloat) -> NSAttributedString {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
            shadow.shadowBlurRadius = size * 0.08
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.03)
            return NSAttributedString(string: string, attributes: [
                .font: font(size: size, bold: bold), .foregroundColor: NSColor(cgColor: color(hex)) ?? .white,
                .paragraphStyle: paragraph, .shadow: shadow,
            ])
        }
        var size = maxSize
        var text = attributed(size)
        let unlimited = CGSize(width: rect.width, height: .greatestFiniteMagnitude)
        while size > maxSize * 0.3 {
            let widestWord = string.split(whereSeparator: \.isWhitespace).map { word in
                NSAttributedString(string: String(word), attributes: [.font: font(size: size, bold: bold)]).size().width
            }.max() ?? 0
            let height = text.boundingRect(with: unlimited, options: [.usesLineFragmentOrigin, .usesFontLeading]).height
            if widestWord <= rect.width && height <= rect.height { break }
            size *= 0.94
            text = attributed(size)
        }
        let attributed = text
        let bounds = attributed.boundingRect(with: unlimited, options: [.usesLineFragmentOrigin, .usesFontLeading])
        attributed.draw(with: CGRect(origin: rect.origin, size: CGSize(width: rect.width, height: ceil(bounds.height))),
                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(bounds.height)
    }

    /// Gerät samt Screenshot; `screenHeight` = Höhe des Bildschirms, oben mittig an `top` / `centerX`,
    /// um `degrees` um die Mitte des Bildschirms gedreht (Bezel und Screenshot gemeinsam).
    func device(_ device: Device, image: CGImage?, label: String, centerX: CGFloat, top: CGFloat, screenHeight: CGFloat,
                degrees: CGFloat = 0) {
        let frame = frames[device]
        let aspect = frame.map { $0.screen.width / $0.screen.height }
            ?? image.map { CGFloat($0.width) / CGFloat($0.height) } ?? device.placeholderAspect
        let screen = CGRect(x: centerX - screenHeight * aspect / 2, y: top, width: screenHeight * aspect, height: screenHeight)

        context.saveGState()
        context.translateBy(x: screen.midX, y: screen.midY)
        context.rotate(by: degrees * .pi / 180)
        context.translateBy(x: -screen.midX, y: -screen.midY)
        if let frame {
            let scale = screen.width / frame.screen.width
            let frameRect = CGRect(
                x: screen.minX - frame.screen.minX * scale, y: screen.minY - frame.screen.minY * scale,
                width: CGFloat(frame.image.width) * scale, height: CGFloat(frame.image.height) * scale
            )
            // Schatten des Bezels (aus dessen Alphakanal) zuerst; der Screenshot deckt den inneren Teil ab,
            // danach der Bezel noch einmal ohne Schatten obenauf (deckt die eckigen Screenshot-Ecken ab).
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: frameRect.height * 0.02), blur: frameRect.height * 0.05,
                              color: color("#000000", alpha: 0.55))
            draw(frame.image, in: frameRect)
            context.restoreGState()
            screenContent(image, label: label, in: screen, radii: [0, 0, 0, 0], mask: frame.mask)
            draw(frame.image, in: frameRect)
        } else {
            let bezel = screen.width * 0.045
            let radius = screen.width * 0.11
            let outer = screen.insetBy(dx: -bezel, dy: -bezel)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: outer.height * 0.02), blur: outer.height * 0.05,
                              color: color("#000000", alpha: 0.55))
            context.addPath(CGPath(roundedRect: outer, cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
            context.setFillColor(color("#1C1C1E"))
            context.fillPath()
            context.restoreGState()
            screenContent(image, label: label, in: screen, radii: [radius, radius, radius, radius])
        }
        context.restoreGState()
    }

    private func screenContent(_ image: CGImage?, label: String, in rect: CGRect, radii: [CGFloat], mask: CGImage? = nil) {
        context.saveGState()
        if let mask {
            // Maske aufrecht anlegen (Kontext ist gespiegelt, wie in `draw`).
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.clip(to: CGRect(origin: .zero, size: rect.size), mask: mask)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -rect.minX, y: -rect.maxY)
        } else {
            context.addPath(roundedPath(rect, radii: radii))
            context.clip()
        }
        if let image {
            draw(image, in: rect)
        } else {
            context.setFillColor(color(isDark ? "#1C1C1E" : "#F2F2F7"))
            context.fill(rect)
            text("Screenshot\n„\(label)“", in: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.4),
                 size: min(rect.width, rect.height) * 0.08, bold: true, color: "#8E8E93", alignment: .center)
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
/// Abwechselnde leichte Drehung der Geräte (Grad), Bild für Bild.
let tilts: [CGFloat] = [-4, 3.5, -3, 4.5, -3.5, 3]

/// build/AppStore/de bzw. build/AppStore/de-dark
func folder(_ language: String) -> String { isDark ? "\(language)-dark" : language }

func screenCaption(_ id: String) -> Captions.Screen? {
    captions.screens.first { $0.id == id }
}

/// Kopfzeile der Produktseite (wie Apples Beispiel): nur Tafel, Name groß in der Mitte, kurzer Untertitel darunter.
/// Großzügiger Rand – der App Store zeigt je nach Gerät nur einen mittigen Ausschnitt.
func header(_ language: String) throws {
    let canvas = Canvas(wide)
    canvas.background()
    let h = wide.height
    let width = wide.width * 0.6
    let x = (wide.width - width) / 2
    let titleHeight = canvas.text(captions.header.title[language] ?? "", in: CGRect(x: x, y: h * 0.36, width: width, height: h * 0.2),
                                  size: h * 0.17, bold: true, color: captions.chalk.title, alignment: .center)
    canvas.text(captions.header.subtitle[language] ?? "",
                in: CGRect(x: x, y: h * 0.36 + titleHeight + h * 0.02, width: width, height: h * 0.1),
                size: h * 0.06, bold: false, color: captions.chalk.subtitle, alignment: .center)
    try canvas.save(output.appending(path: "\(folder(language))/header.png"))
}

/// Suchergebnis-Bilder (wie Apples Beispiel): Titel der Seite links oben, gerahmtes iPhone rechts, unten angeschnitten.
func search(_ language: String) throws {
    let h = wide.height
    for (index, id) in captions.search.screens.prefix(1).enumerated() {
        let canvas = Canvas(wide)
        canvas.background()
        let dark = captions.darkStoreScreens?.contains(id) == true
        canvas.text(screenCaption(id)?.title[language] ?? id,
                    in: CGRect(x: wide.width * 0.08, y: h * 0.12, width: wide.width * 0.42, height: h * 0.45),
                    size: h * 0.12, bold: true, color: captions.chalk.title)
        canvas.device(.iphone, image: screenshot(.iphone, id, language: language, forceDark: dark), label: id,
                      centerX: wide.width * 0.72, top: h * 0.1, screenHeight: h * 1.3, degrees: index.isMultiple(of: 2) ? 4 : -4)
        try canvas.save(output.appending(path: "\(folder(language))/search.png"))
    }
}

/// Store-Bilder einer Geräteklasse im Hochformat als Panorama: Tafel durchgehend, oben Kreidetext (auf allen Geräten
/// derselbe), darunter das leicht gedrehte Gerät, das unten aus dem Bild läuft.
/// Duo: geschlossen und – wenn Screenshots des inneren Displays da sind – jedes zweite Bild aufgeklappt.
func storeImages(_ device: Device, _ language: String) throws {
    let screens = captions.storeScreens
    let size: CGSize = switch device {
    case .ipad: CGSize(width: 2064, height: 2752)
    case .duo, .duoOpen: CGSize(width: 1398, height: 2034)
    case .iphone: CGSize(width: 1206, height: 2622)
    }
    for (index, id) in screens.enumerated() {
        let canvas = Canvas(size)
        canvas.background(index: index, count: screens.count)
        let caption = screenCaption(id)
        let tilt = tilts[index % tilts.count]
        let dark = captions.darkStoreScreens?.contains(id) == true

        // Text: oben, mittig, höchstens zwei Zeilen Titel; Untertitel 0,6 × Titelgröße.
        // iPad: Titel halb so groß wie zuvor (das breitere Bild wirkte sonst überladen).
        let titleSize = size.width * (device == .ipad ? 0.0525 : 0.092)
        let margin = size.width * 0.08
        var y = size.height * 0.045
        y += canvas.text(caption?.title[language] ?? id,
                         in: CGRect(x: margin, y: y, width: size.width - 2 * margin, height: size.height * 0.12),
                         size: titleSize, bold: true, color: captions.chalk.title, alignment: .center)
        y += size.height * 0.008
        y += canvas.text(caption?.subtitle[language] ?? "",
                         in: CGRect(x: margin, y: y, width: size.width - 2 * margin, height: size.height * 0.07),
                         size: titleSize * 0.6, bold: false, color: captions.chalk.subtitle, alignment: .center)

        // Gerät: ab etwa einem Fünftel der Höhe, Breite ~80 % (iPad ~82 %), unten angeschnitten.
        let top = max(y + size.height * 0.035, size.height * 0.2)
        let openImage = device == .duo && index % 2 == 1 ? screenshot(.duoOpen, id, language: language) : nil
        if let openImage {
            let screenWidth = size.width * 0.86
            canvas.device(.duoOpen, image: openImage, label: id, centerX: size.width / 2, top: top + size.height * 0.08,
                          screenHeight: screenWidth / Device.duoOpen.placeholderAspect, degrees: tilt * 0.6)
        } else {
            let aspect = frames[device].map { $0.screen.width / $0.screen.height } ?? device.placeholderAspect
            // Der geschlossene Duo ist gedrungener (fast quadratisch) und darf breiter sein, damit er die Fläche füllt.
            let screenWidth = size.width * (device == .ipad ? 0.82 : device == .duo ? 0.82 : 0.78)
            canvas.device(device, image: screenshot(device, id, language: language, forceDark: dark), label: id,
                          centerX: size.width / 2, top: top, screenHeight: screenWidth / aspect, degrees: tilt * (device == .ipad ? 0.6 : 0.8))
        }
        let name = String(format: "%02d-%@.png", index + 1, id)
        try canvas.save(output.appending(path: "\(folder(language))/\(device.rawValue)/\(name)"))
    }
}

print("▸ Bezels: " + (frames.isEmpty ? "keine (gezeichnete Rahmen)" : frames.keys.map(\.rawValue).sorted().joined(separator: ", ")))
print("▸ Tafel: " + (chalkboard.map { "\($0.width) × \($0.height)" } ?? "fehlt (Verlauf)") + " · Schrift: " + (chalkFontName ?? "Systemschrift"))
for appearance in appearances {
    isDark = appearance == "dark"
    for language in languages {
        print("▸ \(folder(language))")
        // Alte Ausgaben entfernen (z. B. nach weniger Store-Seiten).
        try? fileManager.removeItem(at: output.appending(path: folder(language)))
        try header(language)
        try search(language)
        for device in [Device.iphone, .duo, .ipad] {
            try storeImages(device, language)
        }
    }
}
print("✓ build/AppStore/")
