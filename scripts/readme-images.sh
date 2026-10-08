#!/bin/zsh
# README-Bilder aus den App-Store-Bildern: verkleinerte JPEGs (hell und dunkel) nach docs/screenshots/.
#
#   scripts/readme-images.sh
#
# Vorher: scripts/appstore-screenshots.sh und scripts/appstore-images.sh (Ausgabe in build/AppStore/de[-dark]/).
set -euo pipefail
cd "${0:A:h:h}"

typeset -A widths=(ipad 750 iphone 600)
for device width in "${(@kv)widths}"; do
  mkdir -p "docs/screenshots/$device"
  for variant in de de-dark; do
    suffix=${variant#de}
    for source in build/AppStore/$variant/$device/*.png(N); do
      target="docs/screenshots/$device/${source:t:r}$suffix.jpg"
      sips -s format jpeg -s formatOptions 80 --resampleWidth "$width" "$source" --out "$target" >/dev/null
    done
  done
done
du -sh docs/screenshots
print "✓ README-Bilder in docs/screenshots/"
