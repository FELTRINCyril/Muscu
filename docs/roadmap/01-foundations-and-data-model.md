# 01 — Fondations et modèle de données

## Objectif

Faire évoluer le domaine sans casser les programmes, historiques ou séances en
cours déjà enregistrés. Cette phase précède iCloud, les formats avancés et l’IA.

## Architecture attendue

- Conserver SwiftUI, SwiftData et `MuscuEngine`.
- Maintenir la logique déterministe et testable dans `MuscuEngine` lorsque celle-ci
  ne dépend ni de SwiftUI ni de SwiftData.
- Introduire des services protocolés pour CloudKit, HealthKit, IA, notifications
  et horloges afin de fournir des implémentations simulées dans les tests.
- Éviter un « god object » de séance : séparer définition du programme, plan de
  séance, état d’exécution et résultat terminé.
- Utiliser des identifiants UUID stables et ne jamais relier des entités par leur
  nom affiché.

## Schéma cible

Créer une nouvelle version réelle du schéma SwiftData et un plan de migration.
Les noms peuvent être ajustés, mais les responsabilités suivantes sont requises.

### Profil

`AthleteProfile`

- identifiant stable ;
- prénom facultatif ;
- date de naissance facultative ;
- taille, poids actuel et unités préférées ;
- niveau, objectifs, jours disponibles, durée habituelle maximale ;
- équipement disponible ;
- zones à ménager ;
- préférences de progression ;
- date de création et de modification.

Les données de santé sensibles doivent être facultatives et clairement séparées
des informations nécessaires au fonctionnement de base.

### Programmation

Ajouter les concepts suivants :

- `TrainingPlan` ou extension de `Program` avec dates, statut et version ;
- `TrainingBlock` : accumulation, intensification, réalisation ou décharge ;
- `TrainingWeek` : numéro, cible de volume et état ;
- `ScheduledWorkout` : date planifiée, séance source et état ;
- `ExercisePrescription` versionnée ;
- `ExerciseGroup` pour les supersets et circuits ;
- `ProgressionRule` typée et sérialisable.

Une modification d’un programme ne doit jamais réécrire rétroactivement une
séance terminée. Une séance commencée utilise un snapshot autonome.

### Exécution

Remplacer progressivement les blobs JSON opaques de `ActiveWorkout` par un état
versionné et validable. Un blob reste acceptable pour certains sous-états, à
condition d’avoir :

- un numéro de version ;
- une taille maximale ;
- une stratégie de migration ou d’abandon contrôlé ;
- un test de décodage de chaque ancienne version.

Modéliser :

- groupes et exercices actifs ;
- séries planifiées et réalisées ;
- charge et type de charge : externe, poids du corps, lest, assistance ;
- répétitions, durée, distance et calories lorsque pertinentes ;
- RPE, RIR, tempo et notes ;
- chronos en cours avec échéances absolues ;
- pauses et progression dans les groupes avancés.

### Historique et mesures

Ajouter :

- `BodyMeasurement` ;
- `ReadinessEntry` ;
- `PersonalBest` typé ;
- `HealthWorkoutLink` pour éviter les doubles écritures HealthKit ;
- métadonnées de création, modification et suppression nécessaires à la synchro.

## Suppression et synchronisation

Pour les entités synchronisées, préférer des suppressions logiques temporaires
(`deletedAt`) ou une stratégie CloudKit équivalente afin qu’une suppression hors
ligne soit propagée. Prévoir une purge différée.

Définir une règle de fusion par type :

- historique terminé : immuable, fusion par UUID ;
- record : maximum des performances compatibles, puis date la plus récente ;
- programme : dernière modification avec détection de conflit visible ;
- séance active : un seul propriétaire d’édition à la fois ;
- réglages : dernière modification par clé ;
- mesures corporelles : fusion par UUID, jamais par valeur ou date seule.

## Import/export v3

Créer une enveloppe v3 qui inclut toutes les nouvelles entités et conserve :

- décodage des versions v1 et v2 ;
- validation avant mutation ;
- import idempotent ;
- transaction et rollback ;
- aperçu avant confirmation ;
- limites de taille et de cardinalité ;
- export lisible et documenté.

Ajouter un manifeste dans l’archive avec version, date, compteurs et somme de
contrôle. Pour les médias personnalisés, utiliser une archive de paquet plutôt
qu’un JSON gigantesque encodé en base64.

## Migrations

Avant toute fonctionnalité dépendante :

1. figer dans les tests un store représentatif de la version actuelle ;
2. ouvrir ce store avec le nouveau schéma ;
3. vérifier programmes, relations, historique, records et séance active ;
4. vérifier une migration interrompue ou un store corrompu ;
5. préserver le store original et proposer une exportation de récupération.

## Critères d’acceptation

- Tous les tests actuels restent verts.
- Une base issue de la version actuelle migre sans perte.
- Une séance terminée ne change pas quand son programme source est modifié.
- Les quatre types de charge ne produisent pas de faux records.
- Les anciennes sauvegardes v1 et v2 sont importables.
- Deux imports identiques ne créent aucun doublon.
- Chaque entité synchronisable possède identifiant, dates et stratégie de conflit.
- Aucun `try? context.save()` silencieux n’est introduit.
