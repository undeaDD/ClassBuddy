# TODO

Stand: 29.10.2026. Getestet wird gesammelt (Liste unten).

## Icons

Vorschläge (Iconoir für den eingebauten Satz / Font Awesome Duotone fürs Paket), Dateien lädt der Nutzer:

- [ ] „Bewertung einstellen“ (bisher `settings`): `star` / `star-half-stroke`
- [ ] „Eingetroffen um“ (bisher `timer`): `log-in` / `door-open`
- [ ] „Notensystem“ (bisher `graduation-cap`): `numbered-list` / `list-ol`
- [ ] Kaufseite und Testphasen-Kachel (bisher SF Symbols): Testphase `hourglass` / `hourglass-half`,
      Vollversion `badge-check` / `badge-check`
- [ ] „Daten & Sync“ (bisher SF Symbols): Einstellungen-Zeile `arrow.triangle.2.circlepath`, „Gerät koppeln“ `qrcode`,
      gekoppeltes Gerät `ipad.and.iphone`

## Sync und Teilen (geplant)

Entscheidungen (29.10.2026): nur Vollversion (nach Ablauf der Testphase gesperrt wie der Export).
Sync (eigene Geräte) führt Einträge einzeln zusammen (`updatedAt` + Lösch-Markierungen), nichts geht verloren:
lokal per Kopplung (QR-Code, Network.framework mit Bonjour + TLS, kein Server) und Button „Jetzt synchronisieren“;
iCloud per `CKSyncEngine` in der privaten Datenbank, sensible Felder in `encryptedValues` (Ende-zu-Ende), Opt-in, läuft
automatisch. Kein SwiftData-CloudKit-Spiegeln (keine Kontrolle über Verschlüsselung und Konflikte).
Teilen (Kollegen): Gesamtpaket (Daten, Dateien, optional Einstellungen) an ein Gerät in der Nähe oder als Datei per
AirDrop/Mail; der Empfänger bestätigt und alle seine lokalen Daten werden ersetzt. Kein CKShare, keine Rechteverwaltung.
Eigener Cloud-Ordner (Google Drive, Nextcloud, OneDrive, Dropbox, iCloud Drive …): Ordner über die Dateien-App wählen
(File Provider, Lesezeichen), keine Anbieter-SDKs und kein OAuth. Jedes Gerät schreibt nur eigene Änderungsdateien,
verschlüsselt (CryptoKit, Schlüssel aus dem Daten-Passwort, siehe unten), der Anbieter sieht nichts Lesbares. Sync beim Öffnen der App und per
„Jetzt synchronisieren“ (kein Hintergrund-Sync).
Version: Sync und Teilen nur bei gleicher App-Version + Build. Lokal per Handschlag geprüft; iCloud und Cloud-Ordner tragen
die Version des neuesten Geräts, Geräte mit anderer Version pausieren mit Hinweis „ClassBuddy auf allen Geräten
aktualisieren“; Paket-Dateien mit anderer Version werden abgelehnt.

Umgesetzt (02./03.11.2026): `lastModified` an allen Modellen + `DeletedRecord` (`SyncTracking`), Sync-Kern
(`SyncEngine`, `SyncPayloads*`: Manifest-Austausch, Pakete, neuerer Stand gewinnt), lokaler Sync (`LocalSync.swift`:
QR-Kopplung, Bonjour + TLS mit gemeinsamem Schlüssel, „Jetzt synchronisieren“), Seite „Daten & Sync“ mit Export & Import.

- [ ] Einstellungen (UserDefaults: Schule, Schultag, Pausen, Profil …) mit abgleichen (eigener Eintrag mit Zeitstempel)
- [ ] Teilen an Kollegen: Gesamtpaket an ein Gerät in der Nähe oder als Datei (AirDrop/Mail), Empfänger ersetzt alles
- [ ] iCloud: `CKSyncEngine`, Dateien als `CKAsset`, Einstellungen als eigener Eintrag
- [ ] Cloud-Ordner: Ordnerwahl, verschlüsselte Änderungsdateien je Gerät, Zusammenführen beim Öffnen
- [ ] „Daten & Sync“ ergänzen: iCloud, Cloud-Ordner, Teilen
- [ ] Ein Daten-Passwort für Excel-Backup und Sync: sicheres Textfeld auf „Daten & Sync“ (Auge zum Anzeigen, Kopieren,
      Neu erzeugen), im Schlüsselbund gespeichert. Beim ersten Start zufällig erzeugt (gut lesbar, z. B. 4 × 5 Zeichen),
      jederzeit änderbar. Lokale Kopplung übernimmt das Passwort des anderen Geräts; Cloud-Ordner mit anderem Passwort →
      Hinweis „Passwort muss auf allen Geräten gleich sein“; Ändern verschlüsselt den Cloud-Ordner neu, alte Backups
      brauchen weiter das alte Passwort (Hinweis beim Ändern). Export zeigt das Passwort mit Hinweis „notieren“
