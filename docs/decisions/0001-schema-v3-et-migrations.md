# 0001 — Schéma v3, migrations et règles de calcul partagées

Date : 2026-09-12
Statut : accepté
Phase de la roadmap : 1 (fondations et modèle de données)

## Contexte

Le schéma SwiftData déclarait une seule version (`MuscuSchemaV1`) dont la liste
de modèles pointait vers les classes courantes. Ces classes avaient déjà évolué
deux fois sans que la version déclarée change : un store existant ne pouvait
donc plus être migré (`Cannot use staged migration with an unknown model
version`). Il fallait aussi introduire les entités décrites dans
`docs/roadmap/01-foundations-and-data-model.md` sans réécrire les données.

## Décisions

### 1. Versions de schéma figées

Chaque version du schéma possède désormais ses propres types, figés :

- `MuscuSchemaV1` (1.0.0) — socle initial, sans identifiants uniques, sans
  typage de charge des séries, sans identifiants de programme sur l'historique ;
- `MuscuSchemaV2` (2.0.0) — identifiants uniques, `loadTypeRaw`,
  `programId`/`programSessionId`, état d'exécution persisté ;
- `MuscuSchemaV3` (3.0.0) — modèle produit v3, seule version dont les modèles
  sont ceux réellement utilisés par l'application.

Règle : avant toute modification d'un `@Model`, figer une copie de l'état actuel
dans une nouvelle `VersionedSchema`. `MuscuCurrentSchema` est le seul alias à
mettre à jour.

Les deux étapes de migration sont légères : aucune donnée existante n'est
transformée, tous les ajouts sont des entités nouvelles ou des attributs
facultatifs / pourvus d'une valeur par défaut.

### 2. Fixtures binaires de migration

`Tests/Fixtures/v1-initial.store` et `Tests/Fixtures/v1-prechange.store` sont
des stores SQLite réels, générés une fois avec les modèles de l'époque, puis
figés. `Tests/MigrationTests.swift` les copie dans un dossier temporaire, les
ouvre avec le schéma courant et vérifie que programmes, séances, prescriptions,
historique, records, exercices personnalisés et séance en cours sont intacts.

Ces fichiers ne doivent jamais être régénérés depuis le schéma courant : ce sont
des témoins. Les fichiers annexes `-wal` / `-shm` ne sont pas versionnés (le
store est checkpointé avant d'être figé).

### 3. Normalisation hors du plan de migration

`SchemaUpgrade` applique après ouverture les normalisations qui ne sont pas des
transformations de schéma : cohérence des dates de synchronisation, reprise des
`ExerciseRecord` sous forme de `PersonalBest` typés. Elle est idempotente et
séparée du plan de migration, afin qu'un échec de normalisation n'empêche jamais
l'ouverture du store.

### 4. `ExerciseRecord` et `PersonalBest` coexistent

`ExerciseRecord` reste la référence du pilotage « % 1RM » et « % max reps » dans
le runner, ainsi que des exports v1/v2. `PersonalBest` est le magasin de records
**typés** (charge, 1RM estimé, répétitions, tonnage, temps, tours, distance),
avec une clé de configuration pour les formats chronométrés et pour le lest ou
l'assistance. Les deux sont recalculables depuis l'historique, qui reste la
source de vérité.

### 5. Règles de calcul dans `MuscuEngine`

Les formules ne vivent plus dans les vues :

- `LoadKind` décrit les quatre types de charge (`external`, `bodyweight`,
  `weighted`, `assisted`) plus `unknown` pour les données antérieures ;
- `SetMetrics` calcule charge effective, tonnage, éligibilité au 1RM et durée
  sous tension ; il renvoie `nil` quand le poids de corps est nécessaire mais
  inconnu, pour que les vues distinguent « zéro » de « donnée manquante » ;
- `ExerciseClassification` déduit le type de charge depuis le catalogue ; une
  prescription qui déclare son type l'emporte toujours ;
- `MergePolicy` documente la stratégie de fusion de chaque type d'entité ;
- `Units` fixe le kilogramme comme **valeur canonique** stockée : `MassUnit` ne
  sert qu'à l'affichage et à la saisie.

### 6. Records et types de charge

- Une série **assistée** ne produit jamais de record de charge, ni de record de
  répétitions non qualifié : huit tractions avec 30 kg d'aide ne valent pas huit
  tractions strictes. Un tel record porte une clé de configuration
  (`assisted:30.0`).
- Une série **lestée** vaut par le total soulevé (poids de corps + lest) pour le
  1RM estimé, mais la progression de charge porte sur le **lest seul**.
- Les séries antérieures au typage (`unknown`) sont lues par leur charge :
  charge nulle = poids de corps, charge saisie = charge externe. Sans cette
  lecture, tout l'historique existant perdrait ses records.

### 7. Export v3

L'enveloppe v3 est `{ version, exportedAt, manifest, payload }` :

- le **manifeste** porte la version de schéma, la version de l'app, les
  compteurs par type et une somme de contrôle `sha256:` du payload encodé de
  manière canonique (clés triées, dates ISO 8601) ;
- le **payload** contient toutes les entités, y compris profil, mesures,
  check-in, records typés et plans d'entraînement.

Les archives v1 et v2 (enveloppe plate) restent importables : elles sont
décodées vers le même payload, les champs v3 absents prenant une valeur neutre.
L'import reste idempotent (fusion par UUID), validé **avant** toute insertion,
et annulé en bloc en cas d'erreur.

## Conséquences

- Ajouter un champ à un `@Model` impose désormais de figer une version de schéma.
- Toute nouvelle vue qui affiche un tonnage, un 1RM ou un record doit passer par
  `SetMetrics` plutôt que recalculer sa propre formule.
- Le poids de corps est figé sur chaque séance terminée (`bodyweightKilograms`),
  afin que les calculs restent justes même si l'athlète change de poids ensuite.
