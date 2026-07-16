#!/bin/bash
# Telecharge la base free-exercise-db (source des exercices)
set -euo pipefail
DEST="$(dirname "$0")/exercises_source.json"
curl -fsSL "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json" -o "$DEST"
echo "OK: $(jq length "$DEST") exercices dans $DEST"
