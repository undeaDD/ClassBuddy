import Foundation
import Testing
@testable import ClassBuddy

@Suite("ZIP & XLSX")
struct SpreadsheetTests {
    /// Erwartete Texte sind deutsch – unabhängig von der Sprache des Simulators.
    init() {
        AppLanguage.current = .german
    }

    @Test("ZIP: geschriebene Einträge lassen sich wieder lesen")
    func zipRoundTrip() throws {
        let entries: [(path: String, data: Data)] = [
            ("a.txt", Data("Hallo".utf8)),
            ("ordner/ü.xml", Data("<x>Größe</x>".utf8)),
            ("leer.bin", Data()),
        ]
        let files = try ZipArchive.read(ZipArchive.write(entries))

        #expect(files.count == 3)
        #expect(files["a.txt"] == Data("Hallo".utf8))
        #expect(files["ordner/ü.xml"] == Data("<x>Größe</x>".utf8))
        #expect(files["leer.bin"] == Data())
    }

    @Test("ZIP: ungültige Daten werden abgelehnt")
    func zipRejectsGarbage() {
        #expect(throws: ZipArchive.ZipError.self) {
            try ZipArchive.read(Data("kein zip".utf8))
        }
    }

    @Test("XLSX: Blätter und Zellen überstehen Schreiben + Lesen")
    func xlsxRoundTrip() throws {
        let sheets = [
            XLSXSheet(name: "Klassen", rows: [["ID", "Kürzel", "Fächer"], ["1", "7b", "Mathe; Physik"]]),
            XLSXSheet(name: "Sonderzeichen", rows: [["Text"], ["<&> \"x\" 'y'"], ["Émma Ölaf"]]),
        ]
        let book = try XLSX.read(XLSX.write(sheets))

        #expect(book["Klassen"] == sheets[0].rows)
        #expect(book["Sonderzeichen"] == sheets[1].rows)
    }

    @Test("XLSX: leere Zellen bleiben an ihrer Position")
    func xlsxKeepsGaps() throws {
        let rows = [["A", "B", "C"], ["1", "", "3"]]
        let book = try XLSX.read(XLSX.write([XLSXSheet(name: "Lücken", rows: rows)]))

        #expect(book["Lücken"] == rows)
    }

    @Test("XLSX wie aus Excel/Numbers: Shared Strings, Rich Text, Zellen ohne Position, absoluter Pfad")
    func readsSharedStrings() throws {
        let xml = { (body: String) in Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + body).utf8) }
        let archive = ZipArchive.write([
            ("xl/workbook.xml", xml(#"""
                <workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                <sheets><sheet name="Klassen" sheetId="1" r:id="rId1"/></sheets></workbook>
                """#)),
            ("xl/_rels/workbook.xml.rels", xml(#"""
                <Relationships><Relationship Id="rId1" Target="/xl/worksheets/sheet1.xml"/></Relationships>
                """#)),
            ("xl/sharedStrings.xml", xml(#"""
                <sst><si><t>Kürzel</t></si><si><r><t>7</t></r><r><t>b</t></r></si></sst>
                """#)),
            ("xl/worksheets/sheet1.xml", xml(#"""
                <worksheet><sheetData>
                <row><c t="s"><v>0</v></c><c t="b"><v>1</v></c></row>
                <row r="3"><c r="B3" t="s"><v>1</v></c><c r="C3"><v>42</v></c></row>
                </sheetData></worksheet>
                """#)),
        ])

        let book = try XLSX.read(archive)
        #expect(book["Klassen"] == [["Kürzel", "ja", ""], ["", "", ""], ["", "7b", "42"]])
    }

    @Test("Spaltennamen", arguments: [(0, "A"), (25, "Z"), (26, "AA"), (701, "ZZ"), (702, "AAA")])
    func columnNames(index: Int, expected: String) {
        #expect(XLSX.columnName(index) == expected)
    }
}
