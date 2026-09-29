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
        case badResponse

        var errorDescription: String? { "Die Ferien konnten nicht geladen werden." }
    }

    /// Ersetzt alle gespeicherten Ferien/Feiertage durch die des Bundeslands
    /// (Zeitraum: 1 Jahr zurück bis 2 Jahre voraus). Gibt die Anzahl zurück.
    @discardableResult
    static func importHolidays(for stateCode: String, into context: ModelContext) async throws -> Int {
        let calendar = Calendar.school
        let from = calendar.date(byAdding: .year, value: -1, to: .now) ?? .now
        let to = calendar.date(byAdding: .year, value: 2, to: .now) ?? .now

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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ImportError.badResponse }
        return try JSONDecoder().decode([APIHoliday].self, from: data)
    }

    /// „2026-10-17“ → lokaler Tagesbeginn (ohne UTC-Verschiebung).
    private static func parseDay(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.school.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func dayString(_ date: Date) -> String {
        let c = Calendar.school.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
