import Foundation

// Tabellen-Hilfen für den Excel-Export/-Import: Zugriff per Spaltenname und
// tolerantes Formatieren/Parsen von Zellwerten.
extension Backup {
    /// Tabelle mit Kopfzeile: Zugriff auf Zellen per Spaltenname.
    struct Table {
        struct Row {
            let values: [String: String]
            subscript(column: String) -> String {
                values[column]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }
        }

        let rows: [Row]

        init(_ raw: [[String]]) {
            guard let header = raw.first else { rows = []; return }
            let names = header.map { $0.trimmingCharacters(in: .whitespaces) }
            rows = raw.dropFirst()
                .filter { $0.contains { !$0.isEmpty } }
                .map { cells in
                    Row(values: Dictionary(
                        zip(names, cells).filter { !$0.0.isEmpty }.map { ($0.0, $0.1) },
                        uniquingKeysWith: { first, _ in first }
                    ))
                }
        }
    }

    /// Zweispaltige Schlüssel/Wert-Tabelle.
    struct KeyValues {
        let values: [String: String]

        init(_ raw: [[String]]) {
            values = Dictionary(
                raw.dropFirst().compactMap { row -> (String, String)? in
                    guard let key = row.first else { return nil }
                    return (key.trimmingCharacters(in: .whitespaces), row.count > 1 ? row[1] : "")
                },
                uniquingKeysWith: { first, _ in first }
            )
        }

        subscript(key: String) -> String {
            values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    /// Formatierung und tolerantes Parsen von Zellwerten.
    /// Liest auch Werte, die Excel beim Bearbeiten umwandelt (Datums-/Zeit-Seriennummern).
    enum Cell {
        private static let calendar = Calendar.school
        private static let weekdays = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

        static func date(_ date: Date?) -> String {
            guard let date else { return "" }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }

        static func dateTime(_ date: Date) -> String {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return "\(self.date(date)) \(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))"
        }

        static func bool(_ value: Bool) -> String { value ? "ja" : "nein" }

        static func linkKind(_ kind: DashboardLink.Kind) -> String {
            switch kind {
            case .file: "Dokument"
            case .image: "Bild"
            case .website: "Website"
            case .shortcut: "Kurzbefehl"
            case .script: "Skript"
            }
        }

        static func parseLinkKind(_ text: String) -> DashboardLink.Kind {
            let lower = text.lowercased()
            if lower.hasPrefix("dok") { return .file }
            if lower.hasPrefix("bild") { return .image }
            if lower.hasPrefix("kurz") { return .shortcut }
            if lower.hasPrefix("skript") { return .script }
            return .website
        }
        static func list(_ values: [String]) -> String { values.joined(separator: "; ") }

        /// Rasterpunkte als „x,y; x,y; …“.
        static func points(_ points: [GridPoint]) -> String {
            points.map { "\($0.x),\($0.y)" }.joined(separator: "; ")
        }

        /// Liest „x,y; x,y“ (auch mit Leerzeichen); `nil`, wenn ein Punkt ungültig ist.
        static func parsePoints(_ text: String) -> [GridPoint]? {
            let parts = parseList(text)
            let points = parts.compactMap { part -> GridPoint? in
                let numbers = part.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
                guard numbers.count == 2, let x = numbers[0], let y = numbers[1] else { return nil }
                return GridPoint(x, y)
            }
            return points.count == parts.count ? points : nil
        }

        static func parseRoomCategory(_ text: String) -> RoomCategory {
            RoomCategory.allCases.first { $0.title.caseInsensitiveCompare(text) == .orderedSame } ?? .other
        }

        static func parseRoomElementKind(_ text: String) -> RoomElementKind? {
            RoomElementKind.allCases.first { $0.title.caseInsensitiveCompare(text) == .orderedSame }
        }
        static func weekday(_ index: Int) -> String { weekdays.indices.contains(index) ? weekdays[index] : "" }

        static func parseList(_ text: String) -> [String] {
            text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        static func parseBool(_ text: String) -> Bool? {
            switch text.lowercased() {
            case "ja", "yes", "true", "wahr", "1", "x": true
            case "nein", "no", "false", "falsch", "0": false
            default: nil
            }
        }

        static func parseWeekday(_ text: String) -> Int? {
            if let number = Int(text), (1...7).contains(number) { return number - 1 }
            let lower = text.lowercased()
            return weekdays.firstIndex { $0.lowercased() == lower || $0.lowercased().prefix(2) == lower.prefix(2) && lower.count >= 2 }
        }

        static func parseGender(_ text: String) -> Gender? {
            let lower = text.lowercased()
            return Gender.allCases.first { $0.title == lower || String($0.title.prefix(1)) == lower || $0.rawValue == lower }
        }

        /// „2026-09-29“, „29.09.2026“ oder Excel-Seriennummer.
        static func parseDate(_ text: String) -> Date? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let serial = Double(trimmed) { return excelDate(serial) }
            let datePart = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
            let iso = datePart.split(separator: "-").compactMap { Int($0) }
            if iso.count == 3 { return calendar.date(from: DateComponents(year: iso[0], month: iso[1], day: iso[2])) }
            let german = datePart.split(separator: ".").compactMap { Int($0) }
            if german.count == 3 {
                let year = german[2] < 100 ? 2000 + german[2] : german[2]
                return calendar.date(from: DateComponents(year: year, month: german[1], day: german[0]))
            }
            return nil
        }

        /// „2026-09-29 08:00“, Datum allein oder Excel-Seriennummer mit Bruchteil.
        static func parseDateTime(_ text: String) -> Date? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let serial = Double(trimmed) { return excelDate(serial) }
            guard let day = parseDate(trimmed) else { return nil }
            let parts = trimmed.split(separator: " ")
            guard parts.count > 1, let minutes = parseTime(String(parts[1])) else { return day }
            return calendar.date(byAdding: .minute, value: minutes, to: day)
        }

        /// „08:05“ oder Excel-Zeit (Tagesbruchteil) → Minuten seit Mitternacht.
        static func parseTime(_ text: String) -> Int? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let fraction = Double(trimmed), fraction < 1, !trimmed.contains(":") {
                return Int((fraction * 24 * 60).rounded())
            }
            let parts = trimmed.split(separator: ":").compactMap { Int($0) }
            guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
            return parts[0] * 60 + parts[1]
        }

        /// Excel zählt Tage ab 30.12.1899 (inkl. des historischen Schaltjahr-Fehlers).
        private static func excelDate(_ serial: Double) -> Date? {
            guard serial > 1, serial < 2_958_466,
                  let base = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30)),
                  let day = calendar.date(byAdding: .day, value: Int(serial), to: base)
            else { return nil }
            let minutes = Int(((serial - serial.rounded(.down)) * 24 * 60).rounded())
            return calendar.date(byAdding: .minute, value: minutes, to: day)
        }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
