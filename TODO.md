# TODO

Stand: 07.10.2026. Alles Gebaute ist committet; getestet wird gesammelt (Liste unten).

## Icons

- [ ] Checklisten-Tab (auch Kachel, leerer Zustand, Statistik); bisher Platzhalter `check` in `AppTab.swift`
- [ ] Checklisten-Editor: Schalter „Für alle Fächer der Klasse“ (bisher `globe`, passt nicht)
- [ ] App-Einstellungen (nur iPad): „iPhone-Tab-Leiste“ (bisher Platzhalter `home-table`)
- [ ] Später: „Bewertung einstellen“, „Eingetroffen um“, „Notensystem“
- [ ] Selbst gewählt, bitte bestätigen oder ersetzen:
      Sekretariat (`bank`, `phone`, `send-mail`), Leistung anlegen (`label`, `page`, `graduation-cap`, `calendar`, `number1-circle`),
      Enddatum (`calendar`), Rückgängig (`undo`), Export-Menü (`share-ios`, `page`), „Fehlt“ (`user-xmark`),
      Schuleinstellungen „Leistungsarten und Bereiche“ (`graduation-cap`)

## Offene Fragen

- [ ] „Leistungsarten und Bereiche“ aus den Schuleinstellungen in das Sheet „Neue Leistung“ verschieben („Arten bearbeiten …“)?

## Manuell testen (iPhone und iPad)

Testdaten im Debug-Menü einmal entfernen und neu einfügen (gefüllter Sitzplan, Stunden mit Raum, gestrichelte Tische).

- [ ] Einstellungen: lange hoch und runter scrollen – friert es noch ein? (Puls-Animation entfernt, Chips ohne `ViewThatFits`;
      bei erneutem Einfrieren lldb anhängen: `device select`, `device process attach --pid`, dann `bt all`)
- [ ] Debug-Menü: Testdaten entfernen stürzt nicht mehr ab
- [ ] Übersicht: Kacheln Gruppen (Abfrage, Ergebnis, PDF, letzte Gruppen), Sekretariat (Anrufen / E-Mail nur mit Daten),
      Letztes Tafelbild (öffnet Quick Look), Checklisten (öffnet die Checkliste)
- [ ] Schuleinstellungen: Bundesland aus PLZ + Ort, Schulform-Picker, Footer-Texte, Leistungsarten und Bereiche
- [ ] Globale Statistiken: alle Karten und Diagramme, gleiche Rundung, Privatsphäre-Modus
- [ ] Tafelbild: Fach-Abfrage (Warnung bei vorhandenem Foto), Scanner an Kreide- und Whiteboard, Kacheln (aktuelles Fach zuerst,
      Kalender-Symbol), Quick Look, langes Drücken entfernt, Privatsphäre-Modus (nicht antippbar, unscharf)
- [ ] Checklisten: Anlegen mit Vorlagen (Titel + Untertitel), Enddatum (rot bei überschritten), Abhaken / Haken entfernen,
      Filter in der Leiste unten, leerer Zustand, PDF mit Icons, Duplizieren, Löschen, Excel hin und zurück
- [ ] Sitzplan: Schnell-Leiste (xmark links, Details rechts, 4 Aktionen, Rückgängig mit Icon, nach unten ziehen schließt),
      freier Tisch schließt zuerst die Leiste, gestrichelte Tische, abwesend abgeblendet, verspätet mit Uhrzeit
- [ ] Demo-Raum aus Sicht der Lehrkraft (Tafel und Pult unten)
- [ ] Bewertungen-Tab: Leiste unten (Schüler / Leistungen), Export-Menü je Fach (Notenübersicht PDF / Excel, Mitarbeitsliste)
- [ ] Schülerakte: Leiste unten (Mündlich / Leistungen / Fehlzeiten), Beobachtung anlegen (farbige Skala), bearbeiten
      („vorher …“), iPad: Notiz neben dem Datum, Fehlzeiten korrigieren, Noten je Halbjahr eintragen, PDF
- [ ] Leistungen: anlegen (mit / ohne Rohpunkte), Notenspiegel, Punkte „/ max“ mit Notenvorschlag, „fehlt“, „eintragen“ nicht abgeschnitten
- [ ] Bewertung einstellen: Skalen (7 Stufen, − o +, Daumen, Zähler, Smileys), Notensystem, ohne schriftliche Arbeiten
- [ ] iPad: App-Einstellungen → „iPhone-Tab-Leiste“ an und aus
- [ ] Datumsformat überall „06.10.26“ bzw. „06.10.26 09:12“
- [ ] Englische Sprache: neue Texte übersetzt

## Später

- [ ] Fehlzeiten-Merkliste: offen → entschuldigt / unentschuldigt, offene Fehlzeiten bleiben in den folgenden Stunden sichtbar,
      Frist (Schulvorgabe) mit Hinweis
- [ ] Checklisten ohne Schüler: einfache Klassen-Checkliste (Punkte statt Schüler, z. B. „Bücher bestellt“), Art beim Anlegen wählen
- [ ] Optional Kategorie je Beobachtung: Qualität, Quantität, Arbeitsverhalten, Sozialverhalten
- [ ] Eigener Notenschlüssel (Tabelle Prozent → Note) zusätzlich zur Abitur-Tabelle
- [ ] Selbst eingetragene Noten auch je Bereich (Modell kann es schon: `GradeScope`), bisher nur für das ganze Fach

Hinweis Schülerakte: Die App rechnet keine Noten aus (rechtlich nicht erlaubt), Einstellungen gelten je Klasse + Fach.
Skizzen für Lehrkräfte: https://claude.ai/artifact/ETRRLuZduF8Bte9q5hmjeR
