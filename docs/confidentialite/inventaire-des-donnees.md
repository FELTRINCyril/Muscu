# Inventaire des données

Ce document décrit ce que Muscu enregistre, où, pourquoi et pour combien de
temps. Il doit rester **fidèle au code** : toute donnée ajoutée au modèle y est
ajoutée ici, et la fiche de confidentialité App Store en découle.

Dernière vérification : 04/10/2026, modèle v7 (lot 8 : sauvegardes automatiques).

## Principe

Tout est **local par défaut**. Aucune donnée ne quitte l'appareil sans une
action explicite de l'utilisateur : export, partage avec Santé, envoi au coach
IA, export vers le calendrier ou transfert depuis la montre.

Aucun SDK publicitaire, aucun traqueur, aucun service d'analyse tiers.

## Ce qui est enregistré sur l'appareil

| Donnée | Où | Pourquoi | Conservation |
| --- | --- | --- | --- |
| Programmes, séances types, prescriptions | Base locale (SwiftData) | Construire et exécuter les séances | Jusqu'à suppression par l'utilisateur |
| Historique des séances et des séries | Base locale | Progression, records, analyses | Idem |
| Note d'effort, fréquence cardiaque (moyenne, min., max.) et énergie active d'une séance (si mesurées) | Base locale | Résumé et détail de la séance ; le cardio vient d'une séance Santé en direct ou d'une lecture dans Santé sur l'intervalle de la séance | Idem |
| Records et records typés | Base locale | Suivi de performance ; recalculables depuis l'historique | Idem |
| Profil (objectif, niveau, matériel, unités) | Base locale | Adapter le générateur et les règles de progression | Idem |
| Mesures corporelles, poids, masse grasse, tour de taille (saisis ou importés de Santé, avec l'identifiant de l'échantillon Santé) | Base locale | Calculs de charge effective, suivi, import sans doublon | Idem |
| Check-in de forme, douleurs déclarées | Base locale | Proposer une adaptation prudente | Idem |
| Planning, récurrences, lieux et inventaire | Base locale | Organiser la semaine | Idem |
| Journal d'adaptation | Base locale | Rendre chaque progression explicable et annulable | Idem |
| **Photos de progression** | **Fichiers, hors base** | Suivi visuel | Jusqu'à suppression ; dossier exclu de la sauvegarde iCloud |
| Cache d'images d'exercices | Fichiers | Affichage hors ligne | Borné à 250 Mo, vidable depuis Réglages |
| **Sauvegardes automatiques** (export JSON complet, **sans les photos**) | Dossier Documents, **visible dans l'app Fichiers** (`Sauvegardes`) ; inclus dans la sauvegarde de l'appareil comme la base | Pouvoir revenir en arrière sans export manuel | **Désactivées par défaut** ; au plus une par jour, les 7 plus récentes gardées ; supprimables depuis Fichiers |
| Sauvegardes de sécurité avant un import « Remplacer » | Application Support, hors de Fichiers | Restaurer si l'import échoue | Les 5 plus récentes |
| Lien de démonstration personnel d'un exercice, paires de doublons écartées | Base locale / `UserDefaults` | Ouvrir sa vidéo de référence ; ne plus reproposer une paire | Jusqu'à suppression |
| Instantané des widgets | Groupe d'applications | Alimenter les widgets et la montre | Réécrit à chaque changement, effacé avec les données |
| Rappels programmés | Centre de notifications + base locale | Ne pas reprogrammer un rappel supprimé | Jusqu'à désactivation |
| Liens vers l'app Santé (identifiant de l'entraînement, horaires et note d'effort écrits, identifiant de l'échantillon d'effort) | Base locale, non synchronisés | Éviter d'écrire deux fois la même séance ; mettre à jour la note d'effort | Jusqu'à suppression |
| Liens vers l'app Calendrier | Base locale | Ne modifier que nos propres événements | Idem |
| **Clé du fournisseur IA** | **Trousseau** (`WhenUnlockedThisDeviceOnly`) | Authentifier les requêtes du coach | Jusqu'à suppression par l'utilisateur |
| Réglages (IA, Santé, chrono, unités) | `UserDefaults` | Préférences | Idem |
| Marqueur de séance Santé en direct (identifiants de séance, aucune donnée de santé) | `UserDefaults` | Rattacher ou abandonner proprement une séance Santé après un arrêt brutal | Effacé à la fin ou à l'abandon de la séance |
| Journal technique du coach IA | `UserDefaults`, borné à 50 lignes | Diagnostic | Effaçable ; ne contient aucune donnée métier |

