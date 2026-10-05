# 0013 — Séance libre, exercices modifiables en séance, séries mesurées

Date : 04/10/2026
Statut : accepté

## Contexte

Le lot 3 de `docs/roadmap/10-inspirations-open-source.md` ajoute la séance
libre, l'ajout et le réordonnancement d'exercices en séance, les séries au
temps et à la distance, le repos réel et la note d'effort de séance. Le
runner unifié (décision 0002) doit rester la seule source de vérité du
déroulé, et le schéma v7 (décision 0011) ne doit pas changer de version.

## Décisions

### 1. Une séance libre est un déroulé vide, pas un autre runner

`WorkoutState(freeSessionWith:)` démarre avec `WorkoutPlan(nodes: [])` et la
même machine à états. Ajouter un exercice ajoute un nœud en fin de déroulé :
une position « terminée » désigne alors naturellement le nouvel exercice.
Seule différence : une séance libre ne se termine que sur demande
(`requestEnd`) ; un déroulé épuisé affiche « Ajouter un exercice / Terminer ».

`ActiveWorkout` gagne `isFreeSession` (booléen, faux par défaut — toute
séance antérieure venait d'un programme), ajouté au modèle vivant v7 non
publié : migration légère inchangée. `programSessionId` y reste non
facultatif et ne désigne rien. La clé `isFreeSession` est facultative dans
l'export ; sans instantané du déroulé (archive, synchronisation), le déroulé
est reconstruit depuis les séries enregistrées et leurs index renumérotés.

La séance terminée n'a ni `programId` ni `programSessionId` : elle ne fait
pas avancer la rotation, et la réparation d'intégrité ne la rattache à aucun
programme.

### 2. Ce qui est commencé ne bouge pas

`WorkoutPlanEditing` (moteur) ne propose au réordonnancement que les nœuds à
partir de la position courante **sans aucune série enregistrée** (échauffement
compris). Un exercice commencé plus loin via l'aperçu garde sa place : les
nœuds déplacés occupent les mêmes emplacements. Les séries désignent leur
exercice par son index « à plat » : il est renuméroté dans la même
sauvegarde quand un groupe de taille différente change de place.

### 3. La mesure d'une prescription se déduit de ses cibles

`PrescribedExercise.targetDurationSeconds` et `targetDistanceMeters` existaient
(zéro = non prescrit) : la mesure (`SetMeasure`) s'en **déduit**, aucun
attribut n'est ajouté. Choisir « Temps » pose une cible par défaut (30 s),
revenir à « Poids × répétitions » remet les cibles à zéro. Seul le format
classique porte une mesure. Dans le déroulé, `WorkoutExercisePlan` gagne
`measure` et ses cibles en champs facultatifs : un déroulé persisté avant
reste lisible.

Une série mesurée a `reps = 0` : le moteur ne lui calcule ni tonnage ni
1RM, et ne la compte pas comme « donnée manquante ». Records : durée
maximale (nouvelle nature `maxDuration`, plus haut = mieux), distance
maximale, et meilleur temps **à distance égale** (`bestTime`, clé
`distance:<m>`, plus bas = mieux) — deux distances ne sont jamais comparées.

### 4. Repos réel : validation à validation, borné

`ActualRest` mesure l'écart entre la validation de la série précédente de la
séance et celle-ci, moins la durée saisie d'une série chronométrée. `nil`
pour la première série, au-delà d'une heure (interruption) ou si l'horloge
recule. Le début réel d'une série en répétitions n'est pas connu : le repos
inclut donc son temps de travail — limite assumée et documentée.

### 5. Note d'effort figée à la fin

Choisie avant « Terminer », elle part avec la séance ; ensuite elle n'est
plus modifiable, une séance terminée étant immuable pour la synchronisation
(la correction d'une séance passée relève du lot 4).

### 6. Export CSV : colonnes ajoutées en fin de ligne

`effort_seance`, `distance_m` et `repos_reel_secondes` sont ajoutées **à la
fin** des lignes. La politique est désormais écrite dans
`docs/formats/csv.md` : jamais de colonne renommée, déplacée ni supprimée.

## Limites connues

- Le chronomètre d'une série au temps en cours n'est pas persisté : un kill
  de l'application pendant un gainage perd le temps écoulé (la saisie
  manuelle reste possible).
- Un appareil antérieur qui reçoit un record `maxDuration` le lit comme une
  charge maximale (repli existant de `PersonalBestKind`).
