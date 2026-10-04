# 0017 — Séance au poignet : miroir, commandes et séance Santé de la montre

Date : 04/10/2026
Statut : accepté

## Contexte

Le lot 7 de `docs/roadmap/10-inspirations-open-source.md` fait de
l'application Watch une vraie séance au poignet (idées d'Ischys, MIT ; Iron et
Skulpt, GPL, idées seulement). Jusqu'ici la montre enregistrait des séries
sous un nom figé « Exercice » et les envoyait en file d'attente
(décision 0009). Depuis les lots 5 et 6, l'iPhone sait suivre une séance
Santé en direct et exécuter des commandes venues de l'extérieur de
l'interface (`LiveWorkoutRegistry`, `LiveWorkoutActions`).

## Décisions

### 1. L'iPhone reste la source de vérité ; la montre est un miroir

Quand une séance tourne sur l'iPhone, la montre affiche l'état qu'il lui
pousse à chaque transition (`WatchMirrorState`, `Shared/WatchMirror.swift`) :
exercice, série n/N, charge × répétitions prévues dans l'unité du profil,
série suivante, repos en décompte puis en dépassement. Cet état reprend
**exactement** celui de la Live Activity (`liveActivityState`) : un seul
calcul, donc la montre, l'écran verrouillé et l'application ne peuvent pas se
contredire. Il voyage dans le contexte d'application (la montre le retrouve à
son lancement) et en message immédiat quand elle est joignable. Une séquence
strictement croissante écarte un état arrivé en retard.

### 2. Les commandes passent par le chemin des boutons, ou ne passent pas

« Valider la série » (charge et répétitions ajustées à la Digital Crown),
« Passer le repos », « +30 s » et « Passer l'échauffement » sont des
commandes `WatchCommand` envoyées par `sendMessage`, **uniquement si l'iPhone
est joignable**. Injoignable : la commande est refusée sur la montre avant
l'envoi, et l'état affiché ne bouge pas. Une commande différée s'appliquerait
à un état qui a changé ; aucune n'est donc mise en file d'attente.

Sur l'iPhone, `WatchCommandHandler` les exécute sur **le** coordinateur de
la séance (`LiveWorkoutActions.currentState`, décision 0016) : `logSet`,
`RestTimer.skip`, `RestTimer.addThirtySeconds`, `finishWarmup`. La décision
(`WatchCommandPolicy`, pure) reprend les gardes du lot 6 : identité de la
série affichée, série classique dont la charge et les répétitions sont
connues, valeurs bornées. La réponse porte toujours l'état à jour, acceptée
ou refusée ; la montre n'affiche jamais ce qu'elle suppose. Côté montre, une
seule commande à la fois (`WatchMirrorMachine`) : un double tap pendant
l'envoi n'envoie rien, et un tap sur un état périmé est refusé par l'iPhone
(« La séance a avancé »).

### 3. Démarrer depuis la montre démarre sur l'iPhone

« Prochaine séance » et « Séance libre » démarrent la séance **sur
l'iPhone** s'il est joignable — la prochaine séance du programme actif, celle
du bouton « Commencer » de l'accueil, sans l'écran de préparation (le
check-in reste facultatif) — puis la montre bascule en miroir. Une seule
séance active à la fois : la commande est refusée s'il y en a déjà une.

iPhone injoignable : le mode autonome de la phase 7 reste disponible, mais
l'exercice est choisi dans la liste des exercices de la prochaine séance,
envoyée dans le contexte (`WatchPlanSummary`) — plus de nom figé. La séance
part en file d'attente et rejoint l'historique une seule fois (décision 0009).

### 4. Une séance Santé, un seul hôte

Règle (`HealthWorkoutCoordination`, moteur, testée) :

1. Santé désactivée, refusée ou absente dans Muscu : personne n'enregistre en
   direct (rien ne change).
2. Montre appairée **et** Muscu installé dessus : la **montre** est l'hôte —
   c'est elle qui porte le capteur. L'iPhone la lance dans la séance
   (`HKHealthStore.startWatchApp`, mode d'arrière-plan
   `workout-processing`) ; une séance démarrée depuis la montre y est
   enregistrée d'emblée. La montre partage sa séance avec l'iPhone
   (`startMirroringToCompanionDevice`, iOS 17+), qui la retient.
