# 10 — Inspirations open source

Date : 03/10/2026
Branche : `feat/inspirations-open-source`

Quatre applications open source ont été archivées dans le dépôt
(`archive/iron`, `archive/ischys`, `archive/skulpt`,
`archive/strength-training`) et comparées à Muscu. Ce document liste les
écarts retenus et l'ordre de livraison.

Licences : UpLift (`archive/strength-training`) et Ischys sont sous MIT — du
code peut être repris avec attribution dans `THIRD_PARTY_NOTICES.md`. Iron et
Skulpt sont sous GPL-3.0 : **idées uniquement, aucune ligne de code reprise**.

## Lots

| Lot | Contenu | Sources d'inspiration |
|---|---|---|
| 1 | Schéma v7 (champs nécessaires aux lots suivants) ; corrections rapides : pas de charge du profil dans la saisie, écran maintenu allumé en séance, unités en dur, repos qui déborde (affiché en négatif) et repos par défaut barre / haltères, plafond de répétitions pour le 1RM estimé | UpLift, Iron, Skulpt |
| 2 | Séance en direct : valeur précédente par série (tap pour recopier), bandeau des dernières séances, record célébré en direct, calculateur de disques, calculateur de 1RM, bips de fin de repos | Ischys, UpLift |
| 3 | Séance libre, ajout / réordonnancement d'exercices en séance, séries au temps et à la distance, repos réel enregistré, note d'effort 1-10 en fin de séance | Iron, Skulpt, Ischys, UpLift |
| 4 | Historique : modifier une séance passée, la refaire, la partager (texte et image), proposer de mettre à jour le programme après une séance modifiée, temps actif / repos dans le résumé, import CSV → programmes | Iron, Skulpt, Ischys |
| 5 | Santé : séance HealthKit en direct sur iPhone (iOS 26+), cardio et calories, note d'effort écrite dans Santé, import masse grasse / tour de taille | UpLift, Skulpt |
| 6 | Live Activity interactive, widget « dernière séance », intents Siri (1RM, records, terminer / annuler) | Ischys, Skulpt, Iron |
| 7 | Apple Watch : vraie séance (HKWorkoutSession, cardio), exercice courant reçu de l'iPhone, repos au poignet, synchro dans les deux sens | les quatre |
| 8 | Bibliothèque et analyses : fusion de doublons, exercices habituels en tête, score de force et records du mois, statistiques par exercice, lien de démo personnel ; sauvegardes automatiques avec restauration ; test de rejeu de la progression | Ischys, UpLift, Skulpt, Iron |

## État final (04/10/2026)

Les huit lots sont livrés sur la branche, chacun avec sa décision
d'architecture, ses tests (moteur et tests unitaires de l'application) et son
entrée dans `CHANGELOG.md`. « À vérifier sur appareil » désigne ce que le
simulateur ne sait pas démontrer : le code est compilé et testé, son
comportement réel reste à constater.

| Lot | État | Décision | Ce qui reste |
|---|---|---|---|
| 1 | **Livré** | 0011 | — Schéma v7 (dix attributs facultatifs, migration légère) et corrections rapides. |
| 2 | **Livré** | 0012 | Bips de fin de repos joués application ouverte seulement (en arrière-plan, la notification de fin de repos prend le relais). |
| 3 | **Livré** | 0013 | Limite assumée : le chronomètre d'une série au temps n'est pas persisté (un arrêt brutal perd le temps écoulé, saisie manuelle possible) ; le repos réel inclut l'exécution de la série précédente. |
| 4 | **Livré** | 0014 | Suppression d'une séance toujours physique (non propagée par la synchronisation) ; temps actif approché (début réel d'une série inconnu). |
| 5 | **Livré — à vérifier sur appareil** | 0015 | Séance Santé en direct (iOS 26+), fréquence cardiaque d'un capteur, reprise après arrêt brutal, enregistrement écran verrouillé : à constater sur un iPhone sous iOS 26 avec montre ou capteur. |
| 6 | **Livré — à vérifier sur appareil** | 0016 | Boutons de la Live Activity (écran verrouillé, Dynamic Island, relance en arrière-plan), péremption, phrases Siri et liens des widgets : à constater sur appareil. |
| 7 | **Livré — à vérifier sur appareil** | 0017 | Tout l'échange iPhone ↔ montre (messages, `startWatchApp`, partage de la séance Santé, cardio réel, Digital Crown, complication) : à constater avec un iPhone et une Apple Watch appairés. |
| 8 | **Livré** | 0018 | Sauvegardes visibles dans Fichiers et écriture au passage en arrière-plan à constater sur appareil ; « même identifiant d'import » interprété comme la convention de nom « Exercice (Matériel) », Muscu ne stockant pas d'identifiant d'import par exercice ; aucun niveau de force (novice / élite) faute de table de référence sourcée. |

## Écarté

- **Carte musculaire du corps** : demande des silhouettes anatomiques dessinées ;
  la répartition par muscle existe déjà en graphique.
- **Illustrations animées** : CC BY-SA, ~120 mouvements seulement, alors que le
  catalogue en compte 873 avec images.
- **Thème clair** : l'application est sombre par choix de conception.
- **Mode Force / Endurance** : couvert par les fourchettes de répétitions et
  l'objectif du programme.
- **Pavé numérique maison, demande d'avis App Store** : sans intérêt pour un
  usage personnel.
