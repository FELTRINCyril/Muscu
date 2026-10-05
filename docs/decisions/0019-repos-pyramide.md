# 0019 — Repos de la pyramide : un seul calcul, mode « Par palier », schéma v8

Date : 05/10/2026
Statut : accepté

## Contexte

Retour d'une vraie séance avec une longue pyramide : les durées de repos
annoncées n'étaient pas celles lancées, l'écran du déroulé débordait, et le
repos ne pouvait pas être choisi palier par palier.

La cause des durées : trois calculs différents du « max de reps » servant de
référence au repos adaptatif. La machine à états prenait le palier le plus
haut de la pyramide ; l'aperçu du déroulé (« Repos après cette série : ~X »)
prenait le record de l'exercice, ou à défaut le double du palier le plus
haut ; l'éditeur prenait le réglage « Max de reps » qui sert à dimensionner
les modèles. Une pyramide 1→10→2 avec un record de 20 annonçait ~85 s au sommet et
lançait 180 s.

## Décisions

### 1. Une seule fonction : `Pyramid.restAfterStep`

Machine à états, aperçu du déroulé, éditeur (cartes de modèle et lignes de
palier) et estimation de durée appellent tous `Pyramid.restAfterStep`
(ou `WorkoutExercisePlan.pyramidRest(afterStep:repsDone:)`). Un test moteur
déroule une pyramide de 18 paliers avec des reps ajustées et vérifie, palier
par palier, que l'aperçu égale le repos lancé.

Référence d'intensité : le **palier le plus haut de la pyramide elle-même**.
Elle est toujours disponible (un record peut manquer), stable pendant la
séance (un record battu en cours de route ne déplace pas les repos suivants)
et identique sur tous les appareils. Le palier le plus dur obtient le repos
maxi, les plus légers un repos proche du mini.

Une pyramide sans bornes de repos (0/0, par exemple issue d'un modèle de
séance antérieur qui ne les copiait pas) prend 30-180 s au lieu d'un repos
nul. Les modèles copient désormais les bornes et les repos par palier.

### 2. Aucun repos après le dernier palier

L'éditeur n'en montrait pas et l'aperçu du déroulé non plus, mais la machine
à états en lançait un si un exercice suivait (adaptatif, calculé sur le
dernier palier, souvent le plus léger). Il n'existe plus : la pyramide se
termine sur son dernier palier, l'exercice suivant s'affiche aussitôt.

### 3. Mode « Par palier »

`PrescribedExercise.pyramidRestSeconds: [Int]` — vide = adaptatif
(comportement d'avant) ; sinon exactement une valeur par palier, de 0 à
10 min (0 = enchaîner). La valeur du dernier palier est conservée mais jamais
lancée ni affichée : elle réapparaît si ce palier est déplacé ou si un palier
est ajouté après lui. Stocker une valeur par palier (et non entre deux
paliers) permet à un repos de **suivre son palier** quand on le déplace,
l'ajoute ou le supprime (`PyramidSteps`, testé).

Passer en « Par palier » part des valeurs de l'adaptatif : rien ne change
tant que l'utilisateur n'a rien touché. Réglage par pas de 5 s sous la
minute, 15 s au-delà ; « Appliquer à tous les paliers » pose une durée
commune. Choisir un modèle recalcule les repos depuis l'adaptatif.

Une liste mal alignée (archive retouchée) est normalisée à la construction du
déroulé ; refusée à l'import JSON (vide, ou un repos 0-600 s par palier).

### 4. Schéma v8

La v7 est installée avec des données réelles : modifier ses modèles sans
nouvelle version rendrait le store illisible. `MuscuSchemaV7` est figé par
`Scripts/freeze-schema.py`, les modèles vivants deviennent `MuscuSchemaV8`,
`migrateV7toV8` est légère (un attribut à valeur par défaut). Le test de
migration écrit un store v7 figé : une pyramide v7 garde paliers et bornes et
passe en mode adaptatif. Le déroulé persisté (`WorkoutExercisePlan`, JSON)
se décode sans la nouvelle clé.

### 5. Déroulé d'une longue pyramide

Les pastilles des paliers défilent horizontalement et se recentrent sur le
palier courant, avec « Palier 7 sur 18 » ; le compteur de reps n'impose plus
de largeur minimale et suit Dynamic Type. L'aperçu du repos est exact (plus
de « ~ ») et le repos affiche le palier suivant.
