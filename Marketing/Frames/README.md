# Geräterahmen für die App-Store-Bilder

Je Gerät eine JSON-Datei (im Repo) mit dem Bildschirmbereich im Rahmenbild, in Pixeln, Ursprung oben links.
Die genaue Form des Displays (Ecken) liest das Skript aus der Transparenz des Bezels und schneidet den Screenshot danach zu.

```json
{ "image": "iphone.png", "screen": [x, y, breite, höhe] }
```

Die Rahmenbilder selbst liegen in `Marketing/Assets/` (nicht im Repo, Apple-Lizenz):

| JSON | Bild | Quelle |
|---|---|---|
| `iphone.json` | `iphone.png` | Apple Product Bezels: iPhone 17, Portrait |
| `ipad.json` | `ipad.png` | Apple Product Bezels: iPad Pro (M5) 13″, Portrait |
| `duo.json` | `duo.png` | Apple Product Bezels: iPhone Duo, Outer Closed Portrait |
| `duo-open.json` | `duo-open.png` | Apple Product Bezels: iPhone Duo, Inner Open Landscape |

Ebenfalls in `Marketing/Assets/`: `chalkboard.jpg` (Hintergrund) und `chalk.ttf` (Schrift).
Fehlt etwas, nutzt `scripts/marketing/compose.swift` einen gezeichneten Rahmen, einen Verlauf bzw. die Systemschrift.
