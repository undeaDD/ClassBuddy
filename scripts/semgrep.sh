#!/bin/zsh
# Lokaler Semgrep-Scan.
# - Mit SEMGREP_APP_TOKEN (Semgrep AppSec Platform / Pro): `semgrep ci` mit den Regeln und
#   Richtlinien aus deinem Semgrep-Konto. Token z. B. in .env (wird nicht eingecheckt):
#     SEMGREP_APP_TOKEN=...
# - Ohne Token: dieselben Open-Source-Regelsätze wie die GitHub-Action.
# Voraussetzung: brew install semgrep  (oder: pipx install semgrep)
set -euo pipefail
cd "${0:A:h:h}"
if ! command -v semgrep >/dev/null; then
  print -u2 "✗ Semgrep fehlt: brew install semgrep"
  exit 1
fi
if [[ -z "${SEMGREP_APP_TOKEN:-}" && -f .env ]]; then
  set -a; source .env; set +a
fi
if [[ -n "${SEMGREP_APP_TOKEN:-}" ]]; then
  print "▸ Semgrep Pro (semgrep ci) …"
  semgrep ci "$@"
else
  print "▸ Semgrep (Open-Source-Regeln) …"
  semgrep scan \
    --config p/default --config p/swift --config p/secrets --config p/github-actions \
    --metrics off --error "$@"
fi
