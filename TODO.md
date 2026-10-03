# TODO: Räume

Räume, Editor, Verknüpfungen und Excel-Export sind umgesetzt. Offen sind nur noch die Punkte unten.

## Sitzplan

- [ ] Platzhalter `SeatingPlanView` durch die echte Ansicht ersetzen: Klasse + Raum → Schüler aus der Seitenleiste
      (mit Suchfilter) per Drag & Drop auf Tische ziehen; zugeordnete Schüler verschwinden aus der Seitenleiste;
      zwei Finger zum Verschieben und Zoomen; keine Platznummern
- [ ] Zuordnungen als `SeatAssignment` speichern (Modell, Löschregeln und Verlust-Hinweis im Editor gibt es schon)
- [ ] Schülernamen auf den Tischen im Privatsphäre-Modus ausblenden (Grundlage vorhanden)

## Optional: KI-Unterstützung (niedrige Priorität / highly optional)

- [ ] comic realistische bildgenerierung von der raumskizze ( teppichboden, fenster mit lichtschein, tisch textur füllung, ...)
- [ ] Nur Apple Intelligence lokal auf dem Gerät (Foundation Models, ggf. Vision), keine Dienste Dritter
- [ ] Erst prüfen, ob das Modell die Aufgabe überhaupt zuverlässig lösen kann; sonst Punkt streichen
- [ ] Verfügbarkeit prüfen (`SystemLanguageModel.default.availability`):
      Gerät nicht unterstützt, Apple Intelligence deaktiviert, Modell noch nicht geladen
      → Funktion ausblenden bzw. passenden Hinweis zeigen

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

- [ ] Auf iPhone und iPad testen (Zeichnen, Teilen, Radierer, Pencil, Toolbox-Breite auf dem iPhone, PDF)
- [ ] SwiftLint 0/0, Semgrep 0, alle Tests grün
