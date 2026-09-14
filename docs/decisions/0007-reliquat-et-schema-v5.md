# 0007 — Écarts fermés et schéma v5

Date : 13/09/2026
Statut : accepté

## Contexte

Six éléments spécifiés dans la roadmap restaient non livrés alors que leur
phase était cochée. Ils ne relevaient d'aucune dépendance externe : c'étaient
des écarts, pas des blocages.

| Écart | Spécifié dans |
| --- | --- |
| Séries d'approche et de back-off | `02` |
| Test de 1RM guidé | `03` |
| Recalcul des séances futures | `03` |
| Photos de progression | `06` |
| Calendrier de chaleur | `06` |
| Détection de plateau exposée | `06` |

## Décisions

### 1. Une série qui ne consomme pas de prescription

`SetRole` distinguait déjà quatre rôles, mais l'interface n'en produisait que
deux. Le point délicat n'était pas la saisie : c'était de décider ce qu'une
série d'approche fait AVANCER.

Deux questions distinctes, séparées explicitement :

- `countsAsWorkingSet` — la série compte-t-elle dans le volume ? Un back-off
  oui, une approche non.
- `consumesPrescribedSet` — la série consomme-t-elle une série du programme ?
  Seul le travail.

Sans cette séparation, ajouter une approche aurait fait sauter une série de
travail sans que rien ne le dise. L'historique affiche le rôle au lieu d'un
numéro : « Série 3 » deux fois de suite serait faux.

### 2. Le test de 1RM refuse de s'inventer une référence

Le protocole est construit à partir d'une référence connue (1RM enregistré ou
record mesuré). Sans référence, ou sous 30 kg, il renvoie une liste **vide** et
l'écran explique pourquoi, au lieu de proposer une montée en charge inventée.

Une garantie tenue par le moteur : chaque tentative pèse **strictement** plus
que la précédente. Avec un incrément grossier, deux fractions voisines
s'arrondissent sur la même charge et le test perdrait son sens.

L'avertissement de sécurité est affiché **avant** le protocole, et le protocole
n'apparaît qu'après acceptation explicite. Il rappelle que l'estimation suffit
pour programmer : Muscu la privilégie, conformément à la roadmap.

Un résultat mesuré remplace l'estimation même s'il est **plus bas** : une
valeur portée vaut mieux qu'une extrapolation optimiste. Le record typé
`maxWeight`, lui, ne redescend jamais.

### 3. Le recalcul ne touche jamais une semaine entamée

Une semaine est « traitée » dès qu'une de ses séances l'est. Ces semaines sont
listées à l'écran **avant** les changements proposés : un recalcul qui
réécrirait le passé serait une perte de données silencieuse.

Pour re-dériver les multiplicateurs, il faut connaître la périodisation
d'origine. Elle n'était pas conservée : le plan stocke désormais son style et
sa fréquence de décharge. Un plan créé avant cette version le dit et ne voit
que ses **dates** réalignées — deviner un style produirait des volumes faux.

### 4. Les photos vivent hors de la base et hors des exports

Trois règles, toutes vérifiées par des tests :

1. le fichier est sur le disque, pas dans le store — une base qui grossit de
   plusieurs mégaoctets par cliché deviendrait lente à migrer ;
2. le dossier est **exclu de la sauvegarde iCloud** et les photos ne sont pas
   exportées : la roadmap demande un consentement séparé pour leur
   synchronisation, et ce consentement n'existe pas encore ;
3. supprimer une photo efface **la ligne et le fichier**. Effacer l'une sans
   l'autre laisserait soit une image orpheline sur l'appareil, soit une
   vignette cassée.

Un défaut réel a été trouvé par les tests : `UIGraphicsImageRenderer` suit par
défaut l'échelle de l'écran. Sur un appareil 3x, une image « réduite à
1 600 px » était stockée en 4 800 px — trois fois le poids voulu. L'échelle est
désormais fixée explicitement à 1.

### 5. Le calendrier de chaleur dit ce qu'il compte

Trois grandeurs au choix (séances, séries difficiles, tonnage), chacune avec sa
définition affichée sous le calendrier, l'échelle et le maximum de la période.
Une couleur sans légende n'est pas une information.

Un jour **absent** n'est pas un jour à zéro : les jours sans donnée ne sont pas
inventés. Les séries dont la charge effective est inconnue sont comptées à
part, comme ailleurs dans l'application.

### 6. Un plateau propose, il n'applique pas

L'écran affiche la fenêtre et le seuil de détection, puis deux sorties :
décharge de 10 % alignée sur les paliers réellement disponibles, ou variante
issue du même classement que les substitutions en séance. Les deux passent par
le journal d'adaptation et restent annulables. Un refus est mémorisé pour ne
pas reproposer la même chose quinze jours durant.

## Conséquences

- Schéma **v5** : le v4 a d'abord été figé (29 modèles), puis un modèle et deux
  attributs facultatifs ajoutés. Migration légère, vérifiée par un test qui
  écrit un store v4 et l'ouvre avec le schéma courant.
- La suppression « Mesures » efface désormais aussi les fichiers photos, et son
  libellé le dit.
