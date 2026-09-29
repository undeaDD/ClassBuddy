import Foundation

/// Eine Tabelle: erste Zeile = Spaltenüberschriften.
nonisolated struct XLSXSheet {
    var name: String
    var rows: [[String]]
}

/// Minimales .xlsx (Office Open XML) – Schreiben und Lesen ohne Fremdbibliothek.
/// Schreibt alle Zellen als Text (Inline-Strings), Kopfzeile fett und fixiert.
/// Liest Text-, Shared-String-, Zahlen- und Wahrheitswert-Zellen als String.
nonisolated enum XLSX {
    enum XLSXError: LocalizedError {
        case missingWorkbook

        var errorDescription: String? { "Die Datei enthält keine lesbare Arbeitsmappe." }
    }

    // MARK: Schreiben

    static func write(_ sheets: [XLSXSheet]) -> Data {
        var entries: [(path: String, data: Data)] = []

        let overrides = sheets.indices.map {
            #"<Override PartName="/xl/worksheets/sheet\#($0 + 1).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }.joined()
        entries.append(("[Content_Types].xml", xml("""
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/>\
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
            \(overrides)</Types>
            """)))

        entries.append(("_rels/.rels", xml("""
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
            </Relationships>
            """)))

        let sheetTags = sheets.enumerated().map { index, sheet in
            #"<sheet name="\#(escape(sanitizedName(sheet.name)))" sheetId="\#(index + 1)" r:id="rId\#(index + 1)"/>"#
        }.joined()
        entries.append(("xl/workbook.xml", xml("""
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
            <sheets>\(sheetTags)</sheets></workbook>
            """)))

        let sheetRels = sheets.indices.map {
            #"<Relationship Id="rId\#($0 + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#($0 + 1).xml"/>"#
        }.joined()
        entries.append(("xl/_rels/workbook.xml.rels", xml("""
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(sheetRels)\
            <Relationship Id="rId\(sheets.count + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
            </Relationships>
            """)))

        entries.append(("xl/styles.xml", xml("""
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
            <fonts count="2"><font><sz val="12"/><name val="Calibri"/></font><font><b/><sz val="12"/><name val="Calibri"/></font></fonts>\
            <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
            <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
            <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
            <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>\
            <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
            </styleSheet>
            """)))

        for (index, sheet) in sheets.enumerated() {
            entries.append(("xl/worksheets/sheet\(index + 1).xml", worksheet(sheet)))
        }
        return ZipArchive.write(entries)
    }

    private static func worksheet(_ sheet: XLSXSheet) -> Data {
        let columnCount = sheet.rows.map(\.count).max() ?? 0
        let cols = columnCount > 0 ? "<cols><col min=\"1\" max=\"\(columnCount)\" width=\"22\" customWidth=\"1\"/></cols>" : ""
        var body = ""
        for (rowIndex, row) in sheet.rows.enumerated() {
            let style = rowIndex == 0 ? " s=\"1\"" : ""
            body += "<row r=\"\(rowIndex + 1)\">"
            for (columnIndex, value) in row.enumerated() where !value.isEmpty {
                let ref = columnName(columnIndex) + String(rowIndex + 1)
                body += "<c r=\"\(ref)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
            }
            body += "</row>"
        }
        let frozenHeader = """
            <sheetViews><sheetView workbookViewId="0">\
            <pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>\
            </sheetView></sheetViews>
            """
        return xml("""
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
            \(frozenHeader)\(cols)<sheetData>\(body)</sheetData></worksheet>
            """)
    }

    private static func xml(_ content: String) -> Data {
        Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + content).utf8)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Excel erlaubt max. 31 Zeichen und keine []:*?/\ im Blattnamen.
    private static func sanitizedName(_ name: String) -> String {
        String(name.filter { !"[]:*?/\\".contains($0) }.prefix(31))
    }

    /// 0 → A, 25 → Z, 26 → AA …
    static func columnName(_ index: Int) -> String {
        var index = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + index % 26))) + name
            index = index / 26 - 1
        } while index >= 0
        return name
    }

    // MARK: Lesen

    /// Blattname → Zeilen (erste Zeile = Überschriften, fehlende Zellen = "").
    static func read(_ data: Data) throws -> [String: [[String]]] {
        let files = try ZipArchive.read(data)
        guard let workbook = files["xl/workbook.xml"] else { throw XLSXError.missingWorkbook }

        let sheetList = WorkbookParser.parse(workbook)
        let relationships = files["xl/_rels/workbook.xml.rels"].map(RelationshipsParser.parse) ?? [:]
        let sharedStrings = files["xl/sharedStrings.xml"].map(SharedStringsParser.parse) ?? []

        var result: [String: [[String]]] = [:]
        for (name, relationshipID) in sheetList {
            guard let target = relationships[relationshipID] else { continue }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard let sheetData = files[path] else { continue }
            result[name] = WorksheetParser.parse(sheetData, sharedStrings: sharedStrings)
        }
        return result
    }

    /// „BC12“ → Spaltenindex 54.
    fileprivate static func columnIndex(fromReference reference: String) -> Int {
        var index = 0
        for scalar in reference.unicodeScalars {
            guard (65...90).contains(scalar.value) else { break }
            index = index * 26 + Int(scalar.value - 64)
        }
        return index - 1
    }
}

