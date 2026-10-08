import SwiftUI
import Testing
import UIKit
@testable import ClassBuddy

@Suite("Ältere iOS-Versionen, eigene Tab-Leiste & Glas")
struct CompatibilityTests {
    /// Erwartete Texte sind deutsch – unabhängig von der Sprache des Simulators.
    init() {
        AppLanguage.current = .german
    }

    // MARK: Minimieren der Tab-Leiste beim Scrollen

    /// Liste mit Inhalt von 0 bis 1000 pt.
    private static let top: CGFloat = 0
    private static let bottom: CGFloat = 1000

    private func scroll(
        _ tracker: inout TabBarScrollTracker, to offsets: [CGFloat], isUserScrolling: Bool = true
    ) -> [Bool?] {
        offsets.map {
            tracker.update(offset: $0, top: Self.top, bottom: Self.bottom, isUserScrolling: isUserScrolling)
        }
    }

    @Test("Runterscrollen minimiert erst ab der Schwelle")
    func minimizesAfterThreshold() {
        var tracker = TabBarScrollTracker()
        tracker.reset(offset: 100, top: Self.top, bottom: Self.bottom)
        let results = scroll(&tracker, to: [110, 120, 130])
        #expect(results == [nil, nil, true])
    }

    @Test("Hochscrollen vergrößert wieder")
    func expandsWhenScrollingUp() {
        var tracker = TabBarScrollTracker()
        tracker.reset(offset: 500, top: Self.top, bottom: Self.bottom)
        #expect(scroll(&tracker, to: [550]) == [true])
        #expect(scroll(&tracker, to: [540, 520]) == [nil, false])
    }

    @Test("Richtungswechsel beginnt die Strecke von vorn")
    func directionChangeResetsTravel() {
        var tracker = TabBarScrollTracker()
        tracker.reset(offset: 500, top: Self.top, bottom: Self.bottom)
        // 20 runter, 10 hoch, dann wieder 20 runter: keine Richtung erreicht 24 pt am Stück.
        #expect(scroll(&tracker, to: [520, 510, 530]) == [nil, nil, nil])
    }

    @Test("Ganz oben ist die Leiste immer groß, auch ohne Geste")
    func topAlwaysExpands() {
        var tracker = TabBarScrollTracker()
        tracker.reset(offset: 300, top: Self.top, bottom: Self.bottom)
        #expect(scroll(&tracker, to: [0], isUserScrolling: false) == [false])
        // Nachfedern über den Anfang hinaus zählt als „oben“.
        #expect(scroll(&tracker, to: [-40], isUserScrolling: true) == [false])
    }

    @Test("Scrollen per Code (ohne Geste) ändert nichts")
    func ignoresProgrammaticScrolling() {
        var tracker = TabBarScrollTracker()
        tracker.reset(offset: 100, top: Self.top, bottom: Self.bottom)
        #expect(scroll(&tracker, to: [200, 400], isUserScrolling: false) == [nil, nil])
    }

    @Test("Abprallen am Ende vergrößert die Leiste nicht")
    func bottomBounceIsIgnored() {
        var tracker = TabBarScrollTracker()
        tracker.reset(offset: 960, top: Self.top, bottom: Self.bottom)
        // Runter bis über das Ende hinaus (begrenzt auf 1000), dann zurückfedern auf 1000.
        #expect(scroll(&tracker, to: [1000, 1060, 1000]) == [true, nil, nil])
    }

    @Test("Inhalt mit eingerückter Oberkante (große Titel)")
    func respectsTopInset() {
        var tracker = TabBarScrollTracker()
        tracker.reset(offset: -96, top: -96, bottom: 800)
        #expect(tracker.update(offset: -96, top: -96, bottom: 800, isUserScrolling: true) == false)
        #expect(tracker.update(offset: -60, top: -96, bottom: 800, isUserScrolling: true) == true)
    }

    // MARK: Eigene Tab-Leiste

