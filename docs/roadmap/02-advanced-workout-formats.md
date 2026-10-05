# 02 — Formats d’entraînement avancés

## Objectif

Permettre de programmer et exécuter les méthodes courantes de musculation sans
les simuler avec des notes ou des manipulations manuelles.

## Modèle commun

Une séance contient une suite ordonnée de `WorkoutNode` :

- exercice simple ;
- groupe d’exercices ;
- bloc chronométré ;
- récupération.

Un groupe possède un type, une liste ordonnée d’exercices, un nombre de tours,
un repos entre exercices et un repos entre tours. La vue d’exécution doit être
pilotée par ce modèle, pas par une succession de conditions propres à chaque vue.

## Formats obligatoires

### Classique

Conserver les fonctionnalités existantes et ajouter :

- charge externe, poids du corps, lest et assistance explicites ;
- répétitions, durée ou distance selon l’exercice ;
- tempo en quatre phases, par exemple `3-1-1-0` ;
- RPE ou RIR facultatif par série ;
- série d’échauffement, d’approche ou de travail ;
- échec musculaire marqué explicitement ;
- commentaire par série.

### Superset, triset et giant set

- Lier respectivement 2, 3 ou 4 exercices et plus.
- Exécuter A1 → A2 → … puis lancer le repos de fin de tour.
- Autoriser un repos court entre exercices et un autre entre les tours.
- Afficher le tour courant, l’exercice courant et la vue d’ensemble du groupe.
- Permettre de passer ou remplacer un seul exercice sans casser le groupe.
- Reprendre exactement au bon endroit après fermeture de l’app.

### Circuit

- Nombre de tours configurable.
- Exercices fondés sur répétitions, durée, distance ou calories.
- Transition facultative entre stations.
- Repos configurable entre les tours.
- Mode automatique ou validation manuelle de chaque station.

### Dropset

- Série initiale suivie de 1 à 5 baisses de charge.
- Baisse en kilogrammes ou pourcentage.
- Répétitions libres ou cibles par palier.
- Repos nul ou configurable entre les paliers.
- Historique conservant chaque palier et le regroupement logique.

### Rest-pause

- Série principale, micro-repos et mini-séries.
- Nombre de mini-séries ou seuil d’arrêt configurable.
- Chrono de micro-repos dédié.

### Myo-reps

- Série d’activation avec plage cible et RIR cible.
- Mini-séries avec nombre de répétitions et repos courts.
- Fin après nombre de blocs, perte de répétitions ou décision manuelle.

### Pyramides

Conserver les pyramides actuelles et ajouter :

- pyramide montante, descendante et complète ;
- charge et répétitions par palier ;
- création manuelle des paliers ;
- propositions basées sur 1RM ou maximum de répétitions ;
- repos adaptatif désactivable.

### Intervalles

Conserver 30/30, Tabata et EMOM, puis ajouter :

- E2MOM et intervalle libre ;
- nombre de rounds ;
- compte à rebours avant départ ;
- sons configurables à 3, 2, 1 et aux transitions ;
- durée totale et aperçu des segments ;
- reprise absolue après suspension.

### AMRAP, EMOM et For Time

- AMRAP mono ou multi-exercices ;
- EMOM avec contenu différent selon la minute ;
- For Time avec cap temporel ;
- tours complets et répétitions supplémentaires ;
- résultat comparable dans l’historique.

## Éditeur de séance

L’utilisateur doit pouvoir :

- créer un groupe à partir d’exercices sélectionnés ;
- déplacer un exercice dans ou hors d’un groupe ;
- réordonner les groupes et leur contenu ;
- dupliquer un groupe ;
- convertir un groupe vers un autre type lorsque compatible ;
- visualiser un résumé lisible avant d’enregistrer ;
- définir zéro seconde de repos lorsque le format l’autorise.

Éviter les écrans surchargés : afficher d’abord les options essentielles et placer
tempo, RPE/RIR, règles d’arrêt et transitions dans une section avancée.

## Runner

- Une machine à états unique doit déterminer le prochain écran.
- Chaque validation est persistée avant l’avancement visuel.
- Les chronos utilisent des dates absolues et rattrapent les segments expirés.
- L’utilisateur peut revenir corriger la dernière série tant que la séance n’est
  pas finalisée.
- Un aperçu de la séance permet de naviguer vers un exercice futur ou précédent.
- L’ajout, la suppression et le remplacement effectués pendant la séance ne
  modifient pas le programme source sans confirmation séparée.
- La Dynamic Island/Live Activity reflète le chrono actif si disponible.

## Historique et records

- Conserver le lien entre sous-séries, paliers, tours et groupe parent.
- Ne calculer un 1RM que sur des séries externes ou lestées pertinentes, entre
  1 et 12 répétitions.
- Ne pas créer de record depuis une charge d’assistance.
- Pour les circuits/AMRAP/For Time, enregistrer un record spécifique au format et
  à la configuration, pas seulement un maximum de répétitions générique.
- Afficher tonnage, densité de travail, durée sous tension et temps total lorsque
  les données sont disponibles.

## Tests obligatoires

- Progression de la machine à états pour chaque format.
- Interruption/reprise à chaque transition possible.
- Chronos expirés pendant une suspension longue.
- Ajout, retrait, remplacement et correction d’une série.
- Historique fidèle et détection de records sans faux positifs.
- Tests UI d’un superset, d’un dropset, d’un circuit et d’un For Time complets.
- VoiceOver annonce exercice, tour, série, objectif et temps restant.

## Critères d’acceptation

- Aucun format avancé ne dépend d’une convention écrite dans les notes.
- Un superset complet peut être créé, exécuté, interrompu puis repris.
- Le repos zéro est possible uniquement lorsqu’il est sémantiquement valide.
- Le récapitulatif distingue clairement exercices, tours et sous-séries.
- Les données restent compatibles avec export, iCloud et graphiques.
