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

## Manuell testen (iPhone und iPad)

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
