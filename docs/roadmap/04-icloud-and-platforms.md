# 04 — iCloud, multi-appareils et plateformes Apple

## Objectif

Rendre les données fiables sur plusieurs appareils Apple, tout en conservant un
mode entièrement local et la sauvegarde manuelle existante.

## Synchronisation iCloud

Utiliser CloudKit dans la base privée de l’utilisateur avec une architecture
local-first : toute action valide est d’abord enregistrée localement puis
synchronisée en arrière-plan.

Exigences :

- activation volontaire et état de synchronisation compréhensible ;
- fonctionnement complet hors ligne avec file d’attente persistante ;
- identifiants stables, dates de création/modification et tombstones de suppression ;
- reprise avec backoff après erreur réseau, quota ou indisponibilité CloudKit ;
- aucune remise à zéro automatique en cas d’erreur de compte ou de schéma ;
- conflits résolus champ par champ lorsque possible, sinon copie de conflit visible ;
- déduplication idempotente des séances, séries et records ;
- changement/déconnexion de compte iCloud géré sans perte locale silencieuse ;
- écran affichant dernière synchronisation, erreurs, éléments en attente et action
  de relance ;
- diagnostic exportable sans données sensibles.

Les conteneurs CloudKit, capacités, entitlements et environnements Development /
Production sont des prérequis externes : le code doit les documenter et détecter
leur absence, jamais prétendre les avoir configurés.

## Migrations et conflits

- Versionner le schéma local et les enregistrements CloudKit.
- Migrer par copie ou transformation contrôlée, avec tests depuis chaque version
  supportée.
- Définir les règles de fusion pour chaque entité dans la documentation du code.
- Une séance terminée est immuable ; une correction crée une révision traçable.
- Une suppression gagne seulement si elle est plus récente que la modification
  concurrente ; sinon demander une résolution ou conserver les deux versions.
- Les records sont recalculables depuis l’historique et ne doivent pas être la
  source de vérité lors d’un conflit.

## Sauvegarde et portabilité

- Conserver export/import JSON manuel et accepter les versions 1 et 2.
- Produire un export v3 complet, documenté et validé avant import.
- Proposer aussi un export CSV lisible pour séances, séries, mensurations et records.
- Ajouter une sauvegarde via feuille de partage et un rappel facultatif de sauvegarde.
- L’import affiche un aperçu, permet fusion ou remplacement, puis crée une sauvegarde
  de sécurité avant tout remplacement.
- Limiter taille, profondeur, pièces jointes et valeurs extrêmes des imports.

## iPhone, iPad et Mac

- Passer d’une cible iPhone seule à une app universelle iPhone/iPad.
- Fournir une navigation adaptative : onglets en compact, sidebar et détail sur iPad.
- Ajouter Mac Catalyst en premier pour partager l’implémentation ; documenter les
  éventuels écarts justifiant plus tard une cible macOS native.
- Supporter clavier, raccourcis, menus, redimensionnement et pointeur sur iPad/Mac.
- Ne jamais dupliquer les règles métier dans les vues propres à une plateforme.
- Un même compte iCloud doit retrouver programmes, historique, records, réglages et
  planning sur les trois plateformes.

## Apple Watch

Créer une app compagnon capable de :

- afficher et démarrer la séance planifiée ;
- enregistrer charge, répétitions, durée et RPE/RIR ;
- piloter repos/intervalles avec sons et retours haptiques ;
- fonctionner temporairement sans l’iPhone ;
- synchroniser via `WatchConnectivity` avec une file idempotente ;
- transmettre le lien HealthKit sans créer deux entraînements.

Les éditions complexes de programme restent sur iPhone, iPad ou Mac.

## Widgets et Live Activities

- Widget petite/moyenne taille : prochaine séance, série en cours ou progression hebdomadaire.
- Live Activity : exercice/série courante, chrono et actions sûres de base.
- Dynamic Island lorsque disponible.
- Données partagées via App Group avec snapshots minimaux, jamais par accès direct
  concurrent au store principal.
- Rafraîchissements économes et comportement dégradé lorsque le système les limite.

## Tests obligatoires

- Deux stores simulant deux appareils, modifications simultanées et suppressions.
- Hors ligne, reprise, doublons, ordre d’arrivée inversé et changement de compte.
- Migrations de toutes les versions d’export et de schéma supportées.
- Navigation et édition sur iPhone, iPad et fenêtre Mac redimensionnée.
- Watch hors connexion puis réconciliation.
- Widgets/Live Activity sans donnée, pendant séance et après expiration.
- Parcours réel sur deux appareils et compte iCloud de test avant distribution.

## Critères d’acceptation

- Un nouvel appareil restaure les données après connexion et activation d’iCloud.
- Le mode local reste utilisable sans compte iCloud.
- Une séance créée hors ligne apparaît une seule fois sur les autres appareils.
- Les conflits ne suppriment jamais silencieusement deux versions divergentes.
- Les données visibles sur Mac correspondent à celles de l’iPhone.
- L’utilisateur peut toujours exporter et restaurer une sauvegarde indépendante.

