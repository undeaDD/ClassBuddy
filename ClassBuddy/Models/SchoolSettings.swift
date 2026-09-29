import Foundation
import SwiftUI

/// Schulweite Einstellungen: Stundenraster, Pausen, Kalender-Optionen.
/// Zeiten jeweils in Minuten seit Mitternacht. Persistiert als JSON in UserDefaults.
@Observable
final class SchoolSettings {
    struct Values: Codable, Equatable {
        var dayStart = 8 * 60
        var dayEnd = 15 * 60 + 30
        var lessonDuration = 45
        var breaks: [BreakTime] = [
            BreakTime(start: 9 * 60 + 30, duration: 20),
            BreakTime(start: 11 * 60 + 20, duration: 15),
            BreakTime(start: 13 * 60 + 5, duration: 45),
        ]
        var showWeekends = false
        /// ISO-3166-2-Code des Bundeslands, z. B. „DE-NW“.
        var federalState: String?
        var holidaysImportedAt: Date?
    }

    var values: Values {
        didSet { save() }
    }

    private static let key = "school.settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Values.self, from: data) {
            values = decoded
        } else {
            values = Values()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    /// Angezeigte Wochentage (0 = Montag … 6 = Sonntag).
    var visibleWeekdays: [Int] {
        values.showWeekends ? Array(0..<7) : Array(0..<5)
    }

    /// Pausen innerhalb des Schultags, nach Beginn sortiert.
    var sortedBreaks: [BreakTime] {
        values.breaks
            .filter { $0.duration > 0 && $0.end > values.dayStart && $0.start < values.dayEnd }
            .sorted { $0.start < $1.start }
    }

    /// Stundenraster: ab Beginn im Takt der Stundenlänge, Pausen werden übersprungen.
    /// Eine Stunde, die nicht mehr vor die nächste Pause passt, beginnt nach der Pause.
    var slots: [LessonSlot] {
        let length = max(values.lessonDuration, 5)
        let breaks = sortedBreaks
        var result: [LessonSlot] = []
        var time = values.dayStart

        while time + length <= values.dayEnd, result.count < 30 {
            if let current = breaks.first(where: { $0.start <= time && time < $0.end }) {
                time = current.end
                continue
            }
            if let next = breaks.first(where: { $0.start > time }), time + length > next.start {
                time = next.end
                continue
            }
            result.append(LessonSlot(index: result.count, start: time, end: time + length))
            time += length
        }
        return result
    }
}

struct BreakTime: Codable, Hashable, Identifiable {
    var id = UUID()
    var start: Int
    var duration: Int

    var end: Int { start + duration }
}

/// Eine Unterrichtsstunde im Raster („3. Stunde, 09:50–10:35“).
struct LessonSlot: Hashable, Identifiable {
    let index: Int
    let start: Int
    let end: Int

    var id: Int { index }
    var number: Int { index + 1 }
    var timeRange: String { "\(start.clockString)–\(end.clockString)" }
}

extension Int {
    /// Minuten seit Mitternacht als „08:05“.
    var clockString: String {
        String(format: "%02d:%02d", (self / 60) % 24, self % 60)
    }
}
