#!/bin/bash
# Refuse toute chaîne qui ressemble à un secret dans le dépôt.
#
# Une clé d'API collée « juste pour tester » est le genre de chose qui
# survit à la relecture et part dans l'historique git, où elle reste même
# après suppression. Ce contrôle est là pour que ça n'arrive pas.
#
# Il vérifie AUSSI le binaire construit quand il existe : une clé peut avoir
# été embarquée par une ressource plutôt que par du code.
set -uo pipefail

cd "$(dirname "$0")/.."

# Formes réellement dangereuses, pas « toute suite de caractères ».
PATTERNS=(
  'sk-[A-Za-z0-9_-]{20,}'          # OpenAI et compatibles
  'sk_live_[A-Za-z0-9]{16,}'       # Stripe
  'ghp_[A-Za-z0-9]{36}'            # jeton GitHub
  'AIza[A-Za-z0-9_-]{35}'          # Google
  'xox[baprs]-[A-Za-z0-9-]{10,}'   # Slack
  '-----BEGIN [A-Z ]*PRIVATE KEY'  # clé privée
)

status=0

scan_sources() {
  for pattern in "${PATTERNS[@]}"; do
    # `git grep` ne regarde que les fichiers SUIVIS : ce qui est ignoré
    # (journaux, DerivedData) ne partira jamais dans l'historique.
    if git grep -nIE -e "$pattern" -- . ':!Scripts/check-secrets.sh' > /tmp/muscu-secrets.txt 2>/dev/null; then
      echo "Secret potentiel dans les sources :"
      cat /tmp/muscu-secrets.txt
      status=1
    fi
  done
}

scan_binary() {
  local app
  app="$(find ~/Library/Developer/Xcode/DerivedData/Muscu-*/Build/Products \
    -maxdepth 2 -name 'Muscu.app' -print -quit 2>/dev/null)" || true
  [[ -z "$app" ]] && return 0

  for pattern in "${PATTERNS[@]}"; do
    if strings -a "$app/Muscu" 2>/dev/null | grep -qE -e "$pattern"; then
      echo "Secret potentiel dans le binaire construit : motif $pattern"
      status=1
    fi
  done
}

scan_sources
scan_binary

if [[ $status -eq 0 ]]; then
  echo "Secrets : rien trouvé dans les sources suivies ni dans le binaire."
fi
exit $status
