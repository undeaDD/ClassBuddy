# TODO: Räume

Nächste große Ansicht. Ersetzt den Platzhalter in `ClassBuddy/Features/Rooms/RoomsView.swift`.

## Ziel

Räume der Schule als Grundriss auf einem Punktraster zeichnen: Raumumriss, Tische und Lehrerpult als Flächen,
Tafel, Tür und Fenster als Linien. Jeder Tisch ist ein Sitzplatz; Tische lassen sich in weitere Tische teilen.
Pro Raum festlegen, welche Fächer dort unterrichtet werden können. Später Grundlage für den Sitzplan.

## Datenmodell (SwiftData)

- [ ] `GridPoint` (`x`, `y` als `Int`, `Codable`): Rasterpunkt, geräteunabhängig, keine Gleitkommazahlen
- [ ] `Room`
  - `name` (z. B. "R 204"), `subtitle` (z. B. "Physikraum, 2. OG")
  - `category` (Klassenraum, Fachraum, Sporthalle, Aula, Sonstiges) für Karte und Filter
  - `assignments: [String]`: 1 bis n Unterrichtsfächer; leer bzw. "Alle Fächer" beim generischen Klassenraum
  - `sortIndex`, `isHidden` (Anordnen und Ausblenden in der Übersicht)
  - `createdAt`, `updatedAt`
- [ ] `RoomElement` (Cascade von `Room`)
  - `kind`: Raumumriss, Tisch, Lehrerpult, Tafel, Tür, Fenster (= Stift in der Toolbox)
  - `points: [GridPoint]`: Linienzug; bei Raumumriss, Tisch und Lehrerpult geschlossen (letzter Punkt = erster Punkt)
- [ ] Sitzplatz = Tisch (geschlossene Fläche des Tisch-Stifts); Teilen ersetzt einen Tisch durch zwei angrenzende Tische
- [ ] Raumgrenzen = min/max x/y des Raumumrisses; keine eigene `canvasSize`
- [ ] Normalisieren beim Speichern: alle Punkte so verschieben, dass min x/y des Umrisses bei 0/0 liegt
- [ ] Gültigkeit (Speichern nur, wenn alles gültig ist; sonst Hinweis, was fehlt):
  - Pflicht ist nur genau ein geschlossener Raumumriss; alles andere ist optional (z. B. Sporthalle ohne Tische und Tafel)
  - Tische und Lehrerpult geschlossen, ohne Selbstüberschneidung oder fremdüberschneidung ( gleiche knotennutzung ist erlaubt! )
  - alle Elemente innerhalb des Raumumrisses (auf dem Umriss ist erlaubt, z. B. Tafel)
  - Tür und Fenster liegen nur auf dem Raumumriss
  - keine Überlappung: Elemente dürfen sich nicht schneiden; Angrenzen über gemeinsame Punkte/Kanten ist erlaubt
  - Trennlinien beginnen und enden auf dem Rand desselben Tisches und verlaufen nur innen,
    nie nach außen oder zu einem anderen Tisch
- [ ] Reine Logik (`nonisolated`) testbar halten: Einrasten, Schnitt/Überlappung, Punkt-in-Polygon,
      Flächen teilen, Normalisieren, Gültigkeit

## Übersicht (RoomsView)

- [ ] Grid mit Karten pro Raum: kleine Grundriss-Vorschau, Name, Kategorie, Anzahl Plätze (wie die Dashboard-Karten, feste Höhe)
- [ ] Antippen → Editor
- [ ] Gedrückt halten → Kontextmenü: Bearbeiten, Duplizieren, Entfernen (mit Bestätigung)
- [ ] Suche (`.searchable`) über Name, Untertitel, Kategorie und Fächer
- [ ] Leerer Zustand mit "Raum hinzufügen"
- [ ] Demo-Klassenzimmer beim ersten App-Start anlegen: normaler, editierbarer Raum ohne Sitzplan;
      wird es entfernt, kommt es nicht wieder

## Editor (Canvas)

- [ ] Vollbild-Sheet: xmark oben links (Verwerfen, bei Änderungen mit Bestätigung), Speichern oben rechts
      (deaktiviert, solange der Raum ungültig ist)
- [ ] Unendliches quadratisches Punktraster; beim erneuten Bearbeiten wird der gespeicherte Raum mit Rand angezeigt
- [ ] Zwei Finger: Verschieben und Pinch-Zoom (Raster zoomt mit, Rasterabstand bleibt gleich); "Einpassen"-Button
- [ ] Zeichnen mit einem Finger oder Pencil: Linien verbinden zwei beliebige Rasterpunkte (auch schräg),
      jede Strecke rastet an Rasterpunkten ein, der Linienzug läuft am letzten Punkt weiter
