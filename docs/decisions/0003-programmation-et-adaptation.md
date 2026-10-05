# 0003 — Programmation, périodisation et adaptation

Date : 2026-09-13
Statut : accepté
Phase de la roadmap : 3 (programmation, périodisation et adaptation)

## Contexte

Le générateur produisait un programme ponctuel : une semaine type, sans dates,
sans progression et sans explication. Rien ne permettait de faire évoluer un
programme à partir des performances réelles, ni d'expliquer pourquoi une charge
devrait monter.

## Décisions

### 1. La progression est une PROPOSITION, jamais une écriture

`ProgressionEngine` (moteur, pur) répond à une seule question : « au vu de ces
expositions passées, que propose la règle ? ». Il renvoie une
`ProgressionProposal` composée d'un `ProgressionOutcome` et de ses
`ProgressionFactor`.

Trois invariants, testés comme propriétés :

- sans historique exploitable, la réponse est `notEnoughData` — jamais une
  valeur inventée ;
- toute proposition porte **au moins un facteur** rattaché à une performance
  identifiable (« 2 séances d'affilée avec toutes les séries à 12 répétitions ») ;
- une montée de charge n'est jamais proposée après une séance ratée.

Huit règles sont implémentées : double progression, charge linéaire,
répétitions, séries, pourcentage de 1RM, cible d'effort (RIR), lesté/assisté et
progression temporelle.

### 2. Les charges proposées sont chargeables

Toute charge proposée est arrondie à un palier réellement disponible, lu depuis
`AthleteProfile.availableIncrementsKilograms`. Une salle sans disques de 1,25 kg
ne se voit jamais proposer 61,25 kg.

### 3. Lesté et assisté progressent en sens inverse

Une traction **lestée** progresse en ajoutant du lest ; une traction **assistée**
progresse en **retirant** de l'assistance. La charge de référence est donc le
maximum dans un cas et le minimum dans l'autre.

### 4. Journal d'adaptation : proposé, décidé, annulable

`AdaptationEntry` conserve la proposition, ses facteurs, la décision et les
valeurs **avant/après**. C'est ce qui rend une adaptation annulable exactement :
`ProgressionReview.revert` restaure les valeurs d'origine sans recalcul.

Une proposition refusée est également journalisée : refuser est une information.

### 5. Le check-in ne diagnostique rien

`ReadinessAdvisor` traduit un check-in en suggestion (`keepAsPlanned`,
`reduceVolume`, `reduceLoad`, `suggestSubstitution`, `suggestRest`) accompagnée
de ses facteurs.

Une douleur déclarée à partir de 4/10 déclenche **systématiquement** un message
prudent invitant à consulter un professionnel de santé, quelle que soit la
suggestion d'entraînement. Ce message dit explicitement que l'application ne
pose aucun diagnostic. Le score de fatigue est volontairement simple — un point
par signal défavorable — pour rester explicable ligne par ligne.

### 6. Périodisation : des multiplicateurs, pas des séances dupliquées

`Periodization` produit des semaines portant un `volumeMultiplier` et un
`intensityMultiplier`. Une semaine ne duplique jamais les séances du programme :
elle décrit son **écart** à la prescription de base.

Une décharge réduit réellement le volume (×0,5) et l'intensité (×0,9). Un plan
ne se termine jamais sur une décharge : le cycle finit sur du travail réel.

Conséquence corrigée en cours de route : `TrainingWeek.isDeload` ne peut pas se
déduire d'un volume réduit, puisqu'une semaine d'**intensification** réduit elle
aussi le volume. Seul le bloc fait foi.

### 7. Un validateur local, avant l'IA

`ProgramValidator` vérifie qu'un programme respecte les contraintes déclarées :
matériel, niveau, zones à ménager, exercices exclus, cohérence des prescriptions,
bornes de volume, récupération entre séances consécutives, durée estimée.

Deux niveaux : `blocking` (contrainte explicite de l'athlète violée) et
`warning` (écart à une recommandation). Un test de propriété vérifie que le
générateur local produit toujours un programme que son propre validateur
accepte, pour tous les jours et tous les objectifs — c'est la garantie du repli
hors ligne dont la phase 8 aura besoin.

### 8. Déterminisme

`PlanGenerator` utilise un calendrier fixe (semaine au lundi, fuseau GMT) : un
plan ne doit pas changer selon les réglages régionaux de l'appareil. Le même
profil produit toujours exactement le même plan, propriété testée.

Quand l'athlète déclare moins de jours disponibles que de séances, le générateur
**réutilise ses jours** plutôt que d'en inventer un qu'il a explicitement exclu.

### 9. Le harnais de tests UI doit purger tout le schéma

Découvert en exécutant la suite : `--uitest-reset` ne supprimait que les cinq
modèles d'origine. Les entités ajoutées en phase 1 et 3 (profil, mesures,
check-in, plans, adaptations) survivaient d'un test à l'autre et rendaient la
suite dépendante de son ordre d'exécution.

`UITestSupport.wipedModelNames` est désormais comparé au schéma courant par un
test unitaire : ajouter un modèle sans l'ajouter à la purge fait échouer la
suite immédiatement.

## Conséquences

- Toute nouvelle règle de progression s'ajoute dans `ProgressionRule` +
  `ProgressionEngine`, jamais dans une vue.
- Une adaptation appliquée sans passer par `ProgressionReview` serait
  intraçable et non annulable : c'est le seul point d'entrée.
- Le planning (`ScheduledWorkout`) et l'historique (`CompletedSession`) restent
  deux choses distinctes : déplacer ou marquer une séance planifiée ne touche
  jamais une séance terminée.

## Limites connues

- Le recalcul automatique des semaines futures après une séance manquée n'est
  pas livré : l'utilisateur déplace ou marque les séances lui-même.
- Le test de 1RM guidé (protocole et avertissement de sécurité) reste à livrer.
- `PlateauDetector` est implémenté et testé dans le moteur, mais n'est pas
  encore exposé dans l'interface.
