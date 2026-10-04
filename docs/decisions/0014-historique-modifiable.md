# 0014 — Historique modifiable, séance refaite, programme mis à jour

Date : 04/10/2026
Statut : accepté

## Contexte

Le lot 4 de `docs/roadmap/10-inspirations-open-source.md` rend l'historique
modifiable (corriger, refaire, partager une séance), propose de reporter dans
le programme une séance modifiée, affiche le temps actif / repos et tire des
programmes d'un import CSV. La décision 0011 avait laissé une limite : une
séance terminée est immuable pour la synchronisation (`immutableByIdentifier`).
Aucune version de schéma n'est ajoutée : `CompletedSession.editedAt` existe
depuis la v7.

## Décisions

### 1. Correction explicite, conséquences dans la même sauvegarde

`PastSessionEditor` travaille sur un brouillon (type valeur) : rien ne touche
le modèle avant « Enregistrer », et la confirmation annonce les records qui
vont changer. L'enregistrement applique en **une** sauvegarde : horaires,
note d'effort, séries corrigées / ajoutées / supprimées, exercices ajoutés /
retirés, records, `editedAt`, `revision + 1`, `updatedAt`. Un échec annule
tout (`PersistenceSupport`). Une série ajoutée après coup a un repos `nil`
(jamais inventé) et prend le rang de saisie suivant.

`date` d'une séance terminée dans Muscu est sa **fin** (posée à « Terminer ») ;
celle d'une séance importée ou venue de la montre est son **début**.
`PastSessionEditor.interval(of:)` porte cette règle unique, utilisée par
l'édition, le partage et désormais Santé (qui écrivait jusqu'ici les séances
iPhone décalées de leur durée).

### 2. Records : recalcul juste et non régressif

`RecordRevision` (moteur) tranche pour chaque record touché :
- un record **qui ne vient pas** de la séance corrigée ne peut que monter ;
- un record **qui en vient** (`PersonalBest.sourceSessionId`) est recalculé
  depuis l'historique : série supprimée ou abaissée → meilleure valeur encore
  justifiée par une autre séance, ou suppression logique s'il n'y en a plus.

`ExerciseRecord` (1RM / répétitions max saisis ou validés un par un) n'a pas
d'origine : il est attribué à la séance quand il égale exactement sa valeur
d'avant correction. Il peut alors redescendre, mais jamais **monter** grâce à
une autre séance (une valeur que l'utilisateur avait ignorée ne réapparaît
pas), et une correction n'en crée jamais. La suppression d'une séance passe
par le même calcul.

### 3. Synchronisation : la correction la plus récente gagne

`SyncRecord` gagne `editedAt` (clé facultative, renseignée pour les séances).
Pour une séance terminée vivante des deux côtés, `SyncReconciler` applique
la version distante si sa correction est plus récente, garde la locale si la
sienne l'est, et ne fait rien sans correction — l'immuabilité d'origine.
La règle est commutative : l'ordre d'arrivée ne change pas le résultat. La
séance corrigée repart dans la file d'attente par la sauvegarde elle-même
(`SyncOutboxFeeder`, la séance étant modifiée). Un appareil antérieur ignore
la clé et garde sa version : accepté, les deux versions convergent dès sa mise
à jour. `SyncMetadata.currentSchemaVersion` n'est pas incrémenté.

### 4. Santé : remplacer, jamais doubler

HealthKit ne modifie pas un entraînement enregistré. `HealthSyncPlanner`
compare `editedAt` à `HealthWorkoutLink.writtenAt` : corrigée après
l'écriture, la séance est **remplacée** — l'ancien entraînement est retiré
d'abord, puis le nouveau écrit. Si la suppression échoue (autre que
« introuvable »), rien n'est écrit et la synchronisation suivante retente :
jamais deux entraînements pour une séance. Devenue plus courte qu'une minute,
elle est seulement retirée.

### 5. Refaire = séance libre préremplie

`SessionReplay` (moteur) construit un déroulé de séance libre : un exercice
seul classique par exercice, dans l'ordre, nombre de séries de travail
principales réalisées, et pour « Refaire » la charge la plus fréquente et la
fourchette de répétitions réalisées comme cibles (« Refaire à vide » : aucune
valeur). Les groupes et formats spécialisés ne sont pas reconstruits : leur
configuration n'est pas conservée par les séries. Le titre d'origine vit dans
`WorkoutRuntimeState.title` (JSON tolérant) et survit à une reprise. Idée
d'Iron (GPL, aucun code repris).

### 6. Programme après une séance modifiée : structure seulement

Au démarrage d'une séance de programme, la structure du déroulé (mise à
l'échelle comprise) est figée dans `WorkoutRuntimeState.structureBaseline`.
En fin de séance, `SessionStructureDiff` la compare au déroulé final :
ajouts, retraits, remplacements, déplacements réels (plus longue
sous-séquence commune), nombre de séries, mesure. Jamais de charge ni de
répétitions. Rien n'est proposé si rien n'a changé, ni pour une séance
commencée avant cette clé. Les séries reportées le sont en **écart**
(prescription + séries finales − séries de départ) : une séance de décharge
ne réduit pas le programme. Inspiré de `routineDiff.ts` d'Ischys (MIT).

### 7. Import CSV → programmes

Les titres importés sont regroupés (casse et espaces ignorés), avec la
structure de la séance la plus récente et le nombre de séries **usuel** de
chaque exercice. Seuls les exercices reliés au catalogue sont proposés. Les
noms sont suffixés, jamais écrasés ; un programme créé est inactif. Le
matériel d'un nom « Deadlift (Barbell) » filtre d'abord la recherche au
catalogue (`ExerciseNaming`, prudent : suffixe inconnu = aucun matériel).

## Limites connues

- Le temps actif inclut le temps avant la première série et après la
  dernière ; le repos inclut l'exécution des séries en répétitions (début
  réel inconnu, décision 0013).
- La suppression d'une séance depuis l'historique reste physique (comme
  avant) : elle ne se propage pas comme une suppression logique.
