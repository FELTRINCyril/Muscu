# 0002 — Runner unifié et formats avancés

Date : 2026-09-12
Statut : accepté
Phase de la roadmap : 2 (formats avancés et runner unifié)

## Contexte

Le déroulé de séance était piloté par deux entiers portés par `WorkoutState`
(`currentExerciseIndex`, `currentSetIndex`) et par une cascade de conditions
propres à chaque vue. Ce modèle ne pouvait pas représenter un superset (deux
exercices alternés sur plusieurs tours), un dropset (plusieurs paliers dans une
même série) ni un circuit, et chaque nouveau format aurait ajouté une condition
supplémentaire dans les vues.

## Décisions

### 1. Une machine à états unique, pure, dans `MuscuEngine`

`WorkoutPlan` décrit la séance comme une suite de `WorkoutNode` (exercice seul
ou groupe). `WorkoutPosition` décrit *où* l'on en est : nœud, tour, exercice du
groupe, série, sous-série. `WorkoutStateMachine` répond à deux questions et
deux seulement :

- `step(at:in:)` — qu'affiche-t-on maintenant ?
- `advance(from:in:outcome:)` — où va-t-on après ce résultat, et quel repos ?

Aucune vue ne décide plus de la suite. `WorkoutState` ne fait que construire le
plan, persister et exposer les suggestions issues de l'historique.

Conséquence testable : la reprise se vérifie en rejouant la séance et en
« coupant » à chaque transition possible, puis en repartant de la seule
`WorkoutPosition` sérialisée.

### 2. Les groupes vivent dans le modèle, pas dans les notes

`ExerciseGroup` (superset, triset, giant set, circuit) porte le type, le nombre
de tours, le repos entre exercices, le repos entre tours et la transition de
circuit. Un `PrescribedExercise` y est rattaché par une relation, jamais par une
convention de nommage.

Un groupe dont le nombre d'exercices ne correspond plus à son type est dissous
automatiquement plutôt que laissé dans un état impossible (un « superset » à un
seul exercice n'existe pas).

### 3. Repos nul : autorisé seulement là où il a un sens

`SetFormat.allowsZeroRest` et `ExerciseGroupKind.allowsZeroRestBetweenExercises`
décrivent cette règle en un seul endroit. Le sélecteur de repos d'une série
classique commence à 15 s ; le repos entre exercices d'un superset commence à 0.

### 4. Sous-séries : dropset, rest-pause, myo-reps

Ces trois formats prolongent une série de travail par des sous-séries.
`WorkoutPosition.subSetIndex` les représente ; la machine à états décide de la
sortie du bloc selon la règle du format :

- dropset : nombre de paliers configuré ;
- rest-pause : seuil de répétitions, nombre maximum de mini-séries, ou décision
  de l'utilisateur ;
- myo-reps : mini-série qui n'atteint plus la cible, maximum, ou décision.

Les charges d'un dropset sont **cumulatives** (chaque palier part du précédent)
et arrondies **vers le bas** au palier de chargement réellement disponible :
jamais une charge impossible à charger.

### 5. « For Time » mesure un temps, pas des répétitions

Réutiliser l'écran AMRAP aurait inversé la sémantique du format. `ForTimeRunnerView`
chronomètre en avant depuis une date absolue, gère un plafond facultatif, et fige
le temps au plafond même si l'app a été suspendue pendant le bloc.

### 6. Records spécifiques au format et à la configuration

`PersonalBestUpdater` produit des records typés depuis l'historique. Un AMRAP de
8 minutes et un AMRAP de 12 minutes ne sont jamais comparés : la clé de
configuration porte la durée. Un For Time s'améliore en **diminuant**. Une série
lestée ou assistée porte sa charge dans sa clé.

### 7. Estimation de durée partagée

`SessionDuration` (moteur) remplace le calcul qui vivait dans `HomeView`. Dans
un groupe, le travail compte une fois **par tour** et non `setCount` fois par
exercice, sinon la durée d'un superset serait doublée.

### 8. Récupération d'un store illisible

Découvert en exécutant la suite UI : un store écrit par une version
intermédiaire du schéma rend l'app inutilisable derrière une alerte sans issue.
`StoreRecovery` permet désormais d'exporter une copie de la base d'origine
depuis cette alerte, sans jamais la supprimer. En DEBUG et **uniquement** avec
`--uitest-reset`, les tests UI peuvent repartir d'un store neuf.

## Compatibilité

- `ActiveWorkout` gagne `planData` et `positionData`. Une séance commencée avant
  ce changement est reprise depuis `runExercisesData` (décodé par
  `LegacyRunExercise`) et depuis les index plats, sans perte.
- `CompletedSet` gagne `groupId`, `roundIndex`, `subSetIndex`, `effortData`,
  `reachedFailure`, `notes`, `plannedExerciseId` et `formatRaw` : tous
  facultatifs, les séries existantes restent lisibles telles quelles.

## Limites connues

- La Dynamic Island / Live Activity du chrono relève de la phase 7.
- Les séries d'approche (`SetRole.approach`) sont modélisées mais ne sont pas
  encore proposées dans l'interface.
