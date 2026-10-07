import SwiftData
import SwiftUI
import UIKit
import WidgetKit

/// Hält den Stundenplan des Widgets aktuell: beim Start, beim Verlassen der App und wenn sich Stunden ändern.
/// Unsichtbar, hängt an `RootView`.
struct WidgetScheduleSync: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SchoolSettings.self) private var settings
    @Query private var lessons: [Lesson]
    @Query private var holidays: [Holiday]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task { write() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { write() }
            }
            // Neue, gelöschte oder verschobene Stunden (Raum, Klasse …) sofort übernehmen.
            .onChange(of: lessons.map(\.persistentModelID)) { write() }
    }

    private func write() {
        let schedule = LessonSchedule(lessons: lessons, holidays: holidays, slots: settings.slots)
        try? WidgetSchedule.save(Self.upcoming(in: schedule, slots: settings.slots, from: .now))
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSchedule.widgetKind)
    }

    /// Alle Stunden der nächsten 14 Tage (laufende eingeschlossen), wie im Kalender: Ferien und Einzelstunden beachtet.
    static func upcoming(in schedule: LessonSchedule, slots: [LessonSlot], from now: Date, days: Int = 14) -> [WidgetSchedule.Lesson] {
        let calendar = Calendar.school
        let today = calendar.startOfDay(for: now)
        var result: [WidgetSchedule.Lesson] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for slot in slots {
                guard let lesson = schedule.lesson(on: day, slotIndex: slot.index),
                      let start = calendar.date(byAdding: .minute, value: slot.start, to: day),
                      let end = calendar.date(byAdding: .minute, value: slot.end, to: day),
                      end > now
                else { continue }
                let rgb = RGB(lesson.schoolClass?.displayColor ?? .accentColor)
                result.append(WidgetSchedule.Lesson(
                    start: start,
                    end: end,
                    slotNumber: slot.number,
                    className: lesson.schoolClass?.shortName ?? "",
                    subject: SchoolClass.displayName(ofSubject: lesson.subject),
                    room: lesson.room?.name,
                    red: rgb.red, green: rgb.green, blue: rgb.blue
                ))
            }
        }
        return result
    }

    /// Klassenfarbe (helle Variante) als RGB für das Widget.
    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        init(_ color: Color) {
            let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            (self.red, self.green, self.blue) = (Double(red), Double(green), Double(blue))
        }
    }
}

/// Data Protection „vollständig“ (Entitlement) gilt nur für neu angelegte Dateien. Bestehende Dateien früherer
/// Versionen (Datenbank, Fotos, Dokumente) werden einmalig auf denselben Schutz umgestellt.
nonisolated enum DataProtectionMigration {
    private static let doneKey = "dataProtection.completeMigrated.v1"

    static func runIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        let fileManager = FileManager.default
        let roots = [FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory, .cachesDirectory]
            .compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
        for root in roots {
            guard let files = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in files {
                try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