## Ce qui peut sortir de l'appareil, et à quelle condition

| Destination | Contenu | Condition |
| --- | --- | --- |
| Fichier d'export JSON | Tout le modèle **sauf les photos** | Action explicite (Réglages → Exporter) |
| Sauvegarde automatique (même contenu que l'export) | Reste sur l'appareil, dans Fichiers ; ne part ailleurs que si l'utilisateur la partage | Réglage « Sauvegarde automatique » activé (désactivé par défaut) ; « Partager » est une action explicite |
| Lien de démonstration | Ouvert dans le navigateur (`http`/`https` uniquement) | Tap explicite sur « Ma démonstration » |
| Fichiers CSV | Séances, séries, mesures, check-in | Action explicite |
| App Santé (écriture) | Séances terminées (en direct sur iOS 26+, après coup sinon), note d'effort reliée à l'entraînement, poids corporel (si activé), fréquence cardiaque et énergie active mesurées par un capteur pendant une séance en direct | Interrupteur activé **et** autorisation système accordée, type par type |
| App Calendrier | Titre et horaire des séances planifiées | Action explicite, calendrier choisi par l'utilisateur |
| Apple Watch | Instantané (prochaine séance, compteurs de la semaine) | Montre appairée |
| Fournisseur IA | Catégories **choisies une par une**, exclues par défaut pour les trois sensibles | Coach activé, clé saisie, consentement par catégorie |
| iCloud | — | **Non activé** : aucun conteneur configuré |

## Ce qui est lu dans l'app Santé

Uniquement si le partage est activé et l'autorisation accordée, type par type :

| Donnée lue | Quand | Usage |
| --- | --- | --- |
| Poids corporel | Si « Partager le poids corporel » est activé | Mesures, calculs de charge |
| Masse grasse, tour de taille | Chacun si son interrupteur est activé | Mesures (lecture seule : jamais écrits dans Santé) |
| Fréquence cardiaque, énergie active | Sur l'intervalle des séances des 7 derniers jours qui n'ont pas déjà un cardio | FC moyenne / min. / max. et kcal de la séance |

Rien d'autre n'est lu : ni sommeil, ni pas, ni activité en dehors des séances.

## Ce qui ne sort jamais

- Les **photos de progression** : exclues de l'export, du groupe d'applications
  et de la sauvegarde iCloud.
- La **clé du fournisseur IA** : jamais dans un export, un journal, une
  sauvegarde ou le corps d'une requête — seulement dans un en-tête
  d'autorisation.
- L'**identité** (prénom, nom) : jamais envoyée au coach IA.
- Les données **HealthKit lues** : elles alimentent l'app et ne repartent vers
  aucun service. La fréquence cardiaque et l'énergie active d'une séance sont
  retirées de la synchronisation iCloud ; seul l'export JSON, déclenché par
  l'utilisateur, les contient.

## Effacement

*Réglages → Mes données* permet de supprimer par catégorie ou en totalité.
Chaque catégorie annonce ce qu'elle efface, et le compte rendu liste ce qui a
été supprimé.

Deux limites, dites explicitement dans l'interface :

- les entraînements **déjà écrits dans l'app Santé** ne sont pas retirés : ils
  appartiennent à l'app Santé, et se suppriment depuis elle ;
- les **événements déjà créés dans Calendrier** doivent être retirés depuis le
  planning avant la suppression, sinon ils survivent à leur source.

## Correspondance avec le Privacy Manifest

`App/Resources/PrivacyInfo.xcprivacy` déclare :

- `NSPrivacyTracking` : `false` — aucun suivi ;
- `NSPrivacyCollectedDataTypes` : vide — aucune donnée n'est collectée par
  l'éditeur, tout reste sur l'appareil ou part vers un service choisi par
  l'utilisateur ;
- `NSPrivacyTrackingDomains` : vide ;
- `NSPrivacyAccessedAPITypes` : `UserDefaults` avec la raison `CA92.1`
  (préférences de l'application elle-même) et dates de fichiers avec la raison
  `C617.1` (fichiers du conteneur de l'app : classement des sauvegardes,
  automatiques comprises).

HealthKit, les notifications, le calendrier et la photothèque ne figurent pas
dans les API à raison déclarée : ils sont encadrés par des autorisations
système et des descriptions d'usage, présentes dans `project.yml`.
