#!/bin/zsh
# Icons/ ist der Eingangsordner für neue SVG-Icons (Iconoir-Stil):
# Jedes SVG wird als Template-Vektorbild (24 pt) nach
# ClassBuddy/Resources/Assets.xcassets/Icons/<name>.imageset übernommen
# und danach aus Icons/ entfernt. Der Ordner selbst bleibt bestehen.
# Gleichnamige Icons im Katalog werden überschrieben.
# Im Code: Image(.name) bzw. AppSymbol.custom(.name) (Bindestriche → camelCase).
set -euo pipefail

root="${0:A:h:h}"
source_dir="$root/Icons"
catalog="$root/ClassBuddy/Resources/Assets.xcassets/Icons"

mkdir -p "$source_dir" "$catalog"
touch "$source_dir/.gitkeep"
print '{"info":{"author":"xcode","version":1}}' > "$catalog/Contents.json"

setopt null_glob # leerer Ordner → keine Schleifendurchläufe
for svg in "$source_dir"/*.svg; do
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
  rm "$svg"
  print "✓ $name"
done
