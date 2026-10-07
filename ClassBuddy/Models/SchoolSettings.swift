import Foundation
import SwiftUI

/// Schulweite Einstellungen: Stundenraster, Pausen, Kalender-Optionen, Schule, Lehrkraft.
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
        /// Schulform (Vorgaben für Bewertungs-Skalen); `nil` = aus der Klassenbezeichnung.
        var schoolType: SchoolType?
        /// Leistungsarten (Vorgaben plus eigene) und umbenannte Bereiche (leer = Vorgabe des Bundeslands).
        var assessmentTypes = AssessmentType.defaults
        var areaNames: [String: String] = [:]
        var holidaysImportedAt: Date?
        var school = SchoolInfo()
        var teacher = TeacherProfile()

        init() {}

        /// Fehlende Felder (ältere Versionen) fallen auf den Standardwert zurück,
        /// damit neue Einstellungen nie die gespeicherten überschreiben.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Values()
            dayStart = try container.decodeIfPresent(Int.self, forKey: .dayStart) ?? defaults.dayStart
            dayEnd = try container.decodeIfPresent(Int.self, forKey: .dayEnd) ?? defaults.dayEnd
            lessonDuration = try container.decodeIfPresent(Int.self, forKey: .lessonDuration) ?? defaults.lessonDuration
            breaks = try container.decodeIfPresent([BreakTime].self, forKey: .breaks) ?? defaults.breaks
            showWeekends = try container.decodeIfPresent(Bool.self, forKey: .showWeekends) ?? defaults.showWeekends
            federalState = try container.decodeIfPresent(String.self, forKey: .federalState)
            schoolType = try container.decodeIfPresent(SchoolType.self, forKey: .schoolType)
            assessmentTypes = try container.decodeIfPresent([AssessmentType].self, forKey: .assessmentTypes) ?? defaults.assessmentTypes
            areaNames = try container.decodeIfPresent([String: String].self, forKey: .areaNames) ?? [:]
            holidaysImportedAt = try container.decodeIfPresent(Date.self, forKey: .holidaysImportedAt)
            school = try container.decodeIfPresent(SchoolInfo.self, forKey: .school) ?? defaults.school
            teacher = try container.decodeIfPresent(TeacherProfile.self, forKey: .teacher) ?? defaults.teacher
        }
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
    var sortedBreaks: [BreakTime] { values.sortedBreaks }

    /// Stundenraster (siehe `Values.slots`).
    var slots: [LessonSlot] { values.slots }
}

extension SchoolSettings.Values {
    /// Pausen innerhalb des Schultags, nach Beginn sortiert.
    var sortedBreaks: [BreakTime] {
        breaks
            .filter { $0.duration > 0 && $0.end > dayStart && $0.start < dayEnd }
            .sorted { $0.start < $1.start }
    }

    /// Stundenraster: ab Beginn im Takt der Stundenlänge, Pausen werden übersprungen.
    /// Eine Stunde, die nicht mehr vor die nächste Pause passt, beginnt nach der Pause.
    var slots: [LessonSlot] {
        let length = max(lessonDuration, 5)
        let breaks = sortedBreaks
        var result: [LessonSlot] = []
        var time = dayStart

        while time + length <= dayEnd, result.count < 30 {
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

/// Stammdaten der Schule.
extension SchoolSettings.Values {
    /// Name eines Bereichs: umbenannt oder Vorgabe des Bundeslands.
    func areaName(_ area: AssessmentArea) -> String {
        areaNames[area.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? area.defaultName(federalState: federalState)
    }

    /// Leistungsarten zur Auswahl (ohne ausgeblendete); ohne schriftliche Arbeiten nur „sonstige“.
    func selectableTypes(hasWrittenWork: Bool) -> [AssessmentType] {
        assessmentTypes.filter { !$0.isHidden && (hasWrittenWork || $0.area == .other) }
    }
}

struct SchoolInfo: Codable, Equatable {
    var name = ""
    var website = ""
    var street = ""
    var postalCode = ""
    var city = ""
    var phone = ""
    var email = ""

    /// Website als URL (ergänzt „https://“, lehnt http & Co. ab – siehe `URL.web`).
    var websiteURL: URL? { URL.web(website) }
}

/// Die Lehrkraft, die die App nutzt.
struct TeacherProfile: Codable, Equatable {
    var firstName = ""
    var lastName = ""
    var birthday: Date?
    var gender: Gender?
    /// Hauptfächer – stehen im Fächer-Picker der Klassen oben.
    var subjects: [String] = []

    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension TeacherProfile {
    /// Fehlende Felder (ältere Versionen) fallen auf den Standardwert zurück.
    /// In einer Extension, damit der Memberwise-Initializer erhalten bleibt.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        birthday = try container.decodeIfPresent(Date.self, forKey: .birthday)
        gender = try container.decodeIfPresent(Gender.self, forKey: .gender)
        subjects = try container.decodeIfPresent([String].self, forKey: .subjects) ?? []
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
