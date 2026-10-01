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

- [ ] Eigene Icons statt SF Symbols (ins `Icons/`-Postfach legen, `scripts/sync-icons.sh`)
- [ ] SwiftLint 0/0, Semgrep 0, alle Tests grün, Deploy aufs iPad

---

# TODO: iPhone-Support & Bugfixes

Umfassende Optimierung für das iPhone, Behebung von Layout- und Navigationsfehlern, Absicherung gegen iPad-Regressionen.

## Ziel & Geräte-Differenzierung

- [x] Globaler Geräte-Manager (`Device.isPhone`, `Device.isPad` bzw. Trait-basierte Weiche)
  - Einheitliche Prüfung für iPhone-spezifische Layout- und Sheet-Anpassungen
  - Sicherstellen, dass alle bestehenden iPad-Funktionen, Popover und Größenverhältnisse unverändert bleiben

## Debug-Menü

- [x] **Debug-Menü** (`#if DEBUG`) in den Einstellungen (`SettingsView.swift` / eigene Unteransicht)
  - Schneller Zugriff und Testmöglichkeit für schwer erreichbare Screens und Zustände:
    - Sperrbildschirm (`LockScreenView`) mit Retry-Button und Fehlermeldungen
    - Privatsphäre-Abdeckung (`PrivacyCoverView`)
    - Leerzustände (`EmptyStateView`) für verschiedene Tabs und Sichten
    - Weitere seltene Dialoge / Toast-Meldungen / Fehlerzustände

## Navigation & Tab-Bar (iPhone)

- [x] **Eigener moderner „Mehr“-Tab (Custom More Controller / View)** (`AppTabView.swift`)
  - Bei mehr als 5 Tabs schaltet iOS auf kompakten Geräten auf den veralteten Standard-„Mehr“-Reiter um
  - Ersatz durch eine zeitgemäße, ansprechende Übersicht:
    - Frei anordbare Tabs (Reorderability / Drag & Drop)
    - Gruppierte Sektionen mit Überschriften (einklappbar / Collapsible)
    - Modernes Styling analog zum restlichen Designsystem
- [x] **Doppel-Navbar-Bug beheben**
  - Beim Öffnen der Einstellungen über den „Mehr“-Tab erscheint aktuell eine doppelte Navigation Bar (erste Navbar enthält nur einen leeren Zurück-Button ohne Titel; zweite Navbar darunter enthält Klassen-Button, Titel und Privatsphäre-Button)
  - NavigationStack-Hierarchie und Toolbar-Integration für sekundäre Tabs im More-Tab bereinigen

## Kalender (iPhone)

- [x] **Kompakte 3-Tage-Ansicht auf dem iPhone** (`CalendarView.swift`)
  - Vollständige Wochenansicht ist auf schmalen iPhone-Bildschirmen zu gequetscht
  - Auf dem iPhone auf 3 Tage begrenzen: Gestern, Heute, Morgen (bzw. gleitendes 3-Tage-Fenster)
  - Auf dem iPad weiterhin die volle Woche anzeigen
- [x] **Monats- und Wochennavigation in untere Toolbar verlagern** (`CalendarView.swift`)
  - Monats-/KW-Wechsler in der oberen Toolbar nimmt zu viel horizontalen Platz weg
  - Auf dem iPhone in eine untere Toolbar direkt über der Tab-Bar verschieben
  - Verifizieren, dass der Navigationstitel oben wieder vollständig und ohne Abschneiden Platz findet
- [x] **Stunden-Slot Antippen (LessonEditorView)** (`DayColumn.swift`, `CalendarEditors.swift`)
  - Nutzt bisher ein Popover (`.presentationCompactAdaptation(.popover)`)
  - Auf dem iPhone zu einem vollwertigen Sheet anpassen
- [x] **Einmalig-Symbol in Stunden-Zellen** (`DayColumn.swift`)
  - „1“-Kreis vor das Klassenkürzel (unten, gleiche Grundlinie) statt neben das Fach → mehr Platz für den Fachnamen
- [x] **Termine mit Klasse** (`CalendarEntry`, `EntryEditorView`, `DayColumn.swift`)
  - Termine optional einer Klasse zuordnen (auch außerhalb der Schulzeit) und dann in der Klassenfarbe
    wie die Stunden-Karten einfärben
  - Umgekehrt: Termine ohne Klasse auch innerhalb der Schulzeit sauber darstellen
- [x] **Neuer Termin Sheet-Layout & Buttons** (`EntryEditorView`, `CalendarView.swift`)
  - Bugfix: Inhalt startet auf dem iPhone in der Mitte des Fullscreen-Sheets statt oben (`.presentationSizing(.fitted)` / Zentrierungs-Ursache beheben)
  - Fehlenden Abbrechen-Button (`xmark`-Icon) in der Toolbar ergänzen

## Klassenverwaltung (ClassPicker & ClassEditor)

- [x] **Klassenliste (`ClassPickerView.swift`)**
  - „Abwählen“-Button aus der Toolbar entfernen (auch auf dem iPad – Abwahl erfolgt bereits intuitiv durch erneutes Antippen der aktiven Klasse)
  - Auf dem iPhone die vollwertige `EmptyStateView` nutzen (da Fullscreen-Sheet statt kleines iPad-Popover)
