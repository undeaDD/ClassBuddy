# TODO

Stand: 07.10.2026. Getestet wird gesammelt (Liste unten).

## Icons

- [ ] „Bewertung einstellen“ (bisher `settings`), „Eingetroffen um“ (bisher `timer`), „Notensystem“ (bisher `graduation-cap`)
- [x] Debug-Menü „Demo-Klassenzimmer zurücksetzen“ (bisher `floor-layout`)

## Offene Fragen

- [ ] „Leistungsarten und Bereiche“ aus den Schuleinstellungen in das Sheet „Neue Leistung“ verschieben („Arten bearbeiten …“)?

## Bugs

- [ ] Einfrieren (v. a. Einstellungen): Backtrace zeigte eine UIKit-Endlosschleife beim Push/Zurückwischen
      (Safe Area → Scroll-Beobachter → Höhe der Navigationsleiste). Minimieren der Navigationsleiste entfernt (Tab-Leiste
      minimiert weiter) – ein paar Tage beobachten. Falls es wieder hängt: App eingefroren lassen, `scripts/hang-backtrace.sh`

## Testphase per In-App-Kauf (Plan)

Bezahl-Apps können im App Store keine Testphase haben. Einziger von Apple erlaubter Weg (Richtlinie 3.1.1):
App kostenlos laden, Vollversion als In-App-Kauf, Testphase als zusätzlicher kostenloser In-App-Artikel (0 €).

**Entscheidungen** (07.10.2026)

- [x] Testphase 30 Tage
- [x] Nach Ablauf komplett gesperrt bis zum Kauf: nur Paywall und Export (Excel, PDF) erreichbar – Daten werden nie
      gelöscht, Export bleibt immer möglich (DSGVO-Auskunft)
- [x] Schulen: Angebotscodes für den In-App-Kauf (in App Store Connect erzeugen und verteilen); kein Bildungsrabatt
      über Apple mehr, nur eine App
- [x] Vollversion 4,99 € einmalig, kein Abo

**App Store Connect** (du)

- [x] In-App-Käufe angelegt (07.10.2026, Prüfung durch Apple steht aus)

- [ ] App-Preis auf kostenlos stellen
- [x] In-App-Käufe anlegen, beide „Nicht-verbrauchbar“:
      `de.devsforge.ClassBuddy.full` „ClassBuddy Vollversion“ 4,99 €,
      `de.devsforge.ClassBuddy.trial` „30 Tage kostenlos testen“ 0 € (Name muss die Dauer nennen)
- [ ] Beschreibung + Werbetext anpassen („30 Tage kostenlos testen, dann einmalig 4,99 €“)
- [ ] Schulrabatt (50 %) wieder ausschalten; Angebotscodes für Schulen unter In-App-Käufe › Angebotscodes erzeugen

**Umsetzung** (ich)

- [ ] `PurchaseStore` (StoreKit 2): Produkte laden, kaufen, `Transaction.updates` beobachten, „Käufe wiederherstellen“
      (`AppStore.sync`); Berechtigung aus `Transaction.currentEntitlements`, keine eigene Server-Logik
- [ ] Status: Testphase läuft (Tage übrig, ab Kaufdatum des Test-Artikels – übersteht Neuinstallation, gilt auf allen
      Geräten derselben Apple-ID) / Vollversion / abgelaufen / noch nicht gestartet
- [ ] Kein eigenes Sheet nach der Einführung (Popup-Müdigkeit). Stattdessen:
      - Feste erste Kachel auf der Übersicht (nicht verschieb- oder ausblendbar) mit Countdown („Noch 23 Tage“) in eigener
        Farbe; Antippen öffnet den Kauf der Vollversion. Verschwindet nach dem Kauf
      - Zeile ganz oben in den Einstellungen (über der ersten Gruppe): Titel, Untertitel, verbleibende Dauer;
        Antippen öffnet den Kauf
- [ ] Testphase startet automatisch beim ersten Start (0-€-Artikel im Hintergrund „kaufen“, kein Dialog nötig?
      Prüfen, ob StoreKit dafür trotzdem den Kauf-Dialog zeigt; sonst Start beim ersten Antippen der Kachel)
- [ ] Sicherheitsnetz: Lassen sich Produkte oder Käufe nicht laden (offline, Apple-Störung), nie sperren
- [ ] Sperre nach Ablauf: Vollbild-Paywall über der App (wie die App-Sperre), darin Kaufen, Wiederherstellen,
      Angebotscode einlösen (`offerCodeRedemption`) und „Daten exportieren“; Widget zeigt dann einen Hinweis
- [ ] Einstellungen › „ClassBuddy Vollversion“: Status, Kaufen, Wiederherstellen, Code einlösen
- [ ] StoreKit-Konfigurationsdatei für Simulator/Xcode-Tests; Unit-Tests mit `StoreKitTest` (Kauf, Ablauf, Wiederherstellen)
- [ ] Debug-Menü: Status simulieren (Testphase, abgelaufen, gekauft)
- [ ] Texte: Datenschutzerklärung (Käufe laufen über Apple, ClassBuddy erhält keine Zahlungsdaten), Support-Seite (FAQ
      „Kauf wiederherstellen“), Übersetzungen
- [ ] TestFlight: Käufe sind dort kostenlos (Sandbox) – Tester können alles durchspielen

## App-Store-Bilder

- [ ] Geräterahmen (Ton-Look) liefern: `Marketing/Frames/` (iphone, ipad, duo; Format siehe README dort)
- [ ] Roh-Screenshots aufnehmen: `scripts/appstore-screenshots.sh` (eigene Simulatoren), dann `scripts/appstore-images.sh`
- [ ] Texte prüfen: `Marketing/captions.json` (Überschriften je Seite, Kopfzeile, Suchzeile; de und en)
- [ ] Hochladen: Kopfzeile + Suchzeile (5244 × 2950), iPhone 6,1″/6,3″ und iPhone Duo (1920 × 886), iPad 13″ (1600 × 1200)

## Manuell testen (iPhone und iPad)

- [ ] iPhone Duo: komplette App durchtesten (Layout, Tab-Leiste, Übersicht, Sitzplan, Widget)

- [ ] Demo-Raum aus Sicht der Lehrkraft (Tafel und Pult unten): wird beim Start jetzt umgestellt (falls unverändert),
      sonst Debug-Menü → „Demo-Klassenzimmer zurücksetzen“
- [ ] Timer-Kachel heißt „Timer & Stoppuhr“

## Später

- [ ] Fehlzeiten-Merkliste: offen → entschuldigt / unentschuldigt, offene Fehlzeiten bleiben in den folgenden Stunden sichtbar,
      Frist (Schulvorgabe) mit Hinweis
- [ ] Checklisten ohne Schüler: einfache Klassen-Checkliste (Punkte statt Schüler, z. B. „Bücher bestellt“), Art beim Anlegen wählen
- [ ] Optional Kategorie je Beobachtung: Qualität, Quantität, Arbeitsverhalten, Sozialverhalten
- [ ] Eigener Notenschlüssel (Tabelle Prozent → Note) zusätzlich zur Abitur-Tabelle
- [ ] Selbst eingetragene Noten auch je Bereich (Modell kann es schon: `GradeScope`), bisher nur für das ganze Fach

Hinweis Schülerakte: Die App rechnet keine Noten aus (rechtlich nicht erlaubt), Einstellungen gelten je Klasse + Fach.
Skizzen für Lehrkräfte: https://claude.ai/artifact/ETRRLuZduF8Bte9q5hmjeR