- [ ] Excel-Verschlüsselung mit dem Daten-Passwort: echte Excel-Verschlüsselung (ECMA-376 Agile, AES-256 + SHA-512,
      Container als Compound File), Datei öffnet in Excel/Numbers/LibreOffice nur mit Passwort; eigener Code wie
      `XLSX.swift` und `ZipArchive.swift`, CommonCrypto für AES-CBC, keine Bibliothek. Import probiert das gespeicherte
      Passwort und fragt nur nach, wenn es nicht passt. Teilen an Kollegen nutzt es nicht
- [ ] Texte: `privacy.html` + `.en` (Auf einen Blick, gespeicherte Daten, Internet-Verbindungen, Zugriffsrechte lokales
      Netzwerk, Hinweise für Lehrkräfte: Wahl des Cloud-Anbieters und Weitergabe an Kollegen liegt bei der Lehrkraft),
      `site/` (Startseite, Support), README und FEATURES („kein Cloud-Sync“); `licenses.html` nur bei neuer Fremd-Bibliothek
      (bisher keine geplant)

## Anleitung

Umgesetzt (29.10.2026): `guide.html` + `guide.en.html` (Rechtstexte-Ordner), Einstellungen › Aktionen › „Anleitung“.

## Website (GitHub Pages)

Startseite wird erzeugt: `python3 scripts/landing-page.py` → `site/index.html` + `index.en.html` (alle Texte de/en im
Skript), Aussehen `site/landing.css`, Verhalten `site/landing.js` (Hell/Dunkel, Sprachmenü, Bilder, Fragen).
Geräte-Bilder: `WEB=1 scripts/appstore-images.sh` → `site/screenshots/`. Workflow kopiert alles mit.

- [ ] Store-Links: `APP_STORE_URL` und `PLAY_URL` im Skript setzen, sobald die Apps veröffentlicht sind, dann Skript
      ausführen (bis dahin springen die Buttons zum Download-Abschnitt)
- [ ] Stimmen: `REVIEWS` im Skript füllen (nur echte Zitate mit Erlaubnis); leere Einträge sind Platzhalter
- [ ] Englische Seite zeigt noch deutsche Screenshots (englische Roh-Screenshots aufnehmen, dann
      `LANGUAGES="de en" WEB=1 scripts/appstore-images.sh` und im Skript `screenshots/de` je Sprache wählen)

## Manuell testen (iPhone und iPad)

- [ ] iPhone Duo: komplette App durchtesten (Layout, Tab-Leiste, Übersicht, Sitzplan, Widget)
- [ ] Foto auswählen öffnet ein Menü „Aus „Fotos““ / „Aus „Dateien““, beide führen zum Ausschnitt
- [ ] Schüler-Detailseite: Bearbeiten-Knopf oben rechts (im Privatsphäre-Modus gesperrt, schließt sich beim Einschalten)
- [ ] Schülerliste: schwebende Leiste unten (Filter-Symbol und gewählte Sortierung), Menü Vorname / Nachname / Geschlecht / Geburtstag
      (Abschnitte: Buchstaben, Geschlechter, Monate), Wahl bleibt nach Neustart; Index rechts passt; iPad und iPhone
- [ ] Mein Profil › Foto (Fotos oder Dateien, Ausschnitt wie bei Schülern); Sitzplan zeigt das Foto am Lehrerpult
      (unscharf im Privatsphäre-Modus), darunter den Namen aus dem Profil; auch im Sitzplan-PDF
- [ ] Sitzplan › Schüler antippen: großes Foto mittig zwischen „Schließen“ und „Details“, Name darunter (iPhone, iPad)

- [ ] Sitzplan › Schüler antippen, Skala 7 Stufen auf dem iPhone: „− − −“ bis „+ + +“ stehen übereinander, Knöpfe
      etwas höher und gleich hoch; auf dem iPad nebeneinander; ebenso in „Neue Beobachtung“

