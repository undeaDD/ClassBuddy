# TODO: Notizen

Der Tab „Notizen“ (nach „Räume“) und die Wege dorthin stehen schon als Platzhalter:
Schülerliste (Tab oder „Schüler“) → Fächer des Schülers → leere Notizen-Ansicht.
Im Sitzplan führt das Antippen eines Schülers direkt zu Schüler + Fach der Stunde.

Ziel: Pro Schüler und Fach schnell festhalten, was im Unterricht auffällt, als Grundlage für mündliche Noten,
Zeugnisbemerkungen und Elterngespräche.

## Offene Fragen (vor dem Bauen klären)

- [ ] Welche Notiz-Arten gibt es fest, welche sind frei? (Vorschläge unten)
- [ ] Bewertungsskala für Mitarbeit: + / o / −, 1–6, Punkte (Oberstufe) oder frei wählbar je Klasse?
- [ ] Was passiert mit dem bisherigen Freitext `Student.notes` (Schüler-Editor)? Bleibt „Allgemein“ oder wird übernommen
- [ ] Icons: Fächer-Zeilen (Fächerliste), Notiz-Arten, Schnell-Buttons
- [ ] Gehört eine Notiz zu einer Stunde (Datum + Stunde) oder nur zu einem Datum?

## Modell

- [ ] `StudentNote` (SwiftData): Schüler, Fach, Datum, Art, Bewertung (optional), Text (optional), Stunde (optional)
- [ ] Löschregeln: mit dem Schüler löschen; entfernte Fächer der Klasse → Notizen bleiben unter „Frühere Fächer“
- [ ] Alles gilt als sensibel (`.sensitive()`), im Privatsphäre-Modus geschwärzt und nur lesend

## Notizen-Ansicht (Schüler + Fach)

- [ ] Zeitleiste der Notizen, neueste oben, nach Datum gruppiert; Wischen zum Bearbeiten und Löschen
- [ ] Filter nach Art (z. B. nur Mitarbeit)
- [ ] Kopf mit Zusammenfassung: Anzahl je Art, Mitarbeit-Tendenz der letzten Wochen (kleines Diagramm)
- [ ] Neue Notiz: Art wählen, optional Bewertung und Text; Datum/Stunde vorausgefüllt

## Schnell erfassen (Unterricht)

- [ ] Im Sitzplan: Schüler antippen → kompakte Schnell-Leiste statt ganzer Ansicht
      (Mitarbeit +/−, Hausaufgaben fehlen, Material fehlt, Notiz …), ein Tipp speichert, Toast mit „Rückgängig“
- [ ] Mehrere Schüler nacheinander erfassen, ohne die Ansicht zu verlassen
- [ ] Stunde und Fach automatisch aus dem Kalender (laufende Stunde)

## Vorschläge für Notiz-Arten

- Mitarbeit (Bewertung)
- Hausaufgaben vergessen
- Material vergessen
- Verhalten (positiv / negativ)
- Mündliche Leistung / Abfrage (Bewertung)
- Förderbedarf / Beobachtung
- Freitext

## Auswertung und Weitergabe

- [ ] Übersicht je Klasse und Fach: Tabelle Schüler × Arten (z. B. „HA vergessen: 3“)
- [ ] Zusammenfassung je Schüler als PDF (Quick Look wie beim Sitzplan) für Elterngespräche
- [ ] Übersichtskarte „Heute notiert“ bzw. „Notizen dieser Woche“

## Daten

- [ ] Excel-Export und -Import: Blatt „Notizen“ (ID, Schüler-ID, Fach, Datum, Art, Bewertung, Text)
- [ ] Tests: Modell und Löschregeln, Zusammenfassung, Excel hin und zurück

## Optional

- [ ] Suche über alle Notizen einer Klasse
- [ ] Textbausteine für häufige Bemerkungen
- [ ] Erinnerung: Schüler ohne Notiz seit X Wochen

## Bewusst nicht geplant

- Notenberechnung bzw. Notenbuch (eigenes Thema)
- Teilen mit anderen Lehrkräften oder Cloud-Sync
- Anhänge (Fotos von Arbeiten)

## Qualität

- [ ] Auf iPhone und iPad testen (Sitzplan: Antippen, Ziehen, Seitenleiste, PDF in Quick Look; Notizen-Tab)
- [ ] SwiftLint 0/0, Semgrep 0, alle Tests grün
