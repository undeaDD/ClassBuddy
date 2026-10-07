import Foundation

// Globale Statistiken: Zähler (lokal in UserDefaults) und reine Berechnungen für die Diagramme.

/// Lokale Zähler – werden nirgends hingeschickt, nur im Excel-Backup (Blatt „Statistiken“) gesichert.
nonisolated enum FunStat: String, CaseIterable, Identifiable {
    case appLaunches = "stats.appLaunches"
    case randomPicks = "stats.randomPicks"
    case groupsDealt = "stats.groupsDealt"
    case timerMinutes = "stats.timerMinutes"
    case loudSeconds = "stats.loudSeconds"
    case boardPhotos = "stats.boardPhotos"
    case checksSet = "stats.checksSet"
    case observations = "stats.observations"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appLaunches: loc("App gestartet")
        case .randomPicks: loc("Zufallsauswahlen")
        case .groupsDealt: loc("Gruppen gemischt")
        case .timerMinutes: loc("Timer-Minuten")
        case .loudSeconds: loc("Zu laut")
        case .boardPhotos: loc("Tafelbilder aufgenommen")
        case .checksSet: loc("Haken gesetzt")
        case .observations: loc("Beobachtungen")
        }
    }

    /// Schlüssel im Excel-Backup (immer Deutsch, nie ändern).
    var backupKey: String {
        switch self {
        case .appLaunches: "App gestartet"
        case .randomPicks: "Zufallsauswahlen"
        case .groupsDealt: "Gruppen gemischt"
        case .timerMinutes: "Timer-Minuten"
        case .loudSeconds: "Sekunden zu laut"
        case .boardPhotos: "Tafelbilder aufgenommen"
        case .checksSet: "Haken gesetzt"
        case .observations: "Beobachtungen"
        }
    }

    static func currentValues(in defaults: UserDefaults = .standard) -> [FunStat: Int] {
        allCases.reduce(into: [:]) { $0[$1] = $1.value(in: defaults) }
    }

    func value(in defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: rawValue)
    }

    func set(_ value: Int, in defaults: UserDefaults = .standard) {
        defaults.set(max(0, value), forKey: rawValue)
    }

    func increment(by amount: Int = 1, in defaults: UserDefaults = .standard) {
        guard amount > 0 else { return }
        set(value(in: defaults) + amount, in: defaults)
    }

    /// Anzeigewert, z. B. „12 min“ oder „3 min 20 s“.
    func formatted(_ value: Int) -> String {
        switch self {
        case .timerMinutes:
            return value >= 60 ? loc("\(value / 60) h \(value % 60) min") : loc("\(value) min")
        case .loudSeconds:
            return value >= 60 ? loc("\(value / 60) min \(value % 60) s") : loc("\(value) s")
        default:
            return value.formatted()
        }
    }
}

/// Ferien bzw. Feiertag als reiner Wert (testbar ohne SwiftData).
nonisolated struct HolidayRange: Hashable {
    var name: String
    var start: Date
    var end: Date
    var isSchoolHoliday: Bool

    func contains(_ day: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: day)
        return calendar.startOfDay(for: start) <= day && day <= calendar.startOfDay(for: end)
    }
}

nonisolated enum StatsLogic {
    struct NextHoliday: Equatable {
        let name: String
        let start: Date
        let schoolDays: Int
    }

    /// Nächste Schulferien und die Schultage bis dahin (heute zählt mit; Feiertage und freie Wochentage nicht).
    static func nextHoliday(
        _ holidays: [HolidayRange], weekdays: [Int], today: Date, calendar: Calendar = .school
    ) -> NextHoliday? {
        let start = calendar.startOfDay(for: today)
        // Laufende Ferien zählen nicht: dann die übernächsten.
        guard let next = holidays
            .filter({ $0.isSchoolHoliday && calendar.startOfDay(for: $0.start) > start })
            .min(by: { $0.start < $1.start })
        else { return nil }
        let end = calendar.startOfDay(for: next.start)
        var days = 0
        var day = start
        while day < end {
            let isFree = holidays.contains { $0.contains(day, calendar: calendar) }
            if weekdays.contains(calendar.mondayBasedWeekday(of: day)), !isFree {
                days += 1
            }
            guard let following = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = following
        }
        return NextHoliday(name: next.name, start: next.start, schoolDays: days)
    }

    /// Schuljahr: vom Ende der letzten bis zum Beginn der nächsten Sommerferien; ohne Ferien 1. August bis 31. Juli.
    static func schoolYear(_ holidays: [HolidayRange], today: Date, calendar: Calendar = .school) -> DateInterval {
        let day = calendar.startOfDay(for: today)
        let summers = holidays.filter { $0.isSchoolHoliday && $0.name.localizedCaseInsensitiveContains("Sommer") }
        let lastEnd = summers.filter { calendar.startOfDay(for: $0.end) < day }.map(\.end).max()
            .flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        let nextStart = summers.filter { calendar.startOfDay(for: $0.start) > day }.map(\.start).min()
            .map { calendar.startOfDay(for: $0) }

        let year = calendar.component(.year, from: day)
        let startYear = calendar.component(.month, from: day) >= 8 ? year : year - 1
        let fallbackStart = calendar.date(from: DateComponents(year: startYear, month: 8, day: 1)) ?? day
        let fallbackEnd = calendar.date(from: DateComponents(year: startYear + 1, month: 8, day: 1)) ?? day
        let start = lastEnd ?? fallbackStart
        let end = max(nextStart ?? fallbackEnd, start)
        return DateInterval(start: start, end: end)
    }

    /// Anteil des Schuljahrs, der schon vorbei ist (0…1).
    static func progress(of interval: DateInterval, at date: Date) -> Double {
        guard interval.duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(interval.start) / interval.duration, 0), 1)
    }

    /// Geburtstage je Monat (Index 0 = Januar).
    static func birthdaysPerMonth(_ birthdays: [Date], calendar: Calendar = .school) -> [Int] {
        var counts = Array(repeating: 0, count: 12)
        for birthday in birthdays {
            counts[calendar.component(.month, from: birthday) - 1] += 1
        }
        return counts
    }

    /// Anzahl je Alter (aufsteigend), nur vorhandene Alter.
    static func ageDistribution(_ birthdays: [Date], today: Date, calendar: Calendar = .school) -> [(age: Int, count: Int)] {
        let ages = birthdays.compactMap { calendar.dateComponents([.year], from: $0, to: today).year }
        return Dictionary(grouping: ages, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.age < $1.age }
    }

    /// Belegung des Stundenplans: Anzahl regelmäßiger Stunden je Wochentag und Stunde.
    static func heatmap(_ lessons: [(weekday: Int, slot: Int)]) -> [Cell: Int] {
        lessons.reduce(into: [:]) { $0[Cell(weekday: $1.weekday, slot: $1.slot), default: 0] += 1 }
    }

    struct Cell: Hashable {
        let weekday: Int
        let slot: Int
    }
}
