#!/bin/zsh
# Roh-Screenshots mit Testdaten für die App-Store-Bilder (Mockups, siehe scripts/appstore-images.sh):
#   iPhone 6,3"  → iPhone 17
#   iPad 13"     → iPad Pro 13-inch (M5)
#   iPhone Duo   → iPhone Duo
# Ergebnis: build/AppStore/raw/<sprache>/<iphone|ipad|duo>/<seite>.png (hell) und <seite>-dark.png (dunkel)
#
#   scripts/appstore-screenshots.sh
#   LANGUAGES="de en" scripts/appstore-screenshots.sh       (Standard: nur Deutsch)
#   APPEARANCES="light" scripts/appstore-screenshots.sh     (Standard: hell und dunkel)
#
# - Eigene Simulatoren „ClassBuddy Store …“ (werden beim ersten Mal angelegt) – nie deine eigenen.
#   Sie werden gebootet und danach wieder heruntergefahren.
# - App wird jeweils neu installiert (leere Daten) und startet mit `-screenshots` → Testdaten, erste Testklasse.
# - Statusleiste 9:41, voller Akku, volles Netz.
set -euo pipefail
cd "${0:A:h:h}"

bundle="de.devsforge.ClassBuddy"
appearances=(${=APPEARANCES:-light dark})
languages=(${=LANGUAGES:-de})
# Alle Seiten, die in Marketing/captions.json vorkommen.
tabs=(dashboard calendar notes rooms checklists students)
# Anzeigename:Gerätetyp:Ordner
devices=(
  "ClassBuddy Store iPhone:com.apple.CoreSimulator.SimDeviceType.iPhone-17:iphone"
  "ClassBuddy Store iPad:com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB:ipad"
  "ClassBuddy Store iPhone Duo:com.apple.CoreSimulator.SimDeviceType.iPhone-Duo:duo"
)

print "▸ Build (Debug, Simulator) …"
xcodebuild build -quiet \
  -project ClassBuddy.xcodeproj -scheme ClassBuddy \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath build/Screenshots
app="build/Screenshots/Build/Products/Debug-iphonesimulator/ClassBuddy.app"
# Ohne App-Sperre und ohne „Neu in ClassBuddy“ (gilt als gesehen für die gebaute Version).
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Info.plist")"

for entry in $devices; do
  IFS=: read -r name type folder <<< "$entry"
  udid="$(xcrun simctl list devices available | grep -m1 -F "    $name (" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)"
  if [[ -z "$udid" ]]; then
    print "▸ Simulator „$name“ anlegen …"
    udid="$(xcrun simctl create "$name" "$type")"
  fi

  print "▸ $name …"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3

  for language in $languages; do
    xcrun simctl uninstall "$udid" "$bundle" 2>/dev/null || true
    xcrun simctl install "$udid" "$app"
    output="build/AppStore/raw/$language/$folder"
    rm -rf "$output" && mkdir -p "$output"
    for appearance in $appearances; do
    suffix=""
    [[ $appearance == dark ]] && suffix="-dark"
    for tab in $tabs; do
      file="$output/$tab$suffix.png"
      xcrun simctl launch --terminate-running-process "$udid" "$bundle" \
        -screenshots -tab "$tab" -app.appearance "$appearance" -onboarding.completed YES \
        -security.appLockEnabled NO -whatsNew.lastSeenVersion "$version" \
        -app.language "$language" -AppleLanguages "($language)" -AppleLocale "${language}_DE" >/dev/null
      # Übersicht: Wetter braucht etwas länger (Apple bzw. Open-Meteo).
      wait=6
      [[ $tab == dashboard ]] && wait=15
      sleep $wait
      xcrun simctl io "$udid" screenshot --type=png "$file" >/dev/null
      print "  ✓ $file"
    done
    done
  done

  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  xcrun simctl status_bar "$udid" clear
  xcrun simctl shutdown "$udid"
done

print "✓ Roh-Screenshots in build/AppStore/raw/ – weiter mit scripts/appstore-images.sh"