- [x] **Klasse anlegen / bearbeiten (`ClassEditorView.swift`, `ClassBadge.swift`)**
  - Avatar-Vorschaukreis (`ClassBadge`): Wenn noch kein Kürzel eingegeben wurde, ein Minus (`-`) statt des Plus (`+`) anzeigen (für iPad und iPhone)
  - Toolbar-Aktionen: Text-Buttons („Abbrechen“ / „Anlegen“) durch Icon-Buttons ersetzen (`xmark` und `checkmark`) – für iPad und iPhone
  - Fach hinzufügen: Vom Menü zu einer separaten Picker-Unterseite umbauen
  - Farbpalette: Weniger Farben auf einmal anzeigen (aktuell alle Optionen in einer einzigen horizontalen Zeile gequetscht); Farbauswahl am Ende (`ColorPicker` für eigene Farben) beibehalten

## Schüler-Formular (StudentEditorView)

- [x] **Hintergrund & Layout auf dem iPhone** (`StudentEditorView.swift`)
  - Falschen Hintergrund des Fullscreen-Sheets auf dem iPhone korrigieren
- [x] **Toolbar-Buttons** (`StudentEditorView.swift`)
  - Text-Buttons „Abbrechen“ und „Anlegen“ durch Icons ersetzen (`xmark` und `checkmark`)
- [x] **Geschlechtsauswahl (`PersonFields.swift` / `GenderPicker`)**
  - Segmented Control auf dem iPhone durch ein kompaktes Picker-Menü (Pop-up-Menü) ersetzen

## Einstellungen & Profile

- [x] **Einstellungs-Übersicht (`SettingsView.swift`)**
  - Hero-Bereich: Beschreibungstext einkürzen; Umbruch der Info-Pills (`HeroChip`) verhindern
  - Versionszeile: Text ist zu lang und bricht um. „iOS“ weglassen und Geräte-Präfixe abkürzen (`p` für Phone, `t` für Tablet, z. B. `p15,2` / `t13,4`), Versionsnummern beibehalten
  - Textfarben der Zeilenbeschriftungen vereinheitlichen (Label-Konsistenz)
  - Chevron-Pfeile (`nav-arrow-right`) am Ende von Zeilen ergänzen, die Untermenüs/Dateidialoge öffnen (z. B. Export/Import)
- [x] **App-Einstellungen (`AppSettingsView.swift`)**
  - Darstellung: Segmented Control (System / Hell / Dunkel) durch Picker-Menü-Popup ersetzen
  - „Alle lokalen Daten löschen“: Icon rot färben (bisher fälschlicherweise in Akzentfarbe) passend zum roten Text; Chevron am Zeilenende ergänzen
- [x] **Schuleinstellungen (`SchoolSettingsView.swift`)**
  - Pausen-Zeilen: Uneinheitliche Abstände korrigieren (Abstand TimePicker ↔ Dauer ist kleiner als Dauer ↔ Stepper-Buttons)
  - Zeile „Ferien & Feiertage importieren“: Chevron-Icon am rechten Rand ergänzen
- [x] **Lehrerprofil (`TeacherProfileView.swift`)**
  - Geschlechtsauswahl auf dem iPhone ebenfalls als Picker-Row / Pop-up-Menü statt Segmented Control darstellen

## Dashboard & allgemeine UI-Elemente

- [x] **Übersichts-Kacheln auf dem iPhone** (`DashboardView.swift`)
  - Alle Kacheln (echte Kacheln, „Hinzufügen“-Kachel …) auf volle Breite ziehen (enden aktuell ein paar Punkte zu früh)
- [x] **Karten-Galerie (`CardGallery.swift`)**
  - „Abbrechen“-Text-Button durch `xmark`-Icon-Button in der Toolbar ersetzen
- [x] **Leerzustände (`EmptyStateView.swift`)**
  - Schriftgrößen von Titel und Untertitel für iPhone-Displays skalieren / verkleinern (aktuell zu groß)
- [x] **Icon-Audit & Bereinigung**
  - Keine SF Symbols mehr im Code (`number1-circle`, `community`, `search`); `AppSymbol.system`/`.private` entfernt

## Qualität

- [x] Keine Regressionen auf dem iPad (Layouts, Popover und Navigation prüfen)
- [x] SwiftLint 0/0, Semgrep 0, Unit-Tests grün
- [x] Getestet auf iPhone (kleines & großes Display) sowie iPad

---

# TODO: Alternatives App-Icon (optional)

- [ ] Optional: alternatives App-Icon (`UIApplication.setAlternateIconName`)

---

# TODO: App Intents (Apple Intelligence, sehr optional)

- [ ] **App Intents** für Siri, Kurzbefehle und Apple Intelligence
  - Z. B. Klasse wählen, Übersicht/Kalender/Schüler öffnen, nächste Stunde abfragen, Zufallsauswahl, Timer starten
  - `AppEntity` für Klassen (und ggf. Schüler – Privatsphäre beachten: App-Sperre / Privatsphäre-Modus respektieren)
  - `AppShortcutsProvider` mit deutschen Phrasen

