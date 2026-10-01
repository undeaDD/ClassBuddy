#!/bin/zsh
# Icons/ ist der Eingangsordner für neue SVG-Icons (Iconoir-Stil):
# Jedes SVG wird als Template-Vektorbild (24 pt) nach
# ClassBuddy/Resources/Assets.xcassets/Icons/<name>.imageset übernommen
# und danach aus Icons/ entfernt. Der Ordner selbst bleibt bestehen.
# Gleichnamige Icons im Katalog werden überschrieben.
# Im Code: Image(.name) bzw. AppSymbol.custom(.name) (Bindestriche → camelCase).
# PNG-Dateien sind farbige Illustrationen: → Assets.xcassets/Illustrations/<name>.imageset
# in Originalfarben (kein Template), ebenfalls danach aus Icons/ entfernt.
set -euo pipefail

root="${0:A:h:h}"
source_dir="$root/Icons"
catalog="$root/ClassBuddy/Resources/Assets.xcassets/Icons"
illustrations="$root/ClassBuddy/Resources/Assets.xcassets/Illustrations"

mkdir -p "$source_dir" "$catalog" "$illustrations"
touch "$source_dir/.gitkeep"
print '{"info":{"author":"xcode","version":1}}' > "$catalog/Contents.json"
print '{"info":{"author":"xcode","version":1}}' > "$illustrations/Contents.json"

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

for png in "$source_dir"/*.png; do
  name="${png:t:r}"
  set="$illustrations/$name.imageset"
  mkdir -p "$set"
  cp "$png" "$set/$name.png"
  cat > "$set/Contents.json" <<EOF
{
  "images" : [ { "filename" : "$name.png", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "original" }
}
EOF
  rm "$png"
  print "✓ $name (Illustration)"
done

# AppIcon.swift neu erzeugen: ein Fall je Icon im Katalog (Name wie Xcodes ImageResource, z. B. edit-pencil → editPencil).
generated="$root/ClassBuddy/Shared/AppIcon.swift"
{
  print '// Automatisch erzeugt von scripts/sync-icons.sh – nicht von Hand bearbeiten.'
  print ''
  print '/// Alle Icons der App. Das Bild liefert das aktive Icon-Theme (`IconManager`),'
  print '/// Fallback ist das eingebaute Iconoir-SVG aus `Assets.xcassets/Icons/<rawValue>`.'
  print 'nonisolated enum AppIcon: String, CaseIterable, Sendable {'
  for set in "$catalog"/*.imageset(N); do
    name="${set:t:r}"
    camel="${${(C)name//-/ }// /}"          # edit-pencil → EditPencil
    camel="${(L)camel[1]}${camel[2,-1]}"     # → editPencil
    case "$camel" in
      import|default|case|class|func|return|self|switch|var|let|in|is|as) camel="\`$camel\`" ;;
    esac
    print "    case $camel = \"$name\""
  done
  print '}'
} > "$generated"
print "✓ AppIcon.swift ($(grep -c '    case ' "$generated") Icons)"
