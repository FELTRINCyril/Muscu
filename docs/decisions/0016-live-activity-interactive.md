# 0016 — Live Activity interactive, dernière séance et Siri

Date : 04/10/2026
Statut : accepté — points 2 et 4 remplacés par la décision 0020 (plus de
bouton « Ouvrir », « Valider » avec les valeurs pré-remplies, ±15 s, plus de
dépassement)

## Contexte

Le lot 6 de `docs/roadmap/10-inspirations-open-source.md` rend la Live
Activity interactive (idée d'Ischys, MIT), ajoute un widget « Dernière
séance » et des intents Siri sur les records et la fin de séance (idée
d'Iron, GPL : aucun code repris). Les règles de la décision 0009 restent :
les widgets lisent un instantané, la Live Activity ne survit pas à la séance.

## Décisions

### 1. Un bouton de la Live Activity est un bouton de l'application

Les boutons sont des `LiveActivityIntent` déclarés dans `Shared/` (compilés
dans l'application et dans l'extension, le bouton doit connaître le type),
mais exécutés dans le processus de l'application, éventuellement relancée en
arrière-plan. L'application installe au lancement le gestionnaire
(`LiveWorkoutActions`) ; dans l'extension il reste vide.

Le gestionnaire agit sur **le** coordinateur de la séance (`WorkoutState`) :
celui que l'interface affiche, sinon la séance persistée reprise exactement
comme au lancement. `LiveWorkoutRegistry` retient ce coordinateur jusqu'à la
fin ou l'abandon, et `WorkoutState.resumeOrAdopt` le rend à l'interface : il
n'y a jamais deux coordinateurs — ni deux chronos — pour une même séance.
« Valider la série » appelle `logSet`, « Passer » et « +30 s » le même
`RestTimer` que l'écran de repos.

### 2. On ne valide d'un tap que ce qui est entièrement connu

`LiveActivityPlanning.quickLogProposal` (moteur, testé) n'accepte qu'une série
classique poids × répétitions, hors palier et hors échauffement, dont la
charge et les répétitions proposées sont connues — les mêmes que la saisie
pré-remplit. Au poids du corps, zéro est une charge ; ailleurs, une charge
inconnue n'est jamais validée à zéro. Sinon le bouton devient « Ouvrir ».

Le bouton porte l'identité de la série affichée (séance, position, nombre de
séries enregistrées). Un double tap ou une activité en retard sur
l'application ne valide donc jamais une autre série : l'activité est
seulement remise à jour.

### 3. Charge prévue sur l'écran verrouillé

La phase 7 n'y montrait aucune charge. La charge × répétitions prévue y
figure désormais, parce que le bouton « Valider » doit dire ce qu'il
enregistre. Elle n'apparaît que pendant une séance démarrée par
l'utilisateur ; ni poids de corps, ni note, ni commentaire n'y figurent.

### 4. Le dépassement de repos sans application active

L'activité porte la fin du repos, y compris pendant le dépassement. Pendant
un repos, sa date de péremption est la fin prévue : le système la redessine
à ce moment et elle passe du décompte au dépassement « +0:12 », compté par
le système, borné à une heure comme dans l'application. Hors repos, la
péremption de quatre heures s'applique.

Au lancement, l'activité restée ouverte n'est fermée que s'il n'y a plus de
séance à reprendre : ses boutons ont pu relancer l'application, elle décrit
alors la séance en cours.

### 5. Les liens ne font que naviguer

`muscu://workout`, `muscu://start-next` et `muscu://replay?session=…` peuvent
venir de n'importe quelle application. Ils ne déclenchent que ce que
feraient les boutons de l'accueil : reprendre la séance, ouvrir l'écran de
préparation, ou **proposer** de refaire une séance (confirmation, et refus
si une séance est déjà en cours). Un lien inconnu est ignoré.

### 6. Siri termine et abandonne par le même chemin

`WorkoutState.complete` regroupe ce que faisait le récapitulatif (historique,
widgets, Santé, records typés) ; le récapitulatif et `FinishWorkoutIntent`
l'appellent tous deux. Les deux intents d'écriture demandent une
confirmation (l'abandon est marqué destructif), revérifient la séance après
la confirmation, et refusent proprement sans séance ou, pour terminer, sans
aucune série de travail (`SessionEndCheck`). Le déroulé affiché se ferme de
lui-même. Les records de référence (1RM saisi) détectés à la fin restent
soumis à confirmation dans l'application : Siri ne les applique pas.

## Ce qui n'a pas pu être vérifié

Compilé, testé (moteur et tests unitaires) et construit pour Mac Catalyst,
mais pas exécuté sur un appareil :

- les boutons sur l'écran verrouillé et dans la Dynamic Island, l'application
  relancée en arrière-plan par un bouton ;
- le redessin à la péremption (passage au dépassement) sans application
  active ;
- Siri : reconnaissance des phrases, confirmation vocale, vue de réponse ;
- les liens des widgets posés sur un vrai écran d'accueil.