// MARK: - XML-Parser

private nonisolated final class WorkbookParser: NSObject, XMLParserDelegate {
    private var sheets: [(String, String)] = []

    static func parse(_ data: Data) -> [(name: String, relationshipID: String)] {
        let delegate = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.sheets.map { (name: $0.0, relationshipID: $0.1) }
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        guard element == "sheet" || element.hasSuffix(":sheet"),
              let name = attributes["name"],
              let id = attributes.first(where: { $0.key == "r:id" || $0.key.hasSuffix(":id") })?.value
        else { return }
        sheets.append((name, id))
    }
}

private nonisolated final class RelationshipsParser: NSObject, XMLParserDelegate {
    private var targets: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let delegate = RelationshipsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.targets
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        guard element == "Relationship", let id = attributes["Id"], let target = attributes["Target"] else { return }
        targets[id] = target
    }
}

private nonisolated final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var isInItem = false
    private var isInText = false

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "si": isInItem = true; current = ""
        case "t": isInText = isInItem
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "t": isInText = false
        case "si": strings.append(current); isInItem = false
        default: break
        }
    }
}

private nonisolated final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [Int: [Int: String]] = [:]
    private var currentRow = -1
    private var currentColumn = -1
    private var currentType = ""
    private var buffer = ""
    private var isCollecting = false

    private init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
        let delegate = WorksheetParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        guard let lastRow = delegate.rows.keys.max() else { return [] }
        let width = (delegate.rows.values.flatMap(\.keys).max() ?? -1) + 1
        return (0...lastRow).map { row in
            (0..<width).map { delegate.rows[row]?[$0] ?? "" }
        }
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "row":
            if let r = attributes["r"], let number = Int(r) { currentRow = number - 1 } else { currentRow += 1 }
            currentColumn = -1
        case "c":
            currentColumn = attributes["r"].map(XLSX.columnIndex(fromReference:)) ?? currentColumn + 1
            currentType = attributes["t"] ?? "n"
            buffer = ""
        case "v", "t":
            isCollecting = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCollecting { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "v", "t":
            isCollecting = false
        case "c":
            let value: String = switch currentType {
            case "s": Int(buffer).flatMap { sharedStrings.indices.contains($0) ? sharedStrings[$0] : nil } ?? ""
            case "b": buffer == "1" ? "ja" : "nein"
            default: buffer
            }
            if !value.isEmpty, currentColumn >= 0 {
                rows[currentRow, default: [:]][currentColumn] = value
            }
        default:
            break
        }
    }
}