3. Sinon, ou si la montre n'a pas pu être lancée : l'iPhone (iOS 26+,
   décision 0015).
4. Sinon : écriture après coup.

L'hôte est choisi au démarrage et ne change plus : basculer en cours de
route laisserait deux entraînements partiels. La montre ne démarre une
séance Santé que pour la séance que l'iPhone lui a confiée
(`WatchHealthPlanner`), jamais de sa propre initiative pendant une séance
tenue par l'iPhone.

Fin : l'iPhone termine la séance Muscu, pose le marqueur de la décision 0015
(avec l'hôte et l'heure de la demande) et envoie `finish` à la montre
(message immédiat **et** file d'attente ; la montre ne traite qu'une fois).
La montre termine l'entraînement avec l'identifiant de la séance dans les
métadonnées et renvoie son identifiant et le cardio. L'iPhone le relie
(`HealthWorkoutLink`, source `watch`) et range FC moyenne / min. / max. et
kcal dans la `CompletedSession`. Tant que la confirmation est attendue, la
synchronisation n'écrit pas la séance.

Les cas limites gardent la règle « jamais deux entraînements » :

- la montre répond qu'elle n'a rien enregistré (autorisation refusée sur la
  montre, séance jamais démarrée) : la séance est écrite après coup aussitôt ;
- pas de réponse sous 15 minutes : la séance est écrite après coup ; si la
  montre confirme plus tard, son entraînement **remplace** celui écrit après
  coup ;
- confirmation rejouée : rien n'est refait (lien identique reconnu) ;
- séance supprimée entre-temps : l'entraînement de la montre est retiré ;
- abandon : `discard` à la montre, rien n'est enregistré ; séance trop
  courte : idem (même seuil que la synchronisation).

Mode autonome avec Santé active : la montre enregistre elle-même
l'entraînement et joint son identifiant et le cardio à la séance transférée ;
l'iPhone le relie à l'import, sans jamais le réécrire.

L'autorisation Santé de la montre n'est demandée qu'au démarrage d'une
séance, et seulement si l'utilisateur a activé Santé dans Muscu sur l'iPhone
(décision 0009) ; un refus laisse la séance continuer sans cardio.

### 5. Repos au poignet

Vibration aux trois dernières secondes et à la fin du repos
(`RestHapticTracker`, pur) : chaque signal une seule fois par repos, aucune
rafale après une suspension, rien plus de dix secondes après la fin, et un
« +30 s » relance le compte. Pendant une séance Santé, l'application reste
active poignet baissé ; sans séance Santé, watchOS peut la suspendre et la
vibration n'est garantie qu'écran allumé.

### 6. Complication

Extension WidgetKit de la montre (`MuscuWatchWidgets`, rectangulaire et
circulaire) : séance en cours (exercice, série, décompte du repos tenu par le
système) ou prochaine séance. Comme les widgets iPhone, elle lit un petit
instantané déposé par l'application de la montre dans son groupe
d'applications (`WatchComplicationStore`), rechargé seulement quand ce qu'il
affiche change.

## Correction au passage

La montre encodait les dates de la séance transférée en secondes alors que
l'iPhone les lisait en ISO 8601 : une séance faite à la montre seule était
rejetée comme « illisible ». La montre encode désormais en ISO 8601, et
l'iPhone accepte les deux formats (séances déjà en file d'attente).

## Ce qui n'a pas pu être vérifié

Compilé (montre, iPhone, Mac Catalyst) et testé (moteur, tests unitaires),
application Watch construite pour le simulateur. Sans iPhone et Apple Watch
appairés réels, rien de ce qui suit n'est démontré :

- la livraison des messages, du contexte et de la file d'attente entre deux
  appareils, et les refus quand l'iPhone devient injoignable ;
- `startWatchApp` qui lance la montre dans une séance, le partage
  (`startMirroringToCompanionDevice`) et sa réception sur l'iPhone ;
- la séance Santé de la montre : fréquence cardiaque réelle, kcal, entraînement
  enregistré et relié, confirmation tardive, reprise après un arrêt brutal ;
- l'autorisation Santé demandée sur la montre ;
- la Digital Crown, le retour haptique et la vibration poignet baissé ;
- la complication sur un vrai cadran et son rechargement.
