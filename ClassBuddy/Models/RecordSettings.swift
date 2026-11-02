import Foundation
import SwiftData

// Bewertung: Skala für Beobachtungen, Notensystem, schriftliche Arbeiten. Vorgabe je Stufe (App oder Schule),
// optional eine eigene Bewertung je Klasse.

/// Gewählte Bewertung: für eine Stufe in den Schuleinstellungen oder als eigene Einstellung einer Klasse.
nonisolated struct RecordChoice: Codable, Hashable {
    var scale: ObservationScale
    var gradeSystem: GradeSystem
    var hasWrittenWork: Bool
}

/// Werte der Einstellungen (gespeichert oder Vorgabe).
nonisolated struct RecordSettings: Equatable {
    var scale: ObservationScale
    var gradeSystem: GradeSystem
    var hasWrittenWork: Bool
    var stage: SchoolStage

    var choice: RecordChoice {
        get { RecordChoice(scale: scale, gradeSystem: gradeSystem, hasWrittenWork: hasWrittenWork) }
        set {
            scale = newValue.scale
            gradeSystem = newValue.gradeSystem
            hasWrittenWork = newValue.hasWrittenWork
        }
    }

    /// Vorgaben je Stufe; eine Wahl der Schule für die Stufe (`stageChoices`) ersetzt sie.
    static func defaults(
        className: String, schoolType: SchoolType?, stageChoices: [SchoolStage: RecordChoice] = [:]
    ) -> RecordSettings {
        var values = builtIn(className: className, schoolType: schoolType)
        if let choice = stageChoices[values.stage] { values.choice = choice }
        return values
    }

    /// Vorgaben der App: Grundschule Smileys (1–2) bzw. − o +, Sek. I 7 Stufen mit Noten, Oberstufe 7 Stufen mit Punkten.
    static func builtIn(className: String, schoolType: SchoolType?) -> RecordSettings {
        let stage = SchoolStage.detect(className: className, schoolType: schoolType)
        switch stage {
        case .primary:
            let early = SchoolStage.isEarlyPrimary(className: className)
            return RecordSettings(
                scale: early ? .smileys : .threeStep, gradeSystem: early ? .none : .grades, hasWrittenWork: !early, stage: stage
            )
        case .secondary:
            return RecordSettings(scale: .sevenStep, gradeSystem: .grades, hasWrittenWork: true, stage: stage)
        case .upper:
            return RecordSettings(scale: .sevenStep, gradeSystem: .points, hasWrittenWork: true, stage: stage)
        }
    }
}

/// Bewertung: Vorgabe der Stufe (aus Schulform und Klassenbezeichnung, in den Schuleinstellungen änderbar), optional
/// eine eigene Einstellung der Klasse. Gespeichert als `SubjectSettings` ohne Fach (früher je Fach, das entfällt).
extension SchoolClass {
    var recordOverride: RecordChoice? {
        subjectSettings.first { $0.subject.isEmpty }.map {
            RecordChoice(scale: $0.scale, gradeSystem: $0.gradeSystem, hasWrittenWork: $0.hasWrittenWork)
        }
    }

    func recordSettings(school: SchoolSettings.Values) -> RecordSettings {
        var values = RecordSettings.defaults(className: shortName, schoolType: school.schoolType, stageChoices: school.stageChoices)
        if let override = recordOverride { values.choice = override }
        return values
    }

    /// `nil` = wieder die Vorgabe der Schule.
    func setRecordOverride(_ choice: RecordChoice?, in context: ModelContext) {
        let stored = subjectSettings.first { $0.subject.isEmpty }
        guard let choice else {
            if let stored { context.delete(stored) }
            return
        }
        if let stored {
            stored.scale = choice.scale
            stored.gradeSystem = choice.gradeSystem
            stored.hasWrittenWork = choice.hasWrittenWork
        } else {
            context.insert(SubjectSettings(
                subject: "", scale: choice.scale, gradeSystem: choice.gradeSystem, hasWrittenWork: choice.hasWrittenWork,
                schoolClass: self
            ))
        }
    }
}

extension SubjectSettings {
    private static let migrationKey = "records.stageSettingsMigrated"

    /// Einmal nach dem Update auf Bewertung je Stufe (danach nicht mehr, sonst würde eine spätere bewusste Änderung
    /// der Schulvorgabe immer wieder überschrieben).
    static func migrateOnce(school: SchoolSettings.Values, in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        migrate(school: school, in: context)
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// Frühere Einstellungen je Fach in eine eigene Bewertung der Klasse übernehmen und entfernen. Klassen ohne eigene
    /// Bewertung, deren Beobachtungen eine andere Skala nutzen als die Vorgabe der Schule, bekommen diese Skala als
    /// eigene Bewertung, damit vorhandene Daten ihre Bedeutung behalten. Auch nach einem Excel-Import (ältere
    /// Backups enthalten Einstellungen je Fach).
    static func migrate(school: SchoolSettings.Values, in context: ModelContext) {
        guard let classes = try? context.fetch(FetchDescriptor<SchoolClass>()) else { return }
        for schoolClass in classes {
            let old = schoolClass.subjectSettings.filter { !$0.subject.isEmpty }
            if schoolClass.recordOverride == nil {
                let defaults = schoolClass.recordSettings(school: school).choice
                let oldChoices = old.map { RecordChoice(scale: $0.scale, gradeSystem: $0.gradeSystem, hasWrittenWork: $0.hasWrittenWork) }
                var choice = mostCommon(oldChoices) ?? defaults
                let usedScales = schoolClass.students.flatMap(\.observations).filter { $0.kind == .rating }.map(\.scale)
                if let used = mostCommon(usedScales) { choice.scale = used }
                if choice != defaults { schoolClass.setRecordOverride(choice, in: context) }
            }
            old.forEach(context.delete)
        }
        try? context.save()
    }

    private static func mostCommon<T: Hashable>(_ values: [T]) -> T? {
        Dictionary(grouping: values, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}

extension SchoolStage {
    /// Stufen einer Schulform (ohne Schulform alle).
    static func stages(of schoolType: SchoolType?) -> [SchoolStage] {
        switch schoolType {
        case .primary: [.primary]
        case .special, .secondaryGeneral, .secondaryIntermediate: [.secondary]
        case .comprehensive, .grammar: [.secondary, .upper]
        case .vocational: [.upper]
        case nil: allCases
        }
    }

    /// Vorgabe der App für die Stufe (Grundschule ab Klasse 3).
    var builtInChoice: RecordChoice {
        let example = switch self {
        case .primary: "3a"
        case .secondary: "7a"
        case .upper: "Q1"
        }
        return RecordSettings.builtIn(className: example, schoolType: nil).choice
    }
}
