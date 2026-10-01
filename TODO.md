# TODO: Räume

Nächste große Ansicht. Ersetzt den Platzhalter in `ClassBuddy/Features/Rooms/RoomsView.swift`.

## Ziel

Räume der Schule mit einem nahezu freien Grundriss (Tische, Tafel, Pult, Tür) anlegen,
Tische in 1 bis 3 Bereiche aufteilen und festlegen, welche Fächer in einem Raum
unterrichtet werden können. Später Grundlage für die Sitzplatzverwaltung.

## Datenmodell (SwiftData)

- [ ] `Room`
  - `name` (z. B. „R 204“), `subtitle` (z. B. „Physikraum, 2. OG“)
  - `category` (Klassenraum, Fachraum, Sporthalle, Aula, Sonstiges) für Karte und Filter
  - `assignments: [String]`: 1 bis n Unterrichtsfächer; leer bzw. „Alle Fächer“ beim generischen Klassenraum
  - `sortIndex`, `isHidden` (Anordnen und Ausblenden in der Übersicht)
  - `canvasSize` (Raumgröße in Rastereinheiten), `createdAt`, `updatedAt`
- [ ] `RoomElement` (Cascade von `Room`)
  - `kind`: Tisch (einzeln/doppelt), Lehrerpult, Tafel/Board, Tür, Fenster, Schrank, Waschbecken, Säule
  - `x`, `y`, `width`, `height`, `rotation` (in Rastereinheiten, nicht in Punkten → geräteunabhängig)
  - `seats` (Plätze pro Tisch), `areaIndex` (0 bis 2, nur bei Tischen), `label` (optional)
- [ ] `RoomArea`: bis zu 3 Bereiche pro Raum mit Name und Farbe (z. B. „Fensterseite“, „Mitte“, „Tür“)
- [ ] Reine Logik (`nonisolated`) testbar halten: Einrasten, Kollision, Bereichszuordnung, Belegung

## Übersicht (RoomsView)

- [ ] Grid mit Karten pro Raum: kleine Grundriss-Vorschau, Name, Kategorie (wie die Dashboard-Karten, feste Höhe)
- [ ] Antippen → Editor
- [ ] Gedrückt halten → Kontextmenü: Bearbeiten, Duplizieren, Ausblenden, Entfernen (mit Bestätigung)
- [ ] Suche (`.searchable`) über Name, Untertitel, Kategorie und Fächer
- [ ] Anordnen-Modus (Stift/Haken in der Toolbar wie in der Übersicht): Drag & Drop, Auge zum Ausblenden, xmark zum Entfernen
- [ ] Ausgeblendete Räume im Anordnen-Modus sichtbar (abgeschwächt), sonst nicht
- [ ] Leerer Zustand mit „Raum hinzufügen“ und Vorlagen

## Editor (Canvas)

- [ ] Nahezu freie Platzierung mit Raster zum Einrasten (abschaltbar), Hilfslinien beim Ausrichten
- [ ] Zoom per Pinch und Verschieben mit zwei Fingern; „Einpassen“-Button
- [ ] Elemente per Drag verschieben, Griffe zum Skalieren und Drehen (15°-Schritte)
- [ ] Mehrfachauswahl (Lasso oder Aufziehen) → gemeinsam verschieben, ausrichten, verteilen
- [ ] Leichtes Nachpflegen: einzelne Tische verschieben, ohne den Rest anzufassen; Duplizieren; Reihen/Blöcke erzeugen
- [ ] Bereiche zuweisen: Tische auswählen → Bereich 1/2/3 (farbig markiert)
- [ ] Tafel, Lehrerpult und Tür als eigene Elemente mit klaren Symbolen
- [ ] Rückgängig/Wiederholen (`UndoManager`, auch per Tastatur ⌘Z / ⇧⌘Z)
- [ ] Apple Pencil im Bearbeitungsmodus:
  - Tisch zeichnen: Rechteck skizzieren → wird zu sauberem Tisch
  - Doppeltippen (Pencil) schaltet zwischen Auswählen und Zeichnen
  - Hover (Pencil Pro/M-Serie) zeigt Vorschau der Einrastposition
