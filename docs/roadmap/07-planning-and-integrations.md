# 07 — Planning, contenu et intégrations

## Objectif

Relier les programmes au quotidien : planifier, rappeler, adapter au matériel,
retrouver les contenus et échanger les données avec l’écosystème Apple.

## Planning interne

- Calendrier jour/semaine/mois des séances prévues et réalisées.
- Récurrence hebdomadaire, dates de début/fin et semaines de pause.
- États : prévue, commencée, terminée, partielle, ignorée, reportée.
- Glisser-déposer ou action accessible pour déplacer une séance.
- Détection des collisions sans empêcher une décision volontaire.
- Proposition de replanification d’une séance manquée, avec confirmation.
- Les changements de planning ne modifient pas l’historique terminé.

## Notifications

- Rappel avant séance, rappel le jour même et rappel de reprise facultatifs.
- Heure, jours, son et délai configurables par programme.
- Actions sûres : démarrer, reporter, marquer comme ignorée.
- Mode silencieux et désactivation globale accessibles.
- Ne jamais programmer de notifications sans autorisation explicite.
- Recalculer proprement après changement de fuseau, programme ou permission.

## Calendrier Apple

Intégration EventKit facultative :

- exporter une séance ou un bloc vers un calendrier choisi ;
- mettre à jour seulement les événements créés par l’app grâce à un identifiant stable ;
- ne jamais modifier les événements externes ;
- proposer import d’un créneau, pas interprétation arbitraire d’un calendrier entier ;
- fonctionner sans permission Calendrier.

## Matériel, lieux et substitutions

- Profils de lieux : domicile, salle, voyage ou personnalisé.
- Inventaire par lieu avec charges minimales/maximales et incréments.
- Filtrage et génération selon le lieu de la séance.
- Substitutions classées par mouvement, muscles, matériel et niveau.
- Une substitution en cours de séance n’altère le programme qu’après confirmation.
- Historique conservant exercice prévu et exercice réellement exécuté.

## Bibliothèque de contenus

- Recherche tolérante aux accents et fautes simples.
- Filtres muscles, mouvement, matériel, difficulté et favoris.
- Tags et collections personnalisées.
- Instructions, erreurs fréquentes et variantes pour chaque exercice.
- Images/vidéos avec source et droits documentés ; aucun scraping non autorisé.
- Médias personnalisés locaux et synchronisation facultative séparée.
- Cache borné, suppression du cache et comportement hors ligne.

## Modèles et réutilisation

- Modèles de séance et de programme.
- Dupliquer, versionner, archiver et partager par fichier.
- Créer un modèle à partir d’une séance terminée sans recopier les performances.
- Favoris et dernières utilisations pour accélérer l’édition.

## Import et export inter-apps

- CSV générique avec assistant de correspondance des colonnes et aperçu.
- Importeurs dédiés uniquement pour les formats Strong/Hevy publiquement documentés.
- Valeurs inconnues mises en quarantaine plutôt qu’ignorées silencieusement.
- Rapport d’import : créés, fusionnés, ignorés, erreurs et doublons.
- Export CSV stable et documenté, en plus du JSON complet.
- Fichier partagé ne contenant jamais les secrets, tokens ou identifiants CloudKit.

## Raccourcis et Siri

Ajouter des App Intents pour :

- démarrer la prochaine séance ;
- ouvrir un programme ou exercice ;
- enregistrer le poids corporel ;
- lancer un minuteur de repos ;
- afficher le résumé hebdomadaire.

Les intentions doivent confirmer les écritures ambiguës et fonctionner avec des
entités stables. Les phrases et libellés sont localisés.

## Hors périmètre initial

- réseau social public, messagerie et classements mondiaux ;
- marketplace de coachs ou programmes payants ;
- pilotage propriétaire de machines de salle ;
- suivi nutritionnel clinique.

Ces sujets demandent modération, backend, conformité et modèle économique dédiés.

## Tests et critères d’acceptation

- Récurrence, report, fuseaux horaires et changement d’heure testés.
- Une notification supprimée ne réapparaît pas après relance.
- Les événements Apple Calendar externes ne sont jamais édités.
- Une substitution conserve prévu/réalisé et les calculs corrects.
- Import malformé, volumineux ou partiel n’endommage pas le store.
- Recherche, filtres et App Intents sont testés en français et en anglais.
- Tout le cœur de l’app reste disponible sans notifications, calendrier ni réseau.

