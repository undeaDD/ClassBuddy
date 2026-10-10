# TODO

Stand: 10.10.2026. Getestet wird gesammelt (Liste unten).

## Icons

- [ ] „Bewertung einstellen“ (bisher `settings`), „Eingetroffen um“ (bisher `timer`), „Notensystem“ (bisher `graduation-cap`)

## Offene Fragen

- [ ] „Leistungsarten und Bereiche“ aus den Schuleinstellungen in das Sheet „Neue Leistung“ verschieben („Arten bearbeiten …“)?

## Bugs

- [ ] Einfrieren (v. a. Einstellungen), tritt weiter auf: Backtrace zeigte eine UIKit-Endlosschleife beim Push/Zurückwischen
      (Safe Area → Scroll-Beobachter → Höhe der Navigationsleiste). Minimieren der Navigationsleiste ist schon entfernt.
      Vorerst nicht bearbeiten. Falls es wieder hängt: App eingefroren lassen, `scripts/hang-backtrace.sh`

## Lizenz (du)

- [ ] GitHub: Beschreibung und Topics prüfen (PolyForm Strict 1.0.0, Verlauf ist umgeschrieben, Release 1.0.0 (4) neu angelegt)
- [ ] App-Store-Beschreibung: kein „Open Source“ mehr

## Testphase per In-App-Kauf

Umgesetzt (10.10.2026): `PurchaseStore` (StoreKit 2), Kaufseite als letzte Seite der Einführung, Testphasen-Kachel,
Debug-Menü „Kauf-Status simulieren“, `Config/ClassBuddy.storekit` (im Schema eingetragen), Datenschutz und Support-Seite.
Produkte: `de.devsforge.ClassBuddy.full` (4,99 €) und `de.devsforge.ClassBuddy.trial` (0 €), beide „Nicht-verbrauchbar“,
ohne Familienfreigabe. Nach Ablauf ist nur die Kaufseite erreichbar, kein Export. TestFlight nutzt automatisch die Sandbox.

- [ ] Schema prüfen (du): Product › Scheme › Edit Scheme › Run › Options › StoreKit Configuration zeigt `ClassBuddy.storekit`
      (sonst dort auswählen)
- [ ] Icons der Kaufkarten und der Testphasen-Kachel: vorläufig SF Symbols (`hourglass`, `checkmark.seal`)

Kein Sideloading mehr: Workflow „Build IPA“, README-Abschnitt, AltStore-Erkennung und IPA im Release entfernt.

## App-Store-Bilder

- [ ] Geräterahmen (Ton-Look) liefern: `Marketing/Frames/` (iphone, ipad, duo; Format siehe README dort)
- [ ] Roh-Screenshots aufnehmen: `scripts/appstore-screenshots.sh` (eigene Simulatoren), dann `scripts/appstore-images.sh`
- [ ] Texte prüfen: `Marketing/captions.json` (Überschriften je Seite, Kopfzeile, Suchzeile; de und en)
- [ ] Hochladen: Kopfzeile + Suchzeile (5244 × 2950), iPhone 6,1″/6,3″ und iPhone Duo (1920 × 886), iPad 13″ (1600 × 1200)

## Manuell testen (iPhone und iPad)

- [ ] Kaufen (lokal, Debug-Menü „Kauf-Status simulieren“ oder StoreKit-Datei): Einführung ohne xmark und ohne Wegwischen,
      Kaufseite mit „30 Tage kostenlos testen“ (hervorgehoben) und „Vollversion kaufen“, „Käufe wiederherstellen“;
      Hintergrund ohne Entscheidung → Einführung beginnt von vorn; abgelaufen → nur Kaufseite, Karte „Testphase abgelaufen“;
      Testphasen-Kachel zuerst auf der Übersicht, öffnet die Kaufseite mit xmark; iPad: App dahinter unscharf
- [ ] Raum-Editor, Werkzeug „Maus“: Eckpunkte ziehen (Raum, Tisch, Tafel, Tür …), gemeinsame Ecken wandern mit,
      daneben verschiebt weiter den Ausschnitt; Rückgängig; zweiter Finger während des Ziehens bricht ab

- [ ] iPhone Duo: komplette App durchtesten (Layout, Tab-Leiste, Übersicht, Sitzplan, Widget)
- [ ] Demo-Raum aus Sicht der Lehrkraft (Tafel und Pult unten): wird beim Start jetzt umgestellt (falls unverändert),
      sonst Debug-Menü → „Demo-Klassenzimmer zurücksetzen“
- [ ] Tipps (frisch installiert): Klassen-Button-Popover sauber am Button, Einrichtungs-Kette auf der Übersicht
      (Schüler → Stundenplan → Schulzeiten → Raum → Ferien), „Zu den Schuleinstellungen“ auf dem iPhone (über „Mehr“),
      Privatsphäre-Tipp nach 3 Starts, „Kacheln anordnen“ danach, Schalter „Tipps anzeigen“

## Später

- [ ] Fehlzeiten-Merkliste: offen → entschuldigt / unentschuldigt, offene Fehlzeiten bleiben in den folgenden Stunden sichtbar,
      Frist (Schulvorgabe) mit Hinweis
- [ ] Checklisten ohne Schüler: einfache Klassen-Checkliste (Punkte statt Schüler, z. B. „Bücher bestellt“), Art beim Anlegen wählen
- [ ] Optional Kategorie je Beobachtung: Qualität, Quantität, Arbeitsverhalten, Sozialverhalten
- [ ] Eigener Notenschlüssel (Tabelle Prozent → Note) zusätzlich zur Abitur-Tabelle
- [ ] Selbst eingetragene Noten auch je Bereich (Modell kann es schon: `GradeScope`), bisher nur für das ganze Fach

Hinweis Schülerakte: Die App rechnet keine Noten aus (rechtlich nicht erlaubt), Einstellungen gelten je Klasse + Fach.
Skizzen für Lehrkräfte: https://claude.ai/artifact/ETRRLuZduF8Bte9q5hmjeR
