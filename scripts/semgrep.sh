#!/bin/zsh
# Lokaler Semgrep-Scan mit denselben Regeln wie die GitHub-Action.
# Voraussetzung: brew install semgrep  (oder: pipx install semgrep)
set -euo pipefail
cd "${0:A:h:h}"
if ! command -v semgrep >/dev/null; then
  print -u2 "✗ Semgrep fehlt: brew install semgrep"
  exit 1
fi
semgrep scan \
  --config p/default --config p/swift --config p/secrets --config p/github-actions \
  --metrics off --error "$@"
