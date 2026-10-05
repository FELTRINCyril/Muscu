# 0020 — Live Activity sans « Ouvrir », fin du repos sans dépassement

Date : 05/10/2026
Statut : accepté — remplace les points 2 et 4 de la décision 0016

## Contexte

Retours d'une vraie séance sur l'iPhone (les boutons « Passer » et « +30 s »
fonctionnaient : le mécanisme des intents est sain) :

- pendant une série, la Live Activity ne proposait qu'« Ouvrir », inutile
  puisqu'un tap sur le bandeau ouvre déjà l'application ; « Valider » manquait
  justement là où il sert (pyramide, charge inconnue…) ;
- à la fin du repos, un bandeau « Repos dépassé » apparaissait, et l'écran
  verrouillé restait figé quelques secondes avant de changer.

La latence venait de la conception : le contenu affiché pendant le repos
n'était juste qu'après une mise à jour (passage au dépassement au redessin
déclenché par la péremption, que le système diffère à sa guise).

## Décisions

### 1. Jamais de bouton « Ouvrir »

Le bandeau entier ouvre l'application (`widgetURL`). Une étape qui ne se
valide pas sans saisie (série au temps ou à la distance, intervalles, EMOM,
AMRAP, For Time) n'a simplement pas de bouton de validation.

### 2. « Valider » = ce que la saisie pré-remplit

`LiveActivityPlanning.quickLogProposal` (moteur, testé) reçoit la charge et
les répétitions que l'écran de saisie pré-remplit (`prefillWeight`,
`prefillReps`) et les rend telles quelles pour une série classique, un
dropset, un rest-pause ou des myo-reps (paliers compris). Une pyramide
valide les répétitions du palier courant au poids du corps, par
`logPyramidStep` : les répétitions sont fixées par le palier à la création ;
pour en changer, on ouvre l'application.

Charge inconnue : l'écran de saisie laisse alors le champ à zéro (aucune
charge suggérée, 1RM manquant). « Valider » enregistre ce même zéro, comme le
bouton de l'application ; l'utilisateur corrige dans l'historique. On
préfère un bouton qui fait exactement ce que fait l'application à un bouton
qui disparaît sans explication. La règle de 0016 « jamais validé à zéro »
est donc abandonnée ; la valeur enregistrée est affichée sur le bandeau
(« × 10 ») avant le tap.

Échauffement guidé : sur l'écran « Échauffement libre », « Valider » coche
le premier palier de montée en charge non coché (`logWarmupSet`, comme la
case de l'écran). Les cases de l'écran sont désormais lues dans les séries
enregistrées, pour refléter une validation venue de l'écran verrouillé. Les
écrans de choix et de cardio n'ont rien à valider.

La protection contre le double tap ne change pas (`slotKey` : séance,
phase, position, nombre de séries enregistrées). La montre suit la même
règle (même proposition, même garde).

### 3. Pendant un repos : la série suivante, déjà validable

La position avance au moment de la validation, avant le repos : pendant le
repos, l'activité affiche donc déjà la série qui le suit et son « Valider ».
Valider pendant le repos arrête le repos puis enregistre la série — ce que
ferait l'application avec « Passer » puis « Valider » (`logSet` appelle
`RestTimer.stopIfRunning`). Le repos réellement pris est mesuré entre les
deux validations (`ActualRest`), indépendamment du chrono.

Boutons du repos : « −15 s », « +15 s », « Passer », partout (écran de repos
de l'application, Live Activity, montre). « +30 s » disparaît.
`RestAdjustment` (moteur) borne le temps restant entre 0 et 30 min ; « −15 s »
à moins de 15 s de la fin termine le repos. Un seul intent paramétré
(`AdjustRestActivityIntent`), une seule commande montre (`adjustRest`) ; le
téléphone refuse toute autre valeur que ±15 s.

### 4. Fin du repos : pas de dépassement, pas d'attente

- `RestTimer` n'a plus d'état « dépassement » : à la fin prévue, fin et
  durée sont effacées, l'écran de repos se ferme sans animation et l'écran
  de saisie de la série suivante, déjà en place dessous, est visible
  aussitôt. La notification de fin n'est pas présentée application ouverte.
- Le contenu de l'activité pendant un repos est juste SANS mise à jour : la
  série suivante et « Valider » y sont déjà, le décompte
  `Text(timerInterval:countsDown:)` est tenu par le système et s'arrête à
  0:00. La fin ne fait que retirer la ligne du repos.
- L'application pousse cette mise à jour dès qu'elle le peut : chaque
  changement du chrono (nouveau repos, ajustement, « Passer », fin) passe
  par `onStateChange`, qui met à jour la Live Activity et la montre, écran du
  déroulé affiché ou non (application en arrière-plan pendant une séance
  Santé, bouton de la Live Activity). Application suspendue, la péremption à
  la fin du repos déclenche le redessin système ; une fin passée vaut « pas
  de repos » (`WorkoutActivityState.restPhase`).

### 5. Copie de secours : le vrai fichier

`StoreRecovery.storeURL` recomposait `Application Support/default.store` de
l'application, alors que SwiftData range la base dans le conteneur du groupe
d'applications. Elle lit désormais l'URL de la configuration par défaut
(`ModelConfiguration().url`), celle que reçoit le `ModelContainer` ; un test
compare les deux.

## Ce qui n'a pas pu être vérifié

Compilé et testé (moteur, tests unitaires, aperçus), non exécuté sur un
appareil : le rendu réel sur l'écran verrouillé et dans la Dynamic Island,
le délai du redessin système à la péremption, la mise à jour poussée en
arrière-plan pendant une séance Santé.
