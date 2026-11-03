import Foundation

/// Minimales Compound File (MS-CFB, „OLE-Datei“) für verschlüsselte Office-Dateien: Schreiben (Version 3,
/// 512-Byte-Sektoren, kleine Ströme im Mini-Stream, DIFAT für große Dateien) und Lesen der Ströme im Wurzelordner.
nonisolated struct CompoundFile {
    struct Entry {
        /// Ordner und zuletzt der Name des Stroms, z. B. ["\u{06}DataSpaces", "Version"].
        var path: [String]
        var data: Data
    }

    enum CompoundFileError: Error {
        case invalid
    }

    private static let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
    private static let sectorSize = 512
    private static let miniSectorSize = 64
    private static let miniCutoff = 4096
    private static let free: UInt32 = 0xFFFF_FFFF
    fileprivate static let endOfChain: UInt32 = 0xFFFF_FFFE
    private static let fatSector: UInt32 = 0xFFFF_FFFD
    fileprivate static let difatSector: UInt32 = 0xFFFF_FFFC
    fileprivate static let noStream: UInt32 = 0xFFFF_FFFF

    static func isCompoundFile(_ data: Data) -> Bool {
        data.count >= 512 && Array(data.prefix(8)) == signature
    }

    // MARK: Schreiben

    private final class Node {
        let name: String
        let isStorage: Bool
        var data = Data()
        var children: [Node] = []
        var index = 0
        var left = noStream, right = noStream, child = noStream
        var startSector = endOfChain

        init(name: String, isStorage: Bool) {
            self.name = name
            self.isStorage = isStorage
        }
    }

    /// Sektoren hinter Kopf, FAT und DIFAT, in dieser Reihenfolge.
    private struct Layout {
        var fatCount = 1
        var difatCount = 0
        var directorySectors = 0
        var miniFatSectors = 0
        var miniStreamSectors = 0
    }

    static func write(_ entries: [Entry]) -> Data {
        let (root, nodes) = makeTree(entries)
        let (miniStream, miniFat) = packMiniStream(nodes.filter { !$0.isStorage })
        let bigStreams = nodes.filter { !$0.isStorage && $0.data.count >= miniCutoff }

        var layout = Layout(
            directorySectors: sectors(nodes.count * 128), miniFatSectors: sectors(miniFat.count * 4),
            miniStreamSectors: sectors(miniStream.count)
        )
        let otherSectors = layout.directorySectors + layout.miniFatSectors + layout.miniStreamSectors
            + bigStreams.reduce(0) { $0 + sectors($1.data.count) }
        (layout.fatCount, layout.difatCount) = fatCounts(otherSectors: otherSectors)

        // FAT: eigene Sektoren markieren, dann die Ketten hintereinander.
        var fat = [UInt32](repeating: free, count: layout.fatCount * 128)
        for index in 0..<layout.fatCount { fat[index] = fatSector }
        for index in layout.fatCount..<(layout.fatCount + layout.difatCount) { fat[index] = difatSector }
        var next = layout.fatCount + layout.difatCount
        func chain(_ count: Int) -> UInt32 {
            guard count > 0 else { return endOfChain }
            let first = next
            for offset in 0..<count {
                fat[first + offset] = offset == count - 1 ? endOfChain : UInt32(first + offset + 1)
            }
            next += count
            return UInt32(first)
        }
        let directoryStart = chain(layout.directorySectors)
        let miniFatStart = chain(layout.miniFatSectors)
        root.startSector = chain(layout.miniStreamSectors)
        for node in bigStreams { node.startSector = chain(sectors(node.data.count)) }

        var output = header(layout: layout, directoryStart: directoryStart, miniFatStart: miniFatStart)
        for value in fat { output += littleEndian(value) }
        output += difat(layout: layout)
        output += directory(nodes, root: root, miniStreamSize: miniStream.count, sectorCount: layout.directorySectors)
        var miniFatData = Data()
        for value in miniFat { miniFatData += littleEndian(value) }
        output += padded(miniFatData, filler: littleEndian(free))
        output += padded(miniStream)
        for node in bigStreams { output += padded(node.data) }
        return output
    }

    private static func sectors(_ bytes: Int) -> Int {
        (bytes + sectorSize - 1) / sectorSize
    }

    private static func padded(_ data: Data, filler: Data = Data([0])) -> Data {
        var result = data
        while result.count % sectorSize != 0 { result += filler }
        return result
    }

    /// Ordner aus den Pfaden; Geschwister als ausgeglichener Suchbaum (alle schwarz), sortiert nach Länge, dann
    /// Großschreibung. Reihenfolge im Verzeichnis: Wurzel, dann in die Tiefe.
    private static func makeTree(_ entries: [Entry]) -> (Node, [Node]) {
        let root = Node(name: "Root Entry", isStorage: true)
        for entry in entries {
            var parent = root
            for folder in entry.path.dropLast() {
                if let existing = parent.children.first(where: { $0.isStorage && $0.name == folder }) {
                    parent = existing
                } else {
                    let storage = Node(name: folder, isStorage: true)
                    parent.children.append(storage)
                    parent = storage
                }
            }
            let stream = Node(name: entry.path.last ?? "", isStorage: false)
            stream.data = entry.data
            parent.children.append(stream)
        }

        var nodes: [Node] = []
        func collect(_ node: Node) {
            node.index = nodes.count
            nodes.append(node)
            node.children.forEach(collect)
        }
        collect(root)
        func tree(_ sorted: ArraySlice<Node>) -> UInt32 {
            guard !sorted.isEmpty else { return noStream }
            let middle = sorted.startIndex + sorted.count / 2
            sorted[middle].left = tree(sorted[sorted.startIndex..<middle])
            sorted[middle].right = tree(sorted[(middle + 1)..<sorted.endIndex])
            return UInt32(sorted[middle].index)
        }
        for node in nodes where node.isStorage {
            let sorted = node.children.sorted { lhs, rhs in
                let left = Array(lhs.name.uppercased().utf16), right = Array(rhs.name.uppercased().utf16)
                return left.count != right.count ? left.count < right.count : left.lexicographicallyPrecedes(right)
            }
            node.child = tree(sorted[...])
        }
        return (root, nodes)
    }

    /// Ströme unter 4096 Bytes in 64-Byte-Mini-Sektoren.
    private static func packMiniStream(_ streams: [Node]) -> (Data, [UInt32]) {
        var miniStream = Data()
        var miniFat: [UInt32] = []
        for node in streams where node.data.count < miniCutoff && !node.data.isEmpty {
            let first = UInt32(miniFat.count)
            let count = (node.data.count + miniSectorSize - 1) / miniSectorSize
            for offset in 0..<count {
                miniFat.append(offset == count - 1 ? endOfChain : first + UInt32(offset) + 1)
            }
            node.startSector = first
            miniStream += node.data + Data(count: count * miniSectorSize - node.data.count)
        }
        return (miniStream, miniFat)
    }

    /// FAT-Sektoren (je 128 Einträge) und DIFAT-Sektoren (ab dem 110. FAT-Sektor, je 127) für alle Sektoren.
    private static func fatCounts(otherSectors: Int) -> (Int, Int) {
        var fatCount = 1, difatCount = 0
        while true {
            let neededFat = (otherSectors + fatCount + difatCount + 127) / 128
            let neededDifat = neededFat > 109 ? (neededFat - 109 + 126) / 127 : 0
            if neededFat == fatCount, neededDifat == difatCount { return (fatCount, difatCount) }
            fatCount = neededFat
            difatCount = neededDifat
        }
    }

    private static func header(layout: Layout, directoryStart: UInt32, miniFatStart: UInt32) -> Data {
        var output = Data(signature) + Data(count: 16)
        output += littleEndian(UInt16(0x3E)) + littleEndian(UInt16(3)) + littleEndian(UInt16(0xFFFE))
        output += littleEndian(UInt16(9)) + littleEndian(UInt16(6)) + Data(count: 6)
        output += littleEndian(UInt32(0)) + littleEndian(UInt32(layout.fatCount)) + littleEndian(directoryStart)
        output += littleEndian(UInt32(0)) + littleEndian(UInt32(miniCutoff))
        output += littleEndian(layout.miniFatSectors > 0 ? miniFatStart : endOfChain)
        output += littleEndian(UInt32(layout.miniFatSectors))
        output += littleEndian(layout.difatCount > 0 ? UInt32(layout.fatCount) : endOfChain)
        output += littleEndian(UInt32(layout.difatCount))
        for index in 0..<109 { output += littleEndian(index < layout.fatCount ? UInt32(index) : free) }
        return output
    }

    private static func difat(layout: Layout) -> Data {
        var output = Data()
        for sector in 0..<layout.difatCount {
            for slot in 0..<127 {
                let fatIndex = 109 + sector * 127 + slot
                output += littleEndian(fatIndex < layout.fatCount ? UInt32(fatIndex) : free)
            }
            output += littleEndian(sector == layout.difatCount - 1 ? endOfChain : UInt32(layout.fatCount + sector + 1))
        }
        return output
    }

    private static func directory(_ nodes: [Node], root: Node, miniStreamSize: Int, sectorCount: Int) -> Data {
        var directory = Data()
        for node in nodes {
            var name = Data()
            for unit in node.name.utf16.prefix(31) { name += littleEndian(unit) }
            directory += name + Data(count: 64 - name.count) + littleEndian(UInt16(name.count + 2))
            directory.append(node === root ? 5 : (node.isStorage ? 1 : 2))
            directory.append(1)
            directory += littleEndian(node.left) + littleEndian(node.right) + littleEndian(node.child)
            directory += Data(count: 16 + 4 + 16)
            let size = node === root ? miniStreamSize : (node.isStorage ? 0 : node.data.count)
            let start = node.isStorage && node !== root ? 0 : (size == 0 ? endOfChain : node.startSector)
            directory += littleEndian(start) + littleEndian(UInt64(size))
        }
        while directory.count < sectorCount * sectorSize {
            directory += Data(count: 64) + littleEndian(UInt16(0)) + Data([0, 0])
            directory += littleEndian(noStream) + littleEndian(noStream) + littleEndian(noStream)
            directory += Data(count: 16 + 4 + 16 + 4 + 8)
        }
        return directory
    }

    // MARK: Lesen

    private let reader: Reader
    private let miniFat: [UInt32]
    private let miniStream: [UInt8]
    private let rootStreams: [String: (start: UInt32, size: Int)]
    private let cutoff: Int

    init(_ data: Data) throws {
        guard Self.isCompoundFile(data) else { throw CompoundFileError.invalid }
        let reader = try Reader([UInt8](data))
        self.reader = reader
        cutoff = Int(reader.uint32(56))
        let miniFatBytes = reader.read(reader.uint32(60))
        miniFat = stride(from: 0, to: miniFatBytes.count - 3, by: 4).map { Reader.uint32(miniFatBytes, $0) }

        let directory = reader.read(reader.uint32(48))
        guard let root = DirectoryEntry(directory, index: 0), root.type == 5 else { throw CompoundFileError.invalid }
        miniStream = Array(reader.read(root.start).prefix(root.size))

        var streams: [String: (UInt32, Int)] = [:]
        var pending = [root.child]
        var visited = Set<UInt32>()
        while let index = pending.popLast() {
            guard let item = DirectoryEntry(directory, index: index), visited.insert(index).inserted else { continue }
            if item.type == 2 { streams[item.name] = (item.start, item.size) }
            pending += [item.left, item.right]
        }
        rootStreams = streams
    }

    /// Strom im Wurzelordner.
    func stream(named name: String) -> Data? {
        guard let (start, size) = rootStreams[name] else { return nil }
        let bytes: [UInt8]
        if size < cutoff {
            bytes = Reader.chain(start, in: miniFat).flatMap { sector -> ArraySlice<UInt8> in
                let offset = Int(sector) * Self.miniSectorSize
                guard offset + Self.miniSectorSize <= miniStream.count else { return [] }
                return miniStream[offset..<(offset + Self.miniSectorSize)]
            }
        } else {
            bytes = reader.read(start)
        }
        return bytes.count >= size ? Data(bytes.prefix(size)) : nil
    }
}

