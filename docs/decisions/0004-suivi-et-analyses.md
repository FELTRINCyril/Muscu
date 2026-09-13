# 0004 — Suivi, mesures et analyses

Date : 2026-09-13
Statut : accepté
Phase de la roadmap : 4 (profil, mesures et analyses)

## Contexte

`ChartsView` recalculait ses propres formules : `poids × répétitions` pour le
tonnage, Epley appliqué à toute série chargée. Ces calculs ignoraient les types
de charge introduits en phase 1 — une traction assistée alimentait la courbe de
1RM, un exercice au poids du corps comptait pour zéro kilo. Deux écrans
affichant « le tonnage » ne montraient donc pas la même chose.

## Décisions

### 1. Un seul endroit calcule, les vues affichent

`MuscuEngine/Analytics/TrainingAnalytics` porte toutes les agrégations :
volume et séries difficiles par muscle et par semaine, tonnage, répétitions,
durée, densité de travail, séries par exercice, fréquence, séries consécutives,
adhérence, répartition musculaire, déséquilibres, comparaison de périodes.

Les formules de charge viennent de `SetMetrics`, jamais réécrites.
`AnalyticsBridge` est le **seul** point de conversion SwiftData → moteur : une
vue ne peut plus diverger d'une autre sans changer ce pont.

### 2. « Zéro » et « donnée manquante » ne sont pas la même chose

`MeasuredTotal` transporte la valeur **et** le nombre de séries dont la donnée
manquait. Un tonnage de 0 kg avec 12 séries inconnues ne veut pas dire « aucun
travail » mais « poids de corps non renseigné », et chaque graphique le dit.

Conséquences appliquées partout :

- la densité de travail est `nil` — pas 0 — si la durée est inconnue ou le
  tonnage incomplet ;
- l'adhérence au planning est `nil` quand rien n'était planifié ;
- une séance sans valeur exploitable est **absente** d'une courbe plutôt que
  tracée à zéro, et le nombre de séances écartées est affiché ;
- un objectif sans donnée observée s'affiche « pas encore mesurable ».

### 3. Une série n'est « difficile » que si un signal le dit

Compter toutes les séries de travail comme difficiles reviendrait à confondre
« pas de donnée » et « facile ». Une série est difficile si l'effort déclaré est
à 2 répétitions en réserve ou moins, ou si l'échec est marqué. Le nombre de
séries **sans effort saisi** est remonté séparément.

### 4. Chaque graphique dit son unité, sa période et sa formule

`ExerciseMetric` porte son symbole d'unité et une description de sa formule,
affichée sous le graphique. Le sélecteur de période est toujours visible : un
indicateur sans période n'est pas interprétable.

### 5. Accessibilité : le graphique est masqué, l'alternative est lue

Un nuage de points n'est pas lisible par VoiceOver. Chaque carte marque son
graphique `accessibilityHidden` et expose une **alternative textuelle**
décrivant la série (nombre de points, valeurs de début et de fin, période).
C'est la même information, sous une autre forme — pas un résumé appauvri.

### 6. Les déséquilibres sont descriptifs

Un muscle est signalé quand son volume hebdomadaire passe sous la moitié de la
médiane des muscles travaillés, avec au moins trois muscles suivis. Le texte dit
explicitement qu'il s'agit d'un écart de volume observé, pas d'un jugement sur
le programme. Les comparaisons de périodes énoncent des chiffres, jamais une
causalité.

### 7. Objectifs : factuels, jamais culpabilisants

`GoalEvaluator` produit un avancement et une phrase neutre. Un test vérifie
qu'aucun mot de reproche (« doit », « raté », « échec », « faut ») n'apparaît
dans ces phrases. Un objectif en baisse exige un **point de départ** figé à la
création, sans lequel aucun avancement n'est exprimable. Les objectifs portant
sur le corps affichent un rappel : l'application n'évalue pas la santé et ne
donne aucun conseil nutritionnel.

Mettre en pause ou archiver un objectif ne réécrit jamais l'historique.

### 8. Export CSV : lisible ailleurs, et inoffensif

Quatre jeux séparés (séances, séries, mesures, check-in), séparateur virgule,
dates ISO 8601, nombres au point décimal, **toujours en unité canonique**
(kg, cm). Les valeurs absentes restent vides, jamais converties en zéro.

Un champ commençant par `=`, `+` ou `@` est préfixé d'une apostrophe et cité :
une note utilisateur ne doit pas devenir une formule exécutée à l'ouverture du
fichier dans un tableur.

### 9. La suppression est vérifiable et complète

`DataDeletion` supprime par catégorie ou en totalité et **renvoie ce qui a
réellement été supprimé**, affiché à l'utilisateur. `coveredModelNames` est
comparé au schéma courant par un test : un modèle oublié rendrait la promesse
« tout supprimer » mensongère.

### 10. Les lectures sont bornées

`AnalyticsBridge` charge au plus 500 séances, les plus récentes. Un historique
de plusieurs années n'a pas à être chargé en entier pour afficher douze
semaines. Un test vérifie que 400 séances × 4 séries restent traitées en moins
de deux secondes.

## Conséquences

- Toute nouvelle vue qui affiche un indicateur passe par `TrainingAnalytics` et
  `AnalyticsBridge`. Recalculer localement serait une régression.
- Ajouter un modèle au schéma impose de l'ajouter à `DataDeletion` **et** à la
  purge des tests UI : deux tests échouent sinon.
- Une vue affichée comme SEGMENT (et non poussée) ne doit pas poser de
  `navigationTitle` : elle écraserait celui de l'onglet. Défaut trouvé et
  corrigé sur `MeasurementsView`.

## Limites connues

- HealthKit est volontairement reporté en phase 7, comme prévu au plan
  d'exécution, pour ne pas demander de permissions pendant la stabilisation.
- Les photos de progression ne sont pas encore implémentées : elles supposent un
  magasin d'actifs séparé, compressé et exclu des exports par défaut.
- Le calendrier de chaleur (`sessionsPerDay`) est calculé par le moteur et testé,
  mais pas encore affiché.
