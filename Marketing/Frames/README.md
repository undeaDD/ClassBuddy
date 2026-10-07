# Geräterahmen für die App-Store-Bilder

Optional. Ohne Dateien zeichnet `scripts/marketing/compose.swift` einen schlichten Ton-Rahmen.

Je Gerät zwei Dateien (`iphone`, `ipad`, `duo`):

- `<gerät>.png`: Rahmen mit **transparentem** Bildschirmbereich (Ton-Look, Schatten gern schon enthalten)
- `<gerät>.json`: wo im Rahmenbild der Bildschirm liegt, in Pixeln, Ursprung oben links

```json
{ "screen": [x, y, breite, höhe], "cornerRadius": 120 }
```

Der Screenshot wird auf die Bildschirmgröße skaliert, mit `cornerRadius` abgerundet und unter den Rahmen gelegt.
Danach `scripts/appstore-images.sh` erneut ausführen.
