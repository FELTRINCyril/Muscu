# 0018 — Doublons fusionnés, exercices habituels, indice de force, sauvegardes automatiques

Date : 04/10/2026
Statut : accepté

## Contexte

Le lot 8 de `docs/roadmap/10-inspirations-open-source.md` clôt le plan :
fusion des exercices en double, exercices habituels en tête, indice de force
et records du mois, statistiques par exercice, lien de démonstration
personnel, sauvegardes automatiques et rejeu de la progression. Aucun
attribut n'est ajouté : `CustomExercise.mergedIntoExerciseId` et
`ExerciseLibraryEntry.demoURL` existent depuis la v7 (décision 0011).

## Décisions

### 1. Fusion : redirection, réaffectation complète, une sauvegarde

La détection (`DuplicateExercises`, moteur) ne fait que proposer des paires,
chacune confirmée à la main. Trois raisons, de la plus sûre à la plus
incertaine : même nom normalisé (`TextMatching`, nom FR ou EN du catalogue)
avec matériel compatible ; même nom d'import — Muscu n'a pas d'identifiant
d'import d'exercice, la convention « Exercice (Matériel) » d'`ExerciseNaming`
en tient lieu ; noms proches (similarité ≥ 0,8 ou mots inclus, au moins deux)
avec matériel et muscles compatibles. Un matériel connu différent n'est
jamais rapproché par le nom. Deux exercices du catalogue ne forment jamais de
paire ; le catalogue est toujours conservé, sinon l'exercice personnalisé qui
a le plus d'historique (l'utilisateur peut inverser). Trois paires au plus
par exercice, pour qu'un nom générique ne rapproche pas le catalogue entier.

`ExerciseMergeService.merge` réécrit, dans le contexte puis en **une**
sauvegarde : séries (`exerciseId`, `plannedExerciseId`), prescriptions
(identifiant et nom), modèles (charge utile JSON), objectifs, annotations de
bibliothèque (favori OU, tags unis, lien gardé), collections, exclusions du
profil, journal d'adaptation. Records : pour chaque nature et configuration,
`ExerciseMerge.reconcile` garde le meilleur des deux — jamais de régression,
le survivant gagne les égalités ; le `PersonalBest` du doublon est supprimé
logiquement (synchronisé), l'`ExerciseRecord` du doublon fusionné par
maximum puis supprimé comme le fait l'écran Records. Le nom affiché d'une
série passée n'est pas réécrit : c'est l'instantané de la séance.

Le doublon n'est **pas supprimé** : `mergedIntoExerciseId` le masque des
listes et redirige toute référence ancienne. `applyPendingRedirects`, appelé
au lancement, après une synchronisation entrante et après un import JSON,
réécrit les références qui désignent encore un exercice redirigé (chaînes
suivies, cycles coupés). C'est ce qui rend la fusion cohérente entre
appareils sans toucher à l'immuabilité des séances synchronisées : chaque
appareil applique la redirection à ses propres données. Fusionner est refusé
pendant une séance en cours (l'instantané du déroulé désigne l'exercice) ;
la réécriture différée attend aussi la fin de la séance.

### 2. Exercices habituels

`ExerciseRanking` : score = somme, par séance contenant l'exercice, de
`2^(-ancienneté / 30 j)`. Une séance compte une fois quel que soit le nombre
de séries ; un exercice jamais pratiqué n'entre pas dans la section ;
égalités départagées par le nom. L'historique lu est borné à un an (au-delà
une séance pèse moins de 1/4000). La section est masquée pendant une
recherche ou un filtre de la bibliothèque, et suit le filtre de muscle du
sélecteur. Les favoris ne changent pas.

### 3. Indice de force et records du mois

Exercices principaux : les cinq qui ont le plus souvent un 1RM estimable sur
la période et la précédente. Indice = somme de leurs meilleurs 1RM estimés
(règles `SetMetrics` : charge réelle, plafond de répétitions réglé). Un
exercice principal sans 1RM estimable est **exclu et nommé**, jamais compté à
zéro ; sans aucune donnée l'indice est « non calculable ». La tendance compare
la même somme sur les seuls exercices présents dans les deux périodes, avec
une zone neutre de ±1 % ; « Tout » n'a pas de période précédente, donc pas de
tendance. Intervalles semi-ouverts : une séance n'appartient qu'à une période.

Records du mois : par exercice chargé du mois calendaire, meilleure charge
effective du mois / record historique (séries de travail à charge réellement
portée). Un record dépasse strictement tout l'historique antérieur ; un
premier essai n'en est pas un.

### 4. Statistiques par exercice

Force relative = meilleur 1RM estimé de la période ÷ poids de corps connu **à
cette date** (dernière pesée ou poids figé sur une séance, jamais postérieur) ;
absente si l'un manque. Aucun niveau « novice / élite » : il faudrait une
table de référence sourcée. Intensité = charge ÷ meilleur 1RM estimé connu
jusqu'à la séance de la série (jamais un 1RM futur). Charge moyenne des séries
de travail chargées ; une charge inconnue est exclue et annoncée.

### 5. Lien de démonstration

Éditable dans les deux fiches, validé par `DemoLink` à la saisie et revalidé à
l'affichage. Il s'ouvre dans le navigateur ; la recherche vidéo reste en repli.

### 6. Sauvegardes automatiques

Désactivées par défaut. Au plus une par jour calendaire
(`AutoBackupPolicy`), au passage en arrière-plan (avec une tâche d'arrière-plan
demandée au système) ou après une séance terminée. Le fichier est l'export
JSON complet existant, écrit dans `Documents/Sauvegardes` — seul contenu du
dossier Documents, rendu visible dans Fichiers par `UIFileSharingEnabled` et
`LSSupportsOpeningDocumentsInPlace`. Rotation des sept plus récentes, limitée
aux fichiers au préfixe `muscu-sauvegarde-` (un fichier déposé par
l'utilisateur n'est jamais effacé). Restaurer passe par l'import en mode
Remplacer, qui crée sa sauvegarde de sécurité et la rétablit en cas d'échec.
Un échec d'écriture est journalisé (Diagnostic) et retenté à la prochaine
occasion. Photos exclues, comme dans l'export.

### 7. Rejeu de la progression

`ProgressionReplay` (moteur) rejoue `ProgressionEngine` sur un historique
synthétique : athlète simulé déterministe (graine SplitMix64, force qui
progresse jusqu'à un plafond, mauvais jours, bruit), chaque proposition
acceptée. Les tests vérifient des invariants sur toute la trace (aucune hausse
> 10 % au-dessus de 25 kg, aucune hausse après une séance ratée, décharge
d'environ 10 % au troisième échec d'affilée, charge toujours positive) et
mesurent le taux de hausses. C'est un outil de développement : rien dans
l'application ne l'appelle.
