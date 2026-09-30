#!/bin/zsh
# Führt die Unit-Tests aus (headless auf einem iPad-Simulator, kein Simulator-Fenster).
# Aufruf: scripts/test.sh   ·   anderes Gerät: SIMULATOR_UDID=<udid> scripts/test.sh
set -euo pipefail
cd "${0:A:h:h}"

# Erster verfügbarer iPad-Simulator (per UDID – Namen enthalten Klammern wie „(M5)“).
line="$(xcrun simctl list devices available | grep -m1 -E '^[[:space:]]+iPad' || true)"
udid="${SIMULATOR_UDID:-$(print -r -- "$line" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)}"
if [[ -z "$udid" ]]; then
  print -u2 "✗ Kein iPad-Simulator gefunden (Xcode → Settings → Components)."
  exit 1
fi

# Name zur tatsächlich verwendeten UDID (auch bei SIMULATOR_UDID).
line="$(xcrun simctl list devices available | grep -m1 -F "$udid" || true)"
name="$(print -r -- "$line" | sed -E 's/^[[:space:]]+//; s/ \([0-9A-F-]{36}\).*//')"
print "▸ Tests auf $name …"
log="$(mktemp -t classbuddy-tests)"
if xcodebuild test \
    -project ClassBuddy.xcodeproj \
    -scheme ClassBuddy \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath build/TestData \
    -quiet >"$log" 2>&1; then
  grep -E "Test run with|passed after" "$log" | tail -1 || true
  print "✓ Alle Tests bestanden"
else
  grep -E "error:|✘|failed|Failing tests" "$log" | head -40
  print -u2 "✗ Tests fehlgeschlagen (vollständiges Log: $log)"
  exit 1
fi
