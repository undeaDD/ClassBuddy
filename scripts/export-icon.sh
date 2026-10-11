#!/bin/zsh
# Rendert das App-Icon (Icon Composer) für README/Docs: docs/app-icon.png + docs/app-icon-dark.png
set -euo pipefail
cd "${0:A:h:h}"
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
for rendition in Default Dark; do
  out="docs/app-icon.png"; [[ $rendition == Dark ]] && out="docs/app-icon-dark.png"
  "$ictool" ClassBuddy/Resources/ClassBuddy.icon --export-image --output-file "$out" \
    --platform iOS --rendition "$rendition" --width 512 --height 512 --scale 1 >/dev/null
  print "✓ $out"
done
