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
- [ ] Filter nach Kategorie bzw. Fach (z. B. „Wo kann ich Physik unterrichten?“)
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

## Optional: KI-Unterstützung

- [ ] Handskizze oder Foto des Raums → sauberer, minimaler Grundriss (Vorschlag, den man anpasst)
- [ ] Nur mit ausdrücklicher Zustimmung; bevorzugt on-device (Foundation Models / Vision),
      keine Übertragung von Fotos an Dritte ohne Hinweis (DSGVO, Datenschutzerklärung anpassen)

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
- [ ] Dashboard-Kachel „Aktueller Raum“ bzw. „Nächster Raum“
- [ ] Vorbereitung Sitzplan: Klasse + Raum → Schüler auf Plätze ziehen (eigene Ansicht, später)

## Weitere Ideen

- [ ] Raumkapazität automatisch aus den Plätzen berechnen und auf der Karte zeigen
- [ ] Ausstattung als Stichworte (Beamer, Whiteboard, Dokumentenkamera, Steckdosen, Waschbecken)
- [ ] Barrierefreiheit: Rollstuhlplatz markieren, Fluchtweg/Notausgang
- [ ] Grundriss als PDF/Bild exportieren oder drucken (Vertretungsmappe)
- [ ] Mehrere Gebäude/Etagen zur Gruppierung
- [ ] VoiceOver: Elemente mit Art, Position und Bereich beschreiben; Verschieben per Tastatur/Pfeiltasten

## Qualität

- [ ] Eigene Icons statt SF Symbols (ins `Icons/`-Postfach legen, `scripts/sync-icons.sh`)
- [ ] SwiftLint 0/0, Semgrep 0, alle Tests grün, Deploy aufs iPad
