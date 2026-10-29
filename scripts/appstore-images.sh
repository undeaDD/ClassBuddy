#!/bin/zsh
# App-Store-Bilder (Mockups) aus den Roh-Screenshots rendern – siehe scripts/marketing/compose.swift.
#
#   scripts/appstore-images.sh                 (Deutsch, hell und dunkel)
#   LANGUAGES="de en" scripts/appstore-images.sh
#   WEB=1 scripts/appstore-images.sh           (nur Geräte-Bilder für die Website, site/screenshots/)
#
# Vorher Roh-Screenshots aufnehmen: scripts/appstore-screenshots.sh (sonst Platzhalter bzw. README-Screenshots).
set -euo pipefail
cd "${0:A:h:h}"
swift scripts/marketing/compose.swift
