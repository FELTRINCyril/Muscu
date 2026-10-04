# 0009 — HealthKit, widgets, Live Activity et application Watch

Date : 14/09/2026
Statut : accepté

## Contexte

La phase 7 fait sortir Muscu de son bac à sable : l'app Santé, l'écran
d'accueil, l'écran verrouillé et une seconde application sur la montre. Le
jalon est précis : « une séance Watch rejoint l'historique une seule fois et
la Live Activity expire proprement ».

## Décisions

### 1. Une séance n'est écrite dans Santé qu'une seule fois

La protection contre les doublons vit dans `HealthSyncPlanner`, côté moteur,
sans rien connaître de HealthKit. Une séance qui porte déjà un lien vivant
n'est jamais réécrite, quel que soit le nombre de passages. Un test rejoue la
synchronisation trois fois de suite et vérifie qu'un seul entraînement existe.

Deux règles complètent la déduplication :

- une séance supprimée dans Muscu retire son entraînement de Santé — le
  laisser survivre à sa source serait un mensonge ;
- un échec d'écriture ne laisse **aucun lien** derrière lui. Un lien vers un
  entraînement inexistant ferait croire à un doublon protégé, et la séance ne
  serait jamais réécrite.

### 2. L'autorisation est expliquée avant d'être demandée

L'écran Santé dit ce que Muscu écrira, ce qu'il lira, **et ce qu'il ne lira
pas** (ni fréquence cardiaque, ni sommeil, ni activité). La demande système
n'est déclenchée que par l'activation de l'interrupteur — jamais par la
synchronisation, jamais au lancement. Un test vérifie que la synchronisation
ne demande rien d'elle-même.
*Complété par la décision 0015 : la fréquence cardiaque et l'énergie active
sont désormais lues, uniquement sur l'intervalle des séances.*

Un refus n'active rien, ne supprime rien, ne bloque rien. Un appareil sans
Santé n'est pas traité comme un refus : c'est une indisponibilité, et elle est
dite comme telle.

Désactiver le partage **ne retire pas** ce qui a déjà été écrit : ces
entraînements appartiennent à l'app Santé. Les effacer sans le demander serait
une suppression décidée à la place de l'utilisateur, dans une autre
application.

### 3. Les widgets lisent un instantané, jamais la base

Un widget qui ouvrirait le store SwiftData depuis un autre processus hériterait
de ses migrations et de ses verrous — pour afficher trois lignes.
L'application écrit donc un petit résumé dans le groupe d'applications après
chaque changement qui le concerne, et le widget le lit.

Ce fichier sort du conteneur privé : il ne contient donc **que ce que le
widget montre déjà**. Un test vérifie qu'un prénom, un poids et une note de
séance n'y apparaissent pas.

Les indicateurs viennent de `TrainingAnalytics`, comme les graphiques : un
widget ne doit jamais contredire l'écran Progression parce qu'il aurait refait
le calcul autrement.

### 4. La Live Activity ne survit pas à la séance

Elle se termine à la fin **et** à l'abandon : les deux sorties la font
disparaître. Elle porte une date de péremption de quatre heures, et
l'application ferme au démarrage toute activité restée ouverte après un arrêt
brutal. Une Live Activity affichée toute la nuit après une séance abandonnée
serait un défaut visible sans même ouvrir l'application.
*Complété par la décision 0016 : l'activité devient interactive, et elle
n'est fermée au démarrage que s'il ne reste aucune séance à reprendre.*

Détail d'implémentation qui a demandé un détour : `Activity` est manipulé par
ActivityKit hors de l'acteur principal. Le contrôleur ne retient donc que
l'**identifiant** de l'activité et la retrouve dans un contexte non isolé
quand il doit la mettre à jour.

### 5. L'identifiant d'une séance Watch est frappé à la montre

C'est ce qui tient le jalon. L'identifiant généré sur la montre devient
l'identifiant de la `CompletedSession`, qui est unique dans le modèle. Rejouer
un transfert — après une coupure, une relance, une réinstallation — ne peut
donc pas créer de doublon. Un test rejoue le même transfert dix fois.

Les envois passent par `transferUserInfo`, qui met en file d'attente : une
séance faite hors de portée de l'iPhone part dès qu'il redevient joignable, au
lieu d'être perdue. La montre affiche ce qui reste à envoyer.

La montre ne reçoit ni historique, ni mesures, ni notes : le même instantané
que les widgets, et rien d'autre.

## Ce qui a été réellement exécuté

- HealthKit, widgets et Live Activity : compilés et testés sur le simulateur
  iOS, qui embarque l'app Santé.
- Application Watch : **installée et lancée** sur un simulateur Apple Watch
  Series 11, affichant son état vide.

## Ce qui n'a pas pu être vérifié

Le jalon demande explicitement une vérification **sur appareils réels**. Rien
de ce qui suit n'est démontré :

- l'autonomie pendant une séance Watch ;
- le comportement en arrière-plan et la livraison différée d'un transfert
  quand l'iPhone est réellement hors de portée ;
- l'expiration de la Live Activity sur l'écran verrouillé d'un vrai iPhone ;
- HealthKit avec des données de santé réelles et plusieurs sources d'écriture ;
- le rendu des widgets posés sur un vrai écran d'accueil.

Cela demande une équipe Apple Developer, un iPhone et une Apple Watch appairés.
La case de la phase 7 reste donc partielle.