- [ ] Toolbox unten über `FloatingBottomBar`, als getrennte Glas-Gruppen mit Abstand:
      Stifte und Radierer | Rückgängig/Wiederholen (vorerst ein gemeinsames SF-Symbol als Platzhalter für alle fehlenden Icons; echte Icons werden von Hand
      ergänzt und in die Icon-Packs aufgenommen)
  - Raumumriss (Primärfarbe): Linie, geschlossen; Grundlage für Raumgrenzen
  - Tisch (braun): Fläche; beim Schließen (Startpunkt erreicht) als Tisch markiert und gefüllt
  - Lehrerpult (orange): Fläche wie ein Tisch, aber kein Sitzplatz
  - Tafel (grün): nur Linie
  - Tür (grau), Fenster (blau): nur Linien auf dem Raumumriss, darüber gezeichnet (höherer z-Index), damit gut sichtbar
  - Farben als System-Farben (hell und dunkel lesbar), später anpassbar
  - Flächen (Raumumriss, Tisch, Lehrerpult) mit stark transparenter Stiftfarbe gefüllt; Tische liegen über der
    Raumfläche, die Farben mischen sich dort sichtbar
- [ ] Tisch teilen: mit dem Tisch-Stift innerhalb eines bestehenden Tisches von Rand zu Rand zeichnen
      → aus einem Tisch werden zwei angrenzende Tische
- [ ] Radierer: Antippen entfernt Linie, Tisch oder Lehrerpult
- [ ] Ungültige Stellen markieren (offener Tisch, außerhalb des Raums, Überlappung); Speichern bis dahin deaktiviert
- [ ] Rückgängig/Wiederholen (`UndoManager`, Buttons in der Toolbox, auch per Tastatur ⌘Z / ⇧⌘Z)
- [ ] Speichern eines Raums mit Sitzplänen: Hinweis, wie viele Zuordnungen durch geänderte oder entfernte Tische verloren gehen
- [ ] Apple Pencil:
  - Doppeltippen (Pencil) schaltet zwischen aktuellem Stift und Radierer
  - Hover (Pencil Pro/M-Serie) zeigt Vorschau des nächsten Rasterpunkts
- [ ] Touchbedienung ohne Apple Pencil: auf dem iPhone (und iPad ohne Pencil) vollständig mit Fingern bedienbar;
      Pencil-Funktionen sind nur Zusatz

## Optional: KI-Unterstützung (niedrige Priorität / highly optional)

- [ ] comic realistische bildgenerierung von der raumskizze ( teppichboden, fenster mit lichtschein, tisch textur füllung, ...)
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

- [ ] Neues Blatt "Räume": Name, Untertitel, Kategorie, Fächer, Reihenfolge, ausgeblendet
- [ ] Neues Blatt "Raumelemente": Raum, Art, Punkte (`x,y; x,y; …`)
- [ ] Import in `BackupImport` ergänzen und dieselbe Gültigkeitsprüfung wie im Editor anwenden;
      ältere Dateien ohne diese Blätter weiter unterstützen
- [ ] Tests: Hin- und Rückweg (Export → Import), ungültige Räume beim Import, Fixture aktualisieren

## Verknüpfungen

- [ ] Stunden im Kalender optional einem Raum zuordnen (`Lesson.room`); Warnung, wenn das Fach nicht zum Raum passt
- [ ] Antippen einer Stunde im Kalender öffnet den zugeordneten Raum mit den Schülern der Klasse auf ihren Plätzen
      (sitzplan)
- [ ] Dashboard-Kachel "Aktueller Raum" bzw. "Nächster Raum" ( öffnet ebenfalls sitzplan nicht raum detail / editor )
- [ ] Sitzplan (eigene Ansicht, später): Klasse + Raum → Schüler aus der Seitenleiste (mit Suchfilter) per
      Drag & Drop auf Sitzplätze ziehen; zugeordnete Schüler verschwinden aus der Seitenleiste;
      zwei Finger zum Verschieben und Zoomen; keine Platznummern -> erstelle vorerst eine leere platzhlater view ...
- [ ] Zuordnung hängt am Tisch (`RoomElement`): wird ein Tisch geändert, geteilt oder entfernt, geht seine Zuordnung
      verloren und der Schüler muss neu zugeordnet werden; Normalisieren allein ändert nichts

## Weitere Ideen

- [ ] Ausstattung als multiselect picker (Beamer, Whiteboard, Dokumentenkamera, Steckdosen, Waschbecken, ...)
- [ ] Drucken bzw. PDF über das System-Teilen-Menü: Grundriss mit Sitzplan (Schülernamen auf den Plätzen),
      immer im hellen Erscheinungsbild, unabhängig vom Dunkelmodus

## Bewusst nicht geplant

- Suche/Filter nach Fach (Räume werden für die Lehrkräfte vorab geplant)
- Gebäude und Etagen ( pläne / verbindungen / flure )
- Bereiche im Raum (auch nicht im Sitzplan) und Sitzplatznummern
- Vorlagen (stattdessen ein Demo-Klassenzimmer beim ersten start)
- Drehen, Skalieren, Verschieben, Griffe, Lasso und Mehrfachauswahl, rasterloses Freihandzeichnen
- Tische zusammenführen (stattdessen radieren und neu zeichnen)
- Dreiecks- oder Sechseckraster (freie Linien decken Schrägen ab)
- Barrierefreiheit (VoiceOver, Rollstuhlplatz)

## Qualität

- [ ] SwiftLint 0/0, Semgrep 0, alle Tests grün, Deploy aufs iPad
