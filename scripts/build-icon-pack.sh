#!/bin/zsh
# Baut ein Icon-Paket für ClassBuddy (App-Einstellungen → Icons → Paket installieren).
#
#   scripts/build-icon-pack.sh IconPacks/<Ordner>
#
# Der Ordner enthält manifest.json (id, name, author, version, license, url) und je Icon
# eine SVG mit dem Namen des Icons, z. B. calendar.svg, edit-pencil.svg (alle Namen: AppIcon.swift).
# Fehlende Icons zeigt die App im eingebauten Iconoir-Stil. Farbe: currentColor bzw. Schwarz,
# Transparenz (z. B. Duotone) bleibt erhalten – die App färbt in der Akzent-/Textfarbe.
#
# Ergebnis: build/IconPacks/<id>.zip (manifest.json + <name>.pdf). Braucht rsvg-convert (brew install librsvg).
set -euo pipefail

root="${0:A:h:h}"
source_dir="${1:?Ordner angeben, z. B. IconPacks/FontAwesome}"
source_dir="${source_dir:A}"
manifest="$source_dir/manifest.json"
[[ -f "$manifest" ]] || { print -u2 "✗ $manifest fehlt"; exit 1; }
command -v rsvg-convert >/dev/null || { print -u2 "✗ rsvg-convert fehlt (brew install librsvg)"; exit 1; }

id=$(plutil -extract id raw -o - "$manifest")
[[ "$id" =~ '^[a-z0-9][a-z0-9-]*$' ]] || { print -u2 "✗ id nur aus a-z, 0-9 und -"; exit 1; }
known=(${(f)"$(grep -oE '= "[^"]+"' "$root/ClassBuddy/Shared/AppIcon.swift" | sed 's/= "//; s/"$//')"})

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$manifest" "$work/manifest.json"

count=0
setopt null_glob
for svg in "$source_dir"/*.svg; do
  name="${svg:t:r}"
  if (( ! ${known[(Ie)$name]} )); then
    print -u2 "⚠ $name.svg übersprungen – kein Icon dieses Namens"
    continue
  fi
  rsvg-convert -f pdf -o "$work/$name.pdf" "$svg"
  count=$((count + 1))
done
(( count > 0 )) || { print -u2 "✗ keine passenden SVGs gefunden"; exit 1; }

mkdir -p "$root/build/IconPacks"
output="$root/build/IconPacks/$id.zip"
rm -f "$output"
(cd "$work" && zip -q -X "$output" manifest.json *.pdf)
print "✓ $output ($count von ${#known} Icons)"
