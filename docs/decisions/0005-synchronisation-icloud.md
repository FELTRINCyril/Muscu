# 0005 — Synchronisation iCloud, iPad et Mac

Date : 2026-09-13
Statut : accepté (partie iCloud : **préparée, non validée** — dépendance externe)
Phase de la roadmap : 5 (iCloud, iPad et Mac)

## Contexte

L'application était mono-appareil. La roadmap demande une synchronisation
local-first, explicable, avec file d'attente persistante, conflits visibles et
aucune perte silencieuse — ainsi qu'une application universelle iPhone / iPad /
Mac.

Le conteneur CloudKit, l'équipe Apple Developer et les capacités associées sont
des **prérequis externes**. Ce document dit ce qui est fait, ce qui ne l'est
pas, et pourquoi.

## Décisions

### 1. Pas de miroir CloudKit automatique

SwiftData sait répliquer un store vers CloudKit sans code. Cette voie a été
écartée pour deux raisons **vérifiables** :

1. elle interdit `@Attribute(.unique)`, or le modèle en compte **20** ;
2. elle ne fournit ni file d'attente inspectable, ni conflits visibles, ni
   déduplication idempotente, ni état de synchronisation explicable — qui sont
   précisément les exigences de `docs/roadmap/04-icloud-and-platforms.md`.

La synchronisation est donc une couche explicite, au-dessus d'un protocole de
transport.

### 2. Le transport est abstrait, donc testable sans Apple

`SyncTransport` décrit ce que la synchronisation attend d'un serveur.
`InMemorySyncTransport` en fournit une implémentation complète, partagée par
deux stores SwiftData distincts. C'est ce qui permet les **14 tests à deux
appareils** exigés par le jalon, sans conteneur CloudKit ni compte Apple :
travail hors ligne, ordre d'arrivée inversé, rejeu de la même salve,
suppression concurrente, modification concurrente, changement de compte.

`CloudKitSyncTransport` existe mais n'est **qu'un squelette** : il renvoie
`notConfigured`. La conversion `SyncRecord` ↔ `CKRecord` est volontairement
absente — l'écrire sans pouvoir l'exécuter une seule fois donnerait une fausse
impression de fonctionnement. Les étapes exactes sont dans
`docs/configuration/icloud.md`.

### 3. On synchronise des racines d'agrégat

Un programme voyage avec ses séances, prescriptions et groupes ; une séance
terminée avec ses séries ; un plan avec ses blocs, semaines et séances
planifiées.

Synchroniser les enfants séparément supposerait une granularité que
l'application n'a pas : elle édite ces objets comme des touts. Appliquer un
enregistrement distant **remplace l'agrégat entier**, ce qui est idempotent et
ne peut pas produire d'état impossible (une séance sans ses exercices).

### 4. Les charges utiles réutilisent les DTO de l'export v3

Un seul format décrit une entité, qu'elle parte dans une sauvegarde ou vers
iCloud. Deux formats divergeraient tôt ou tard. Les conversions de
`ExportImport` sont passées de `private` à interne pour être partagées.

L'encodage est **canonique** (clés triées, dates ISO 8601) : deux encodages du
même contenu sont identiques octet pour octet, ce qui permet de détecter
« rien n'a changé » et de ne pas écrire pour rien.

### 5. Rien n'est jamais supprimé silencieusement

- Une séance terminée est **immuable** : un autre appareil ne peut pas la
  réécrire, seulement la supprimer explicitement plus tard.
- Une suppression ne gagne **que** si elle est plus récente que la modification
  concurrente.
- Deux modifications concurrentes d'un programme produisent un **conflit
  visible** : les deux versions sont conservées, l'état local n'est pas écrasé,
  et l'utilisateur tranche.
- Une donnée écrite par une version plus récente du schéma n'est pas appliquée
  à l'aveugle.
- Aucune erreur — réseau, quota, compte, schéma — n'autorise à effacer des
  données locales. Un changement de compte iCloud **arrête** la synchronisation
  au lieu de fusionner les données d'un autre compte.

### 6. La file d'attente ne perd rien

Une entrée n'est retirée qu'après un envoi réussi. Une modification survenue
*pendant* l'envoi reste en attente. Les échecs retentables sont replanifiés
avec un backoff exponentiel plafonné à 30 minutes ; les échecs non retentables
(quota, compte, schéma) conservent l'entrée sans boucler.

### 7. Le diagnostic ne contient aucune donnée personnelle

Dates, compteurs, codes d'erreur et version de schéma. Un test vérifie qu'un
nom de programme ou une valeur de mesure n'y apparaît jamais.

### 8. Navigation adaptative, règles métier uniques

Onglets en largeur compacte, barre latérale en largeur régulière (iPad, Mac
Catalyst), avec raccourcis clavier ⌘1–⌘5. Les cinq destinations sont définies
**une seule fois** et les deux présentations affichent exactement les mêmes
écrans : aucune règle métier n'est dupliquée par plateforme.

### 9. Remplacer n'est jamais irréversible

L'import propose explicitement **Fusionner** ou **Remplacer**. Le mode
remplacement crée d'abord une sauvegarde v3 complète, et restaure
automatiquement si l'import échoue après la suppression. Un fichier illisible
est rejeté **avant** toute sauvegarde et toute suppression.

## Ce qui n'est pas validé

La synchronisation réelle avec iCloud **n'a jamais été exécutée** : elle exige
un conteneur CloudKit et une équipe Apple Developer. Sont donc non vérifiés :

- la conversion vers `CKRecord` (non écrite) ;
- le comportement réel des quotas, des notifications de changement et des
  jetons de serveur ;
- le scénario sur deux appareils physiques ;
- la promotion du schéma en Production.

Tant que ces étapes ne sont pas faites, l'écran *Synchronisation* affiche
« indisponible » et **ne propose aucun interrupteur** : une case à cocher qui
ne ferait rien serait un mensonge d'interface.

## Limites connues

- La synchronisation ne se déclenche pas encore automatiquement en arrière-plan
  (pas de `CKSubscription`, pas de tâche de fond) : elle est manuelle depuis
  l'écran d'état. Ce sera à ajouter en même temps que le transport réel.
- Le lien HealthKit (`healthWorkoutLink`) est déclaré comme type synchronisable
  mais rejeté à l'application : il n'aura de sens qu'en phase 7.
- Les raccourcis clavier se limitent à la navigation entre destinations ; les
  menus Mac complets relèvent de la phase 9.
