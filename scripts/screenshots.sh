#!/bin/zsh
# README-Screenshots mit Testdaten: docs/screenshots/<ipad|iphone>/<seite>.png
# Manuell starten: scripts/screenshots.sh
# - Nutzt eigene Simulatoren (nicht deinen laufenden), bootet sie bei Bedarf und fährt sie danach wieder herunter.
# - App wird neu installiert (leere Daten), startet mit `-screenshots` → Testdaten + erste Testklasse.
# - Andere Geräte: DEVICES="iPad Pro 11-inch (M5):ipad" scripts/screenshots.sh
# - Dunkel: APPEARANCE=dark scripts/screenshots.sh
set -euo pipefail
cd "${0:A:h:h}"

bundle="de.devsforge.ClassBuddy"
appearance="${APPEARANCE:-light}"
tabs=(dashboard calendar students settings)
devices=("${(@s:;:)${DEVICES:-iPad Air 13-inch (M4):ipad;iPhone 17:iphone}}")

print "▸ Build (Debug, Simulator) …"
xcodebuild build -quiet \
  -project ClassBuddy.xcodeproj -scheme ClassBuddy \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath build/Screenshots
app="build/Screenshots/Build/Products/Debug-iphonesimulator/ClassBuddy.app"
# Ohne App-Sperre und ohne „Neu in ClassBuddy“ (gilt als gesehen für die gebaute Version).
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Info.plist")"

for entry in $devices; do
  name="${entry%%:*}"
  folder="${entry##*:}"
  line="$(xcrun simctl list devices available | grep -m1 -F "    $name (" || true)"
  udid="$(print -r -- "$line" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)"
  if [[ -z "$udid" ]]; then
    print -u2 "✗ Simulator nicht gefunden: $name"
    exit 1
  fi
  was_booted=no
  [[ "$line" == *"(Booted)"* ]] && was_booted=yes

  print "▸ $name …"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl uninstall "$udid" "$bundle" 2>/dev/null || true
  xcrun simctl install "$udid" "$app"
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3

  mkdir -p "docs/screenshots/$folder"
  for tab in $tabs; do
    xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
      -screenshots -tab "$tab" -app.appearance "$appearance" -onboarding.completed YES \
        -security.appLockEnabled NO -whatsNew.lastSeenVersion "$version" >/dev/null
    sleep 5
    xcrun simctl io "$udid" screenshot --type=png "docs/screenshots/$folder/$tab.png" >/dev/null
    print "  ✓ $folder/$tab.png"
  done

  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  xcrun simctl status_bar "$udid" clear
  [[ "$was_booted" == no ]] && xcrun simctl shutdown "$udid"
done
print "✓ Screenshots in docs/screenshots/"
