import Foundation
import SwiftData

/// Importiert Schulferien und gesetzliche Feiertage eines Bundeslands
/// von der OpenHolidays API (openholidaysapi.org, frei, ohne Schlüssel).
/// Nur öffentliche Daten werden abgerufen – es werden keine App-Daten gesendet.
enum HolidayImporter {
    static let federalStates: [(code: String, name: String)] = [
        ("DE-BW", "Baden-Württemberg"), ("DE-BY", "Bayern"), ("DE-BE", "Berlin"),
        ("DE-BB", "Brandenburg"), ("DE-HB", "Bremen"), ("DE-HH", "Hamburg"),
        ("DE-HE", "Hessen"), ("DE-MV", "Mecklenburg-Vorpommern"), ("DE-NI", "Niedersachsen"),
        ("DE-NW", "Nordrhein-Westfalen"), ("DE-RP", "Rheinland-Pfalz"), ("DE-SL", "Saarland"),
        ("DE-SN", "Sachsen"), ("DE-ST", "Sachsen-Anhalt"), ("DE-SH", "Schleswig-Holstein"),
        ("DE-TH", "Thüringen"),
    ]

    private struct APIHoliday: Decodable {
        struct LocalizedText: Decodable {
            let language: String
            let text: String
        }

        let id: String
        let startDate: String
        let endDate: String
        let name: [LocalizedText]
    }

    enum ImportError: LocalizedError {
        case badResponse(status: Int, detail: String?)

        var errorDescription: String? {
            switch self {
            case .badResponse(let status, let detail):
                "Die Ferien konnten nicht geladen werden (\(status)\(detail.map { ": \($0)" } ?? ""))."
            }
        }
    }

    /// Fehlerantwort der API (RFC 9457 „problem details“).
    private struct Problem: Decodable {
        let detail: String?
    }

    /// Die API erlaubt höchstens 1095 Tage pro Anfrage (Start und Ende inklusive).
    private static let maxRangeDays = 1094

    /// Ersetzt alle gespeicherten Ferien/Feiertage durch die des Bundeslands
    /// (Zeitraum: ½ Jahr zurück, dann so weit voraus wie die API erlaubt, ≈ 2½ Jahre).
    /// Gibt die Anzahl zurück.
    @discardableResult
    static func importHolidays(for stateCode: String, into context: ModelContext) async throws -> Int {
        let calendar = Calendar.school
        let from = calendar.date(byAdding: .month, value: -6, to: calendar.startOfDay(for: .now)) ?? .now
        let to = calendar.date(byAdding: .day, value: maxRangeDays, to: from) ?? .now

        async let school = fetch("SchoolHolidays", stateCode: stateCode, from: from, to: to)
        async let publicHolidays = fetch("PublicHolidays", stateCode: stateCode, from: from, to: to)
        let (schoolItems, publicItems) = try await (school, publicHolidays)

        try context.delete(model: Holiday.self)
        var count = 0
        for (items, isSchool) in [(schoolItems, true), (publicItems, false)] {
            for item in items {
                guard let start = parseDay(item.startDate), let end = parseDay(item.endDate) else { continue }
                let name = item.name.first { $0.language == "DE" }?.text ?? item.name.first?.text ?? "Frei"
                context.insert(Holiday(id: item.id, name: name, startDate: start, endDate: end, isSchoolHoliday: isSchool))
                count += 1
            }
        }
        try context.save()
        return count
    }

    private static func fetch(_ endpoint: String, stateCode: String, from: Date, to: Date) async throws -> [APIHoliday] {
        var components = URLComponents(string: "https://openholidaysapi.org/\(endpoint)")!
        components.queryItems = [
            URLQueryItem(name: "countryIsoCode", value: "DE"),
            URLQueryItem(name: "subdivisionCode", value: stateCode),
            URLQueryItem(name: "languageIsoCode", value: "DE"),
            URLQueryItem(name: "validFrom", value: dayString(from)),
            URLQueryItem(name: "validTo", value: dayString(to)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let detail = try? JSONDecoder().decode(Problem.self, from: data).detail
            throw ImportError.badResponse(status: status, detail: detail)
        }
        return try JSONDecoder().decode([APIHoliday].self, from: data)
    }

    /// „2026-10-17“ → lokaler Tagesbeginn (ohne UTC-Verschiebung).
    private static func parseDay(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.school.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func dayString(_ date: Date) -> String {
        let parts = Calendar.school.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