- [ ] Lokaler Sync (iPhone + iPad, gleiches WLAN, beide mit diesem Build): Einstellungen › Daten & Sync › Gerät koppeln,
      ein Gerät „Code zeigen“, das andere „Code scannen“ → Abfrage „Lokales Netzwerk“ erlauben, erster Abgleich läuft
      sofort (Meldung mit Anzahl neu/aktualisiert/gelöscht). Danach: etwas ändern, löschen, neu anlegen, auf dem anderen
      Gerät „Jetzt synchronisieren“; Fotos, Tafelbilder, Dokument-Kacheln kommen mit; Kopplung entfernen
- [ ] „Export & Import“ liegt jetzt unter Daten & Sync (App-Einstellungen ohne), funktioniert wie vorher

- [ ] Bewertung: Schuleinstellungen › Bewertungen › „Skala und Noten“ je Stufe der Schulform (Vorgabe wiederherstellen);
      Klasse bearbeiten › „Eigene Bewertung“; Schülerakte-Menü ohne „Bewertung einstellen“, ohne Skala-Fußzeile.
      Nach dem Update: Klassen mit anderer genutzter Skala haben sie als eigene Bewertung (Testerdaten!); auch nach Import
- [ ] Neue Beobachtung: „Weitere anlegen“ (Notiz wird geleert, Art/Wert/Datum bleiben) und „Zuletzt angelegt“
- [ ] Verlauf: Schüler › Fächer zeigen kleinen Verlauf der letzten 20 Bewertungen, Fach-Seite großen Verlauf über den
      Kacheln; alle Skalen (7 Stufen, − o +, Daumen, Smileys auf einer Achse), „+1“ als Balken je Tag; unscharf im
      Privatsphäre-Modus

## Später

- [ ] Fehlzeiten-Merkliste: offen → entschuldigt / unentschuldigt, offene Fehlzeiten bleiben in den folgenden Stunden sichtbar,
      Frist (Schulvorgabe) mit Hinweis
- [ ] Checklisten ohne Schüler: einfache Klassen-Checkliste (Punkte statt Schüler, z. B. „Bücher bestellt“), Art beim Anlegen wählen
- [ ] Optional Kategorie je Beobachtung: Qualität, Quantität, Arbeitsverhalten, Sozialverhalten
- [ ] Eigener Notenschlüssel (Tabelle Prozent → Note) zusätzlich zur Abitur-Tabelle
- [ ] Selbst eingetragene Noten auch je Bereich (Modell kann es schon: `GradeScope`), bisher nur für das ganze Fach

Hinweis Schülerakte: Die App rechnet keine Noten aus (rechtlich nicht erlaubt), Einstellungen gelten je Klasse + Fach.
Skizzen für Lehrkräfte: https://claude.ai/artifact/ETRRLuZduF8Bte9q5hmjeR

### Widgets: Übersichts-Kacheln als Widget

Entscheidungen (11.10.2026): ein konfigurierbares Widget „ClassBuddy-Kachel“ (Kachel-Art und Klasse wählbar) neben
„Jetzt & Als Nächstes“. Klasse „Automatisch“: Klasse der laufenden, sonst der nächsten Stunde heute, sonst die zuletzt
gewählte. Widgets bekommen nur das Nötigste als Snapshot (App Group, kein SwiftData). Zahlen sind unkritisch; nur Kacheln
mit Namen oder freiem Text werden auf dem Sperrbildschirm ausgeblendet (`privacySensitive`). Werkzeuge (Zufallsauswahl,
Gruppen, Dokumente, Websites …) öffnen per Antippen die App direkt in der passenden Ansicht (URL-Schema nötig).
Wetter: letzter Wert aus der App (noch offen, ob das Widget selbst abfragen soll). Nicht als Widget: Timer, Lautstärke,
Buddy, Feedback.

### Windrosen-Gruppen (Entwurf)

Idee: Jeder Schüler bekommt vier feste Partner (Nord, Ost, Süd, West), alle verschieden, für schnelle Partnerarbeit
(„Geht zu eurem Ost-Partner“). Erzeugung je Klasse wie bei den Zufallsgruppen, Ergebnis gespeichert.
Noch offen: Partner oder Vierergruppen? Zufällig oder mit Blick auf den Sitzplan? Kachel, eigene Seite oder beides?
Druckbare Karten je Schüler? Ungerade Schülerzahl: Dreiergruppe oder Lehrkraft wählt?