nonisolated extension CompoundFile {
    /// Sektoren und FAT einer Datei.
    fileprivate struct Reader {
        let bytes: [UInt8]
        let sectorLength: Int
        private(set) var fat: [UInt32] = []

        init(_ bytes: [UInt8]) throws {
            self.bytes = bytes
            let shift = Int(bytes[30]) | Int(bytes[31]) << 8
            guard shift == 9 || shift == 12 else { throw CompoundFileError.invalid }
            sectorLength = 1 << shift

            // FAT-Sektoren aus dem Kopf und der DIFAT-Kette.
            var fatSectors = (0..<109).map { uint32(76 + $0 * 4) }.filter { $0 < CompoundFile.difatSector }
            var difat = uint32(68)
            var visited = 0
            while difat < CompoundFile.difatSector, visited < 100_000 {
                let position = offset(of: difat)
                let perSector = sectorLength / 4 - 1
                fatSectors += (0..<perSector).map { uint32(position + $0 * 4) }.filter { $0 < CompoundFile.difatSector }
                difat = uint32(position + perSector * 4)
                visited += 1
            }
            fat = fatSectors.flatMap { sector in
                let position = offset(of: sector)
                return (0..<(sectorLength / 4)).map { uint32(position + $0 * 4) }
            }
        }

        static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
            guard offset >= 0, offset + 4 <= bytes.count else { return CompoundFile.endOfChain }
            return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }

        func uint32(_ offset: Int) -> UInt32 {
            Self.uint32(bytes, offset)
        }

        func offset(of sector: UInt32) -> Int {
            (Int(sector) + 1) * sectorLength
        }

        static func chain(_ start: UInt32, in table: [UInt32]) -> [UInt32] {
            var result: [UInt32] = []
            var current = start
            while current < CompoundFile.difatSector, Int(current) < table.count, result.count <= table.count {
                result.append(current)
                current = table[Int(current)]
            }
            return result
        }

        func read(_ start: UInt32) -> [UInt8] {
            Self.chain(start, in: fat).flatMap { sector -> ArraySlice<UInt8> in
                let position = offset(of: sector)
                guard position + sectorLength <= bytes.count else { return [] }
                return bytes[position..<(position + sectorLength)]
            }
        }
    }

    /// Ein Eintrag (128 Bytes) im Verzeichnis.
    fileprivate struct DirectoryEntry {
        var name: String
        var type: UInt8
        var left: UInt32, right: UInt32, child: UInt32
        var start: UInt32
        var size: Int

        init?(_ directory: [UInt8], index: UInt32) {
            let offset = Int(index) * 128
            guard index != CompoundFile.noStream, offset + 128 <= directory.count else { return nil }
            let nameLength = max(0, min(64, Int(directory[offset + 64]) | Int(directory[offset + 65]) << 8) - 2)
            let units = stride(from: 0, to: nameLength, by: 2).map {
                UInt16(directory[offset + $0]) | UInt16(directory[offset + $0 + 1]) << 8
            }
            name = String(decoding: units, as: UTF16.self)
            type = directory[offset + 66]
            left = Reader.uint32(directory, offset + 68)
            right = Reader.uint32(directory, offset + 72)
            child = Reader.uint32(directory, offset + 76)
            start = Reader.uint32(directory, offset + 116)
            size = Int(Reader.uint32(directory, offset + 120))
        }
    }
}
