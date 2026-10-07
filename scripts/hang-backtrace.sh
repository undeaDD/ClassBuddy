#!/bin/zsh
# Backtraces aller Threads einer hängenden ClassBuddy-App auf einem Gerät (WLAN reicht).
# App eingefroren lassen (nicht beenden), dann:
#
#   scripts/hang-backtrace.sh [Geräte-UDID]     (Standard: iPad UndeaD_Pad)
#
# Hängt sich an (über WLAN ca. 30 s), schreibt `bt all` nach build/hang-<Zeit>.txt und löst sich wieder (App läuft weiter).
# Zweimal im Abstand von ein paar Sekunden ausführen: gleicher Stack auf dem Main-Thread = echte Endlosschleife.
set -euo pipefail

root="${0:A:h:h}"
device="${1:-00008122-0019598E0223801C}"
mkdir -p "$root/build"
output="$root/build/hang-$(date +%H%M%S).txt"

pid=$(xcrun lldb -b -o "device select $device" -o "device process list" 2>/dev/null \
  | awk '$NF == "ClassBuddy" { print $1; exit }')
[[ -n "$pid" ]] || { print -u2 "✗ ClassBuddy läuft nicht auf $device"; exit 1; }

# Warten, Stacks ausgeben und Lösen übernimmt hang_backtrace.py (über WLAN lädt lldb die Symbole erst nach Sekunden).
lldb_script="$root/build/hang-backtrace.lldb"
cat > "$lldb_script" <<LLDB
device select $device
script lldb.debugger.SetAsync(False)
device process attach --pid $pid
command script import $root/scripts/hang_backtrace.py
LLDB
xcrun lldb -b -s "$lldb_script" > "$output" 2>&1 || true
print "✓ $output (PID $pid)"
