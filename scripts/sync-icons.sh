#!/bin/zsh
# Übernimmt alle SVGs aus Icons/ als Template-Vektorbilder (24 pt) nach
# ClassBuddy/Resources/Assets.xcassets/Icons/<name>.imageset.
# Icons/ bleibt die Quelle – einfach neue SVGs dort ablegen und das Skript ausführen.
# Im Code: Image(.name) bzw. AppSymbol.custom(.name) (Bindestriche → camelCase).
set -euo pipefail

root="${0:A:h:h}"
source_dir="$root/Icons"
catalog="$root/ClassBuddy/Resources/Assets.xcassets/Icons"

mkdir -p "$catalog"
print '{"info":{"author":"xcode","version":1}}' > "$catalog/Contents.json"

for svg in "$source_dir"/*.svg(N); do
  name="${svg:t:r}"
  set="$catalog/$name.imageset"
  mkdir -p "$set"
  # Einheitliche Grundgröße 24 pt (viewBox bleibt unverändert)
  sed -E 's/width="[0-9.]+(px)?" height="[0-9.]+(px)?"/width="24px" height="24px"/' "$svg" > "$set/$name.svg"
  cat > "$set/Contents.json" <<EOF
{
  "images" : [ { "filename" : "$name.svg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
EOF
  print "✓ $name"
done
