#!/bin/zsh
# Aktiviert die Git-Hooks aus .githooks/ für dieses Repository (einmalig nach dem Klonen).
set -euo pipefail
cd "${0:A:h:h}"
chmod +x .githooks/*
git config core.hooksPath .githooks
print "✓ Git-Hooks aktiv: pre-commit (SwiftLint + Tests), commit-msg (Nachrichten-Regeln)"
