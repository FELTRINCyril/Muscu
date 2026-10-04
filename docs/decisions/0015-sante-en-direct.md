# 0015 — Santé en direct, cardio, effort et mesures importées

Date : 04/10/2026
Statut : accepté

## Contexte

Le lot 5 de `docs/roadmap/10-inspirations-open-source.md` approfondit
l'intégration Santé (inspirée de UpLift, MIT) : séance Santé en direct sur
iPhone, cardio de la séance, note d'effort écrite dans Santé, import de la
masse grasse et du tour de taille. Tout reste facultatif (décision 0009) :
Santé désactivée, refusée ou absente, l'application se comporte comme avant.

## Décisions

### 1. La séance en direct remplace l'écriture après coup, par le lien

`HKWorkoutSession` + `HKLiveWorkoutBuilder` n'existent sur iPhone qu'à partir
d'iOS 26 (et jamais sur Mac Catalyst). L'application reste déployée en iOS 18 :
`LiveHealthWorkoutController` vérifie `#available(iOS 26.0, *)` et exclut
Catalyst à la compilation ; ailleurs, la séance est écrite après coup comme
avant.

L'anti-doublon reste celui de la décision 0009 : à la fin, l'entraînement
enregistré en direct est relié à la `CompletedSession` par un
`HealthWorkoutLink` (`sourceRaw = "iphone-live"`), et le planificateur le voit
comme déjà écrit. Entre « Terminer » et la finalisation du builder, un
**marqueur persistant** (`UserDefaults`, identifiants seulement) exclut la
séance du planificateur : aucune synchronisation intercalée ne peut l'écrire
une seconde fois. Si la finalisation échoue, le marqueur est effacé et la
séance redevient une séance ordinaire, écrite après coup.

Si un entraînement avait malgré tout été écrit après coup (reprise tardive),
l'entraînement en direct, plus riche, le remplace.

### 2. Reprise après un arrêt brutal : décidée par le moteur

Au lancement, `recoverActiveWorkoutSession` peut rendre une séance Santé
restée ouverte. `LiveWorkoutRecovery.decide` (moteur, testé) tranche selon le
marqueur et la base : séance Muscu encore en cours → rattachée **en pause**
jusqu'à la reprise ; séance terminée → entraînement terminé et relié ; sinon
(abandon, séance inconnue) → abandonnée sans rien enregistrer.

Muscu n'a pas de pause globale de séance : « Reprendre plus tard » met la
séance Santé en pause, la reprise du déroulé la relance. L'abandon (dans le
déroulé ou depuis l'accueil) appelle `discardWorkout`.

### 3. Cardio : jamais zéro à la place d'une absence

Le cardio vient du builder en direct, ou à défaut d'une lecture dans Santé sur
l'intervalle de la séance, limitée aux séances des 7 derniers jours sans
aucune valeur cardio (`HealthCardioBackfill`). Une valeur connue n'est jamais
écrasée. Les valeurs hors bornes (20-300 bpm, 0-100 000 kcal, mêmes bornes que
l'import d'archive) sont écartées. Sans capteur, la carte en séance n'affiche
pas de fréquence. Ces valeurs restent hors synchronisation iCloud
(décision 0011) ; leur ajout ne touche donc pas `updatedAt`. Pas de zones
cardiaques (écarté dans le plan).

### 4. Note d'effort : l'échantillon, pas l'entraînement

La note 1-10 de Muscu passe telle quelle sur l'échelle `workoutEffortScore`
de Santé (mêmes bornes, mêmes paliers), reliée par
`relateWorkoutEffortSample` (iOS 18). Le lien retient désormais les horaires
et la note écrits (`writtenStartDate`, `writtenDurationSeconds`,
`writtenEffortRating`, `effortSampleIdentifier` — champs facultatifs du modèle
v7 vivant, non publiés, non synchronisés).

Conséquence sur la règle du lot 4 (« séance corrigée après écriture →
entraînement remplacé ») : quand les horaires écrits sont connus et
inchangés, seule la note a pu changer ; l'ancien échantillon d'effort est
retiré et le nouveau relié, **sans remplacer l'entraînement** — qui peut
porter la fréquence cardiaque d'une séance en direct. Un lien antérieur, sans
horaires mémorisés, garde l'ancienne règle. Un refus du seul type « effort »
n'est pas une erreur : la note reste dans Muscu.

### 5. Mesures importées : identifiant d'échantillon, lecture seule

Le poids, la masse grasse et le tour de taille sont importés par interrupteur,
de façon incrémentale (fenêtre de 90 jours au premier import, recouvrement de
7 jours ensuite), et dédoublonnés d'abord par `healthSampleUUID` — y compris
contre une mesure supprimée dans Muscu, pour ne pas défier la suppression —
puis, pour les mesures sans identifiant, par proximité de date et de valeur.
La symétrie existante est conservée : seul le poids peut être écrit dans
Santé ; la masse grasse et le tour de taille sont seulement lus.

La masse maigre est écartée : le modèle n'a pas de type de mesure pour elle,
et une valeur de type inconnue serait refusée par l'import d'archive d'une
version antérieure.

### 6. Nouveaux types d'autorisation : expliqués, jamais imposés

Une autorisation accordée avant le lot 5 ne couvre pas le cardio, l'effort ni
les mesures. `statusForAuthorizationRequest` le détecte ; l'écran Santé
l'explique et propose un bouton. La demande système part de ce bouton ou de
l'activation du partage, jamais d'une synchronisation ni du lancement.

## Ce qui n'a pas pu être vérifié

Le simulateur ne fournit ni Apple Watch portée, ni capteur cardiaque : la
séance en direct, la fréquence cardiaque reçue, la reprise après un arrêt
brutal et l'enregistrement en arrière-plan écran verrouillé (un mode
d'arrière-plan « workout processing » pourrait être exigé sur iPhone) restent
à vérifier sur un iPhone sous iOS 26 avec une montre ou un capteur.
