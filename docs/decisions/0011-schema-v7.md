# 0011 — Schéma v7 : champs préparatoires des inspirations open source

Date : 03/10/2026
Statut : accepté

## Contexte

Le document `docs/roadmap/10-inspirations-open-source.md` découpe huit lots.
Plusieurs ont besoin d'attributs persistés : note d'effort et cardio d'une
séance, repos réel d'une série, correction d'une séance passée, lien de
démonstration, fusion de doublons, import Santé dédoublonné. Les ajouter lot
par lot aurait produit autant de versions de schéma ; ils sont donc posés
ensemble, d'un coup, au lot 1.

## Décisions

### 1. Dix attributs facultatifs, une migration légère

`MuscuSchemaV6` est figé (`Scripts/freeze-schema.py 6`), les modèles vivants
deviennent `MuscuSchemaV7` et `migrateV6toV7` est une étape légère.

| Modèle | Attribut | Sens de `nil` |
| --- | --- | --- |
| `CompletedSession` | `effortRating` (1-10) | effort non noté |
| `CompletedSession` | `avgHeartRate`, `maxHeartRate`, `minHeartRate` | cardio non mesuré |
| `CompletedSession` | `activeEnergyKcal` | énergie non mesurée |
| `CompletedSession` | `editedAt` | jamais corrigée après coup |
| `CompletedSet` | `actualRestSeconds` | repos non mesuré |
| `ExerciseLibraryEntry` | `demoURL` | aucun lien |
| `CustomExercise` | `mergedIntoExerciseId` | exercice actif |
| `BodyMeasurement` | `healthSampleUUID` | pas d'échantillon Santé connu |

Tous sont `nil` par défaut : **zéro est une mesure, `nil` une absence**. Une
séance antérieure à la v7 n'a pas de note d'effort, elle n'a pas un effort de 0.

### 2. La redirection de fusion vit sur `CustomExercise`

Le catalogue embarqué est en lecture seule et identique pour tous : fusionner
deux exercices du catalogue n'a pas de sens. Un doublon est toujours un
exercice **personnalisé** (créé à la main ou par un import) qui recouvre un
exercice du catalogue ou un autre exercice personnalisé. La fiche fusionnée
est conservée avec `mergedIntoExerciseId` plutôt que supprimée : une
référence ancienne (programme, archive, appareil pas encore synchronisé) se
résout ainsi vers l'exercice retenu.

`editedAt` est distinct de `updatedAt`, que la synchronisation et les
réparations touchent aussi : seul `editedAt` dit « l'utilisateur a corrigé
cette séance ».

### 3. Export JSON : aller-retour complet

Les dix attributs rejoignent les DTO d'export comme les autres champs
facultatifs : clés optionnelles, absentes des archives antérieures, qui se
décodent donc sans traitement. La version d'archive reste 4 — une archive v7
lue par une version antérieure de l'application ignore simplement ces clés.

L'import valide les valeurs présentes : note d'effort 1-10, fréquence
cardiaque 20-300 bpm, énergie 0-100 000 kcal, repos 0-86 400 s, lien de
démonstration `http`/`https` absolu uniquement (`DemoLink`, moteur) — un lien
`javascript:` ou un schéma d'application venu d'une archive serait ouvert
tel quel.

### 4. Synchronisation : les mesures Santé restent sur l'appareil

La synchronisation réutilise les DTO d'export. Exception : la fréquence
cardiaque et l'énergie active, **lues dans HealthKit**, sont retirées de la
charge utile synchronisée (`SyncSerialization.syncDTO`) — les règles d'Apple
interdisent de stocker des données de santé dans iCloud. Appliquer une
séance distante conserve ces valeurs locales au lieu de les effacer. La note
d'effort, saisie dans Muscu, voyage normalement.

La version de schéma de synchronisation (`SyncMetadata.currentSchemaVersion`)
n'est pas incrémentée : les attributs sont facultatifs et un appareil plus
ancien les ignore. Limite connue : une séance terminée est immuable côté
synchronisation (`immutableByIdentifier`) ; la correction d'une séance
passée (lot 4) devra donc revoir cette règle pour propager `editedAt`.
*Levée par la décision 0014 : la correction la plus récente (`editedAt`)
gagne.*
