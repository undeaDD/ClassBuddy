import Compression
import Foundation

/// Minimaler ZIP-Container für .xlsx – ohne Fremdbibliothek.
/// - Schreiben: unkomprimiert („stored“), von Excel/Numbers problemlos lesbar.
/// - Lesen: „stored“ und „deflate“ (über Apples Compression-Framework).
/// Kein ZIP64, keine Verschlüsselung – für Tabellen-Exporte völlig ausreichend.
nonisolated enum ZipArchive {
    enum ZipError: LocalizedError {
        case notAZip
        case unsupportedMethod(UInt16)
        case corrupt

        var errorDescription: String? {
            switch self {
            case .notAZip: "Die Datei ist keine gültige Excel-Datei (.xlsx)."
            case .unsupportedMethod(let method): "Nicht unterstützte ZIP-Kompression (\(method))."
            case .corrupt: "Die Datei ist beschädigt."
            }
        }
    }

    // MARK: Schreiben

    static func write(_ entries: [(path: String, data: Data)]) -> Data {
        var archive = Data()
        var central = Data()

        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(archive.count)

            // Local File Header
            archive.append(le32: 0x0403_4B50)
            archive.append(le16: 20)          // benötigte Version
            archive.append(le16: 0x0800)      // UTF-8-Dateinamen
            archive.append(le16: 0)           // stored
            archive.append(le16: 0)           // Zeit
            archive.append(le16: 0x21)        // Datum 1980-01-01
            archive.append(le32: crc)
            archive.append(le32: size)
            archive.append(le32: size)
            archive.append(le16: UInt16(name.count))
            archive.append(le16: 0)
            archive.append(name)
            archive.append(entry.data)

            // Central Directory Eintrag
            central.append(le32: 0x0201_4B50)
            central.append(le16: 20)
            central.append(le16: 20)
            central.append(le16: 0x0800)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0x21)
            central.append(le32: crc)
            central.append(le32: size)
            central.append(le32: size)
            central.append(le16: UInt16(name.count))
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le16: 0)
            central.append(le32: 0)
            central.append(le32: offset)
            central.append(name)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(central)

        // End of Central Directory
        archive.append(le32: 0x0605_4B50)
        archive.append(le16: 0)
        archive.append(le16: 0)
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: UInt32(central.count))
        archive.append(le32: centralOffset)
        archive.append(le16: 0)
        return archive
    }

    // MARK: Lesen

    /// Alle Dateien des Archivs (Pfad → Inhalt).
    static func read(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        let eocd = try endOfCentralDirectory(in: bytes)
        let count = Int(bytes.le16(at: eocd + 10))
        var offset = Int(bytes.le32(at: eocd + 16))
        var files: [String: Data] = [:]

        for _ in 0..<count {
            let entry = try readEntry(in: bytes, at: offset)
            files[entry.name] = entry.data
            offset = entry.nextOffset
        }
        return files
    }

    /// End of Central Directory von hinten suchen (max. 64 KB Kommentar).
    private static func endOfCentralDirectory(in bytes: [UInt8]) throws -> Int {
        guard bytes.count >= 22 else { throw ZipError.notAZip }
        let lowerBound = max(0, bytes.count - 22 - 65_535)
        for index in stride(from: bytes.count - 22, through: lowerBound, by: -1) where bytes.le32(at: index) == 0x0605_4B50 {
            return index
        }
        throw ZipError.notAZip
    }

    /// Einen Eintrag des Central Directory samt Dateiinhalt lesen.
    private struct Entry {
        let name: String
        let data: Data
        /// Beginn des nächsten Central-Directory-Eintrags.
        let nextOffset: Int
    }

    private static func readEntry(in bytes: [UInt8], at offset: Int) throws -> Entry {
        guard offset + 46 <= bytes.count, bytes.le32(at: offset) == 0x0201_4B50 else { throw ZipError.corrupt }
        let method = bytes.le16(at: offset + 10)
        let compressedSize = Int(bytes.le32(at: offset + 20))
        let size = Int(bytes.le32(at: offset + 24))
        let nameLength = Int(bytes.le16(at: offset + 28))
        let extraLength = Int(bytes.le16(at: offset + 30))
        let commentLength = Int(bytes.le16(at: offset + 32))
        let localOffset = Int(bytes.le32(at: offset + 42))
        guard offset + 46 + nameLength <= bytes.count else { throw ZipError.corrupt }
        let name = String(bytes: bytes[(offset + 46)..<(offset + 46 + nameLength)], encoding: .utf8) ?? ""

        guard localOffset + 30 <= bytes.count, bytes.le32(at: localOffset) == 0x0403_4B50 else { throw ZipError.corrupt }
        let dataStart = localOffset + 30 + Int(bytes.le16(at: localOffset + 26)) + Int(bytes.le16(at: localOffset + 28))
        guard dataStart + compressedSize <= bytes.count else { throw ZipError.corrupt }
        let payload = Array(bytes[dataStart..<(dataStart + compressedSize)])

        let data: Data
        switch method {
        case 0: data = Data(payload)
        case 8: data = try inflate(payload, size: size)
        default: throw ZipError.unsupportedMethod(method)
        }
        return Entry(name: name, data: data, nextOffset: offset + 46 + nameLength + extraLength + commentLength)
    }

    /// Raw DEFLATE (RFC 1951) entpacken – `COMPRESSION_ZLIB` ist genau das.
    private static func inflate(_ input: [UInt8], size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: size)
        let written = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(
                    destination.baseAddress!, size,
                    source.baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw ZipError.corrupt }
        return Data(output)
    }

    // MARK: CRC-32

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc & 1) != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
        return crc
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private nonisolated extension Data {
    mutating func append(le16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(le32 value: UInt32) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }
}

private nonisolated extension Array where Element == UInt8 {
    func le16(at index: Int) -> UInt16 {
        UInt16(self[index]) | UInt16(self[index + 1]) << 8
    }

    func le32(at index: Int) -> UInt32 {
        UInt32(self[index]) | UInt32(self[index + 1]) << 8 | UInt32(self[index + 2]) << 16 | UInt32(self[index + 3]) << 24
    }
}