    @Test("Tab-Leiste: Hauptseiten und „Mehr“, ohne Doppelte")
    func floatingTabSlots() {
        #expect(FloatingTabSlot.all == [.tab(.dashboard), .tab(.calendar), .tab(.students), .more])
        #expect(Set(FloatingTabSlot.all).count == FloatingTabSlot.all.count)
    }

    @Test("Tab-Leiste: Titel")
    func floatingTabTitles() {
        #expect(FloatingTabSlot.all.map(\.title) == ["Übersicht", "Kalender", "Schüler", "Mehr"])
    }

    // MARK: Glas

    @Test("Glas: Standard ist normal, ungetönt, nicht interaktiv")
    func glassDefaults() {
        #expect(AppGlass.regular == AppGlass(variant: .regular, tint: nil, isInteractive: false))
        #expect(AppGlass.clear.variant == .clear)
        #expect(AppGlass.identity.variant == .identity)
    }

    @Test("Glas: Tönung und Interaktivität lassen die Variante unverändert")
    func glassBuilders() {
        let glass = AppGlass.clear.tint(.red).interactive()
        #expect(glass.variant == .clear)
        #expect(glass.tint == .red)
        #expect(glass.isInteractive)
        #expect(!glass.interactive(false).isInteractive)
        #expect(glass.tint(nil).tint == nil)
    }

    @Test("Schließen-Rolle: ab iOS 26 die System-Rolle")
    func closeRole() {
        if #available(iOS 26, *) {
            #expect(ButtonRole.appClose == .close)
        } else {
            #expect(ButtonRole.appClose == .cancel)
        }
    }

    // MARK: SF Symbols

    @Test("Ersatzsymbole gibt es auf jedem System und nur für bekannte Icons")
    func symbolFallbacksExist() {
        for (icon, name) in IconTheme.sfSymbolFallbackNames {
            #expect(UIImage(systemName: name) != nil, "\(name) fehlt")
            #expect(IconTheme.sfSymbolNames[icon] != nil)
            #expect(IconTheme.sfSymbolNames[icon] != name)
        }
    }

    @Test("Jedes SF-Symbol-Icon hat auf diesem System ein Bild")
    func availableSymbolsCoverAllIcons() {
        #expect(Set(IconTheme.availableSFSymbolNames.keys) == Set(IconTheme.sfSymbolNames.keys))
        for name in IconTheme.availableSFSymbolNames.values {
            #expect(UIImage(systemName: name) != nil, "\(name) fehlt")
        }
    }

    @Test("Auf neuen Systemen bleiben die Original-Symbole")
    func originalSymbolsWin() {
        // Der Test-Simulator läuft mit dem neuesten iOS: dort gibt es alle Originale.
        #expect(IconTheme.availableSFSymbolNames == IconTheme.sfSymbolNames)
    }

    // MARK: Rechtliches (HTML)

    private static let html = """
        :root { --accent: #9c6830; --pill: rgba(156, 104, 48, 0.12); }
        @media (prefers-color-scheme: dark) { :root { --accent: #cd9c5e; --pill: rgba(205, 156, 94, 0.16); } }
        """

    @Test("Rechtliche Seiten: Standard-Akzent bleibt unverändert")
    func legalPageDefaultAccent() {
        #expect(LegalDocumentView.applyingAccent(to: Self.html, accent: AppAccent.defaultValue) == Self.html)
    }

    @Test("Rechtliche Seiten: gewählte Akzentfarbe ersetzt das Braun (hell und dunkel)")
    func legalPageCustomAccent() {
        let result = LegalDocumentView.applyingAccent(to: Self.html, accent: "#336699")
        let light = AppAccent.cssHex(for: "#336699", dark: false)
        #expect(!result.contains("#9c6830"))
        #expect(!result.contains("#cd9c5e"))
        #expect(result.contains("--accent: \(light);"))
        #expect(result.contains("--pill: \(light)1f;"))
    }
}