- [ ] Vorlagen: Reihen, U-Form, Gruppentische, Sporthalle (leer), Computerraum
- [ ] Touchbedienung ohne Apple Pencil: auf dem iPhone (und iPad ohne Pencil) vollständig mit Fingern bedienbar
      (Verschieben, Drehen, Skalieren, Bereiche zuweisen); Pencil-Funktionen sind nur Zusatz

## Optional: KI-Unterstützung (niedrige Priorität)

- [ ] Handskizze oder Foto des Raums → sauberer, minimaler Grundriss (Vorschlag, den man anpasst)
- [ ] Nur Apple Intelligence lokal auf dem Gerät (Foundation Models, ggf. Vision), keine Dienste Dritter
- [ ] Erst prüfen, ob das Modell die Aufgabe überhaupt zuverlässig lösen kann; sonst Punkt streichen
- [ ] Verfügbarkeit prüfen (`SystemLanguageModel.default.availability`):
      Gerät nicht unterstützt, Apple Intelligence deaktiviert, Modell noch nicht geladen
      → Funktion ausblenden bzw. passenden Hinweis zeigen

## Privatsphäre-Modus

- [ ] Raumname, Untertitel und Fachzuordnungen ausblenden (`.cardPrivacy()` / `.sensitive()`)
- [ ] Grundriss-Vorschau bleibt sichtbar (enthält keine personenbezogenen Daten)
- [ ] Später bei Sitzplänen: Schülernamen auf den Tischen ausblenden

## Excel-Export und -Import

- [ ] Neues Blatt „Räume“: Name, Untertitel, Kategorie, Fächer, Raster, Reihenfolge, ausgeblendet
- [ ] Neues Blatt „Raumelemente“: Raum, Art, x, y, Breite, Höhe, Drehung, Plätze, Bereich, Beschriftung
- [ ] Import in `BackupImport` ergänzen; ältere Dateien ohne diese Blätter weiter unterstützen
- [ ] Tests: Hin- und Rückweg (Export → Import) inkl. Drehung und Bereichen, Fixture aktualisieren

## Verknüpfungen

- [ ] Stunden im Kalender optional einem Raum zuordnen (`Lesson.room`); Warnung, wenn das Fach nicht zum Raum passt
- [ ] Antippen einer Stunde im Kalender öffnet den zugeordneten Raum mit den Schülern der Klasse auf ihren Plätzen
      (vorerst öffnet es nur den Räume-Tab; Bearbeiten/Entfernen per langem Drücken)
- [ ] Dashboard-Kachel „Aktueller Raum“ bzw. „Nächster Raum“
- [ ] Vorbereitung Sitzplan: Klasse + Raum → Schüler auf Plätze ziehen (eigene Ansicht, später)

## Weitere Ideen

- [ ] Raumkapazität automatisch aus den Plätzen berechnen und auf der Karte zeigen
- [ ] Ausstattung als Stichworte (Beamer, Whiteboard, Dokumentenkamera, Steckdosen, Waschbecken)
- [ ] Drucken bzw. PDF über das System-Teilen-Menü: Grundriss mit Sitzplan (Schülernamen auf den Plätzen),
      immer im hellen Erscheinungsbild, unabhängig vom Dunkelmodus

## Bewusst nicht geplant

- Suche/Filter nach Fach (Räume werden für die Lehrkräfte vorab geplant)
- Gebäude und Etagen
- Barrierefreiheit (VoiceOver, Rollstuhlplatz) und Übersetzungen (i18n) vorerst nicht

## Qualität

- [ ] SwiftLint 0/0, Semgrep 0, alle Tests grün, Deploy aufs iPad
