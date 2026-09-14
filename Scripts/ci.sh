#!/bin/bash
# Vérification complète, reproductible en local comme en intégration continue.
#
# Usage :
#   Scripts/ci.sh            # moteur + tests unitaires + builds Release
#   Scripts/ci.sh --with-ui  # ajoute la suite UI (~30 min)
#
# Ce script est la SOURCE DE VÉRITÉ de ce qu'il faut vérifier : la CI
# l'appelle telle quelle, pour que « vert en local » et « vert en CI »
# veuillent dire la même chose.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
PROJECT="Muscu.xcodeproj"
WITH_UI=0
[[ "${1:-}" == "--with-ui" ]] && WITH_UI=1

log() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# Les builds et tests pour SIMULATEUR gardent leur signature ad hoc : sans
# elle, les entitlements sont retires, le groupe d'applications disparait et
# les widgets ne sont plus testables. C'est exactement ce que ce script a
# revele a son premier passage.

# Première destination iPhone et iPad réellement disponibles : coder en dur un
# modèle casse la CI à chaque nouvelle version de Xcode.
first_simulator() {
  # Le nom complet compte : « iPad Pro 13-inch (M5) » et « Apple Watch
  # Series 11 (46mm) » portent leur variante entre parentheses. On ne retire
  # donc que l'UDID et l'etat en fin de ligne, pas tout ce qui est parenthese.
  xcrun simctl list devices available \
    | grep -E "^ +$1" \
    | head -1 \
    | sed -E 's/ \([0-9A-F-]{36}\) \(.*\) *$//; s/^ +//; s/ +$//'
}

IPHONE="$(first_simulator 'iPhone')"
IPAD="$(first_simulator 'iPad')"
WATCH="$(first_simulator 'Apple Watch')"
[[ -n "$IPHONE" ]] || { echo "Aucun simulateur iPhone disponible." >&2; exit 1; }

echo "iPhone : $IPHONE"
echo "iPad   : ${IPAD:-aucun}"
echo "Watch  : ${WATCH:-aucun}"

# Échoue si un avertissement vient de NOS sources. Les avertissements des
# outils Apple et des dépendances ne sont pas de notre ressort.
check_no_new_warnings() {
  local log_file="$1" label="$2"
  local ours
  ours="$(grep -E '^/Users.*(App/Sources|Packages/MuscuEngine/Sources|Shared|Widgets|Watch|Tests|UITests)/.*warning:' "$log_file" | sort -u || true)"
  if [[ -n "$ours" ]]; then
    echo "Avertissements dans nos sources ($label) :" >&2
    echo "$ours" >&2
    return 1
  fi
}

log "Génération du projet"
xcodegen generate

# Avant toute compilation : un catalogue incomplet ne casse pas le build, il
# livre simplement du français à un utilisateur anglophone. Seul un contrôle
# explicite le voit.
log "Localisation"
python3 Scripts/check-localization.py

log "Tests du moteur (MuscuEngine)"
swift test --package-path Packages/MuscuEngine

# Langue figee pour les tests unitaires : depuis la localisation, des
# libelles comme `DataDeletion.Category.displayName` passent par le
# catalogue. Sans ce forcage, la suite dirait « vert » ou « rouge » selon la
# langue de la machine. Les tests UI, eux, choisissent leur langue au
# lancement (dont un cas explicitement anglais) : on ne leur impose rien.
log "Tests unitaires de l'application"
xcodebuild test \
  -project "$PROJECT" \
  -scheme Muscu \
  -destination "platform=iOS Simulator,name=$IPHONE" \
  -testLanguage fr \
  -testRegion FR \
  -only-testing:MuscuTests \
  | tee "$ROOT/.ci-unit.log" \
  | grep -E "Executed [0-9]+ tests|error:|\*\* TEST" || true
grep -q '\*\* TEST SUCCEEDED \*\*' "$ROOT/.ci-unit.log"

if [[ $WITH_UI -eq 1 ]]; then
  log "Tests UI (parcours critiques)"
  xcodebuild test \
    -project "$PROJECT" \
    -scheme Muscu \
    -destination "platform=iOS Simulator,name=$IPHONE" \
    -only-testing:MuscuUITests \
    | tee "$ROOT/.ci-ui.log" \
    | grep -E "Executed [0-9]+ tests|error:|\*\* TEST" || true
  grep -q '\*\* TEST SUCCEEDED \*\*' "$ROOT/.ci-ui.log"
fi

log "Build Release — iPhone"
xcodebuild build -project "$PROJECT" -scheme Muscu \
  -destination "platform=iOS Simulator,name=$IPHONE" \
  -configuration Release > "$ROOT/.ci-release-iphone.log"
check_no_new_warnings "$ROOT/.ci-release-iphone.log" "iPhone"

if [[ -n "$IPAD" ]]; then
  log "Build Release — iPad"
  xcodebuild build -project "$PROJECT" -scheme Muscu \
    -destination "platform=iOS Simulator,name=$IPAD" \
    -configuration Release > "$ROOT/.ci-release-ipad.log"
  check_no_new_warnings "$ROOT/.ci-release-ipad.log" "iPad"
fi

# Mac Catalyst est la SEULE cible qui exige une signature reelle : sans
# equipe de developpement, on desactive la signature pour verifier au moins
# que le code compile pour cette plateforme.
log "Build Release — Mac Catalyst"
xcodebuild build -project "$PROJECT" -scheme Muscu \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Release CODE_SIGNING_ALLOWED=NO > "$ROOT/.ci-release-catalyst.log"
check_no_new_warnings "$ROOT/.ci-release-catalyst.log" "Mac Catalyst"

if [[ -n "$WATCH" ]]; then
  log "Build Release — watchOS"
  xcodebuild build -project "$PROJECT" -scheme MuscuWatch \
    -destination "platform=watchOS Simulator,name=$WATCH" \
    -configuration Release > "$ROOT/.ci-release-watch.log"
  check_no_new_warnings "$ROOT/.ci-release-watch.log" "watchOS"
fi

log "Tout est vert"
