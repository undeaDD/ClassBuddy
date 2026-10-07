#!/bin/zsh
# Testabdeckung: führt alle Tests mit Code Coverage aus und meldet
#   • Logik – Dateien ohne SwiftUI-Views (Modelle, Import/Export, Berechnungen, Sicherheit …) – Ziel ≥ 80 %
#   • Gesamt – inklusive Views (die per Unit-Test kaum sinnvoll prüfbar sind)
#
#   scripts/coverage.sh                 (Simulator: iPad Pro 11-inch, siehe SIMULATOR_UDID)
#   scripts/coverage.sh <xcresult>      (nur auswerten, ohne Testlauf)
#
# Der Logik-Wert steht als Badge in der README (von Hand nachziehen) und als „über 80 %“ in der Datenschutzerklärung.
set -euo pipefail
cd "${0:A:h:h}"

result="${1:-}"
if [[ -z "$result" ]]; then
  udid="${SIMULATOR_UDID:-DE7796FE-608A-4D03-9E7B-A28973F54D76}"
  result="build/TestData/coverage-$(date +%Y%m%d-%H%M%S).xcresult"
  print "▸ Tests mit Coverage …"
  xcodebuild test -project ClassBuddy.xcodeproj -scheme ClassBuddy \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/TestData \
    -collect-test-diagnostics never -enableCodeCoverage YES -resultBundlePath "$result" -quiet >/dev/null
fi

xcrun xccov view --report --json "$result" | python3 -c '
import json, os, sys
report = json.load(sys.stdin)
app = next(t for t in report["targets"] if t["name"] == "ClassBuddy.app")
totals = {"logic": [0, 0], "ui": [0, 0]}
for f in app["files"]:
    source = open(f["path"]).read() if os.path.exists(f["path"]) else ""
    kind = "ui" if ("var body: some View" in source or "func body(content" in source) else "logic"
    totals[kind][0] += f["coveredLines"]
    totals[kind][1] += f["executableLines"]
def pct(c, t): return 100 * c / t if t else 0
logic, ui = totals["logic"], totals["ui"]
print(f"Logik:  {pct(*logic):.1f} %  ({logic[0]}/{logic[1]} Zeilen)")
print(f"Views:  {pct(*ui):.1f} %  ({ui[0]}/{ui[1]} Zeilen)")
print(f"Gesamt: {pct(logic[0] + ui[0], logic[1] + ui[1]):.1f} %")
'
