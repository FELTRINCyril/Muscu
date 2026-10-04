#!/bin/bash
# Synchronise les catalogues de chaînes avec les littéraux du code.
#
# Xcode fait exactement cela à chaque compilation depuis l'IDE. Ce script
# existe pour que la même opération soit reproductible en ligne de commande,
# sans ouvrir Xcode.
#
# Il NE traduit rien : il ajoute les nouvelles clés (à l'état « new ») et
# marque celles qui ont disparu du code. La traduction reste un geste
# humain, et `Scripts/check-localization.py` refuse tout ce qui est resté
# à l'état « new ».
set -euo pipefail

cd "$(dirname "$0")/.."
# Simulateurs : dernier de la liste, donc du runtime le plus recent — voir
# `first_simulator` dans Scripts/ci.sh.
PROJECT="Muscu.xcodeproj"
IPHONE_DESTINATION="platform=iOS Simulator,name=$(
  xcrun simctl list devices available \
    | grep -E '^ +iPhone' \
    | tail -1 \
    | sed -E 's/ \([0-9A-F-]{36}\) \(.*\) *$//; s/^ +//; s/ +$//'
)"

log() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

log "Compilation (c'est elle qui extrait les chaînes)"
xcodegen generate
xcodebuild build \
  -project "$PROJECT" \
  -scheme Muscu \
  -destination "$IPHONE_DESTINATION" \
  -configuration Debug \
  > /dev/null
xcodebuild build \
  -project "$PROJECT" \
  -scheme MuscuWatch \
  -destination "platform=watchOS Simulator,name=$(
    xcrun simctl list devices available \
      | grep -E '^ +Apple Watch' \
      | tail -1 \
      | sed -E 's/ \([0-9A-F-]{36}\) \(.*\) *$//; s/^ +//; s/ +$//'
  )" \
  -configuration Debug \
  > /dev/null

BUILD_ROOT="$(
  xcodebuild -project "$PROJECT" -scheme Muscu -showBuildSettings 2>/dev/null \
    | awk '/ OBJROOT =/ { print $3 }'
)"

sync_catalog() {
  local catalog="$1" objects="$2"
  if [[ ! -d "$objects" ]]; then
    echo "Répertoire d'objets introuvable : $objects" >&2
    return 1
  fi
  log "$catalog"
  find "$objects" -name '*.stringsdata' -print0 \
    | xargs -0 xcrun xcstringstool sync "$catalog" --stringsdata
}

sync_catalog App/Resources/Localizable.xcstrings \
  "$BUILD_ROOT/Muscu.build/Debug-iphonesimulator/Muscu.build/Objects-normal"
sync_catalog Widgets/Localizable.xcstrings \
  "$BUILD_ROOT/Muscu.build/Debug-iphonesimulator/MuscuWidgets.build/Objects-normal"
sync_catalog Watch/Localizable.xcstrings \
  "$BUILD_ROOT/Muscu.build/Debug-watchsimulator/MuscuWatch.build/Objects-normal"

log "Vérification"
python3 Scripts/check-localization.py || {
  echo
  echo "Des chaînes restent à traduire : ouvrez les catalogues dans Xcode."
  exit 1
}
