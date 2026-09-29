import Foundation
import Testing
@testable import ClassBuddy

@Suite("ZIP & XLSX")
struct SpreadsheetTests {
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

    @Test("Spaltennamen", arguments: [(0, "A"), (25, "Z"), (26, "AA"), (701, "ZZ"), (702, "AAA")])
    func columnNames(index: Int, expected: String) {
        #expect(XLSX.columnName(index) == expected)
    }
}
