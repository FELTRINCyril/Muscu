# 05 — Coach et génération par IA

## Objectif

Ajouter une véritable couche IA pour créer, expliquer et adapter des programmes,
sans confondre génération probabiliste, moteur métier et conseil médical.

## Architecture

Définir un protocole `AICoachService` indépendant du fournisseur avec :

- un service mock déterministe pour previews et tests ;
- un service distant injectable ;
- des requêtes/réponses `Codable` versionnées ;
- annulation, délai maximal, reprise contrôlée et limite de coût ;
- journal technique expurgé des données personnelles.

Deux modes d’authentification seulement :

1. clé personnelle facultative conservée dans le Trousseau et jamais dans le repo ;
2. service géré passant par un backend sécurisé qui garde le secret côté serveur.

Ne jamais embarquer une clé fournisseur globale dans l’application. En l’absence
de configuration, afficher clairement que l’IA est indisponible et proposer le
générateur local.

## Capacités

- Transformer une demande en langage naturel en brouillon de programme structuré.
- Adapter une semaine selon disponibilités, historique et check-in.
- Proposer des substitutions selon matériel, préférence ou gêne déclarée.
- Expliquer simplement répartition, volume, progression et récupération.
- Répondre dans un fil de discussion lié à un programme ou une séance.
- Résumer une séance et proposer les prochaines charges sous forme de suggestions.
- Reformuler une séance pour une durée plus courte sans perdre son intention.

Chaque résultat est un brouillon prévisualisé. L’utilisateur confirme avant toute
écriture ou modification d’un programme.

## Sorties structurées et validation

- Utiliser des schémas JSON stricts ; aucun programme ne doit être construit en
  analysant du texte libre.
- Référencer uniquement des identifiants d’exercices connus ou demander explicitement
  la création d’un exercice personnalisé.
- Valider côté app matériel, niveau, durée, volumes, bornes de charge, groupes,
  formats, repos et règles de progression avec `MuscuEngine`.
- Tenter une réparation structurée bornée, puis rejeter proprement si elle échoue.
- Fournir une solution déterministe locale lorsque la requête réseau échoue.
- Conserver version du schéma, modèle utilisé et explication, pas le raisonnement
  interne du modèle.

## Contexte, vie privée et consentement

- Envoyer le minimum nécessaire et afficher un résumé des catégories partagées.
- Données HealthKit, mensurations, douleurs, notes et identité sont exclues par défaut.
- Demander un consentement granulaire avant d’inclure une catégorie sensible.
- Permettre d’effacer les conversations locales et distantes lorsque le backend les
  conserve.
- Documenter durée de conservation, fournisseur, région et politique de données.
- Ne jamais utiliser les données pour entraîner un modèle sans consentement explicite.

## Sécurité et limites

- Les notes, imports et noms d’exercices sont du contenu non fiable, jamais des
  instructions système.
- Échapper ou isoler ces contenus contre les injections de prompt.
- Ne pas diagnostiquer, prescrire un traitement ou remplacer un professionnel.
- En cas de douleur inhabituelle, proposer d’arrêter et de consulter un professionnel.
- Ne pas pousser vers un test maximal ou une charge dangereuse.
- Afficher que les suggestions peuvent contenir des erreurs.
- Filtrer valeurs impossibles et progression agressive avec des règles locales.

## UX et maîtrise des coûts

- Afficher génération en cours, annulation, erreur et nouvelle tentative.
- Prévisualiser le diff avant adaptation.
- Montrer quelles contraintes ont été respectées et lesquelles ne l’ont pas été.
- Autoriser une limite mensuelle et indiquer une estimation d’usage avant envoi long.
- Mettre en cache uniquement les réponses non sensibles et avec une clé de contexte.
- Aucun écran indispensable à l’entraînement ne doit dépendre du réseau ou de l’IA.

## Tests et évaluations

- Tests de schéma, validation, réparation, timeout, annulation et fallback.
- Faux fournisseur pour tester erreurs HTTP, réponse tronquée et JSON malveillant.
- Corpus d’évaluation : niveaux, objectifs, équipements, restrictions et durées variés.
- Vérifier contraintes de volume, disponibilité, sécurité et déterminisme du fallback.
- Tests d’injection dans notes, noms d’exercices et imports.
- Tests UI du consentement, de la prévisualisation, du refus et de l’indisponibilité.

## Critères d’acceptation

- Une demande française produit un brouillon valide et modifiable, jamais une écriture directe.
- Aucun secret n’apparaît dans le binaire, les logs ou le dépôt.
- Une sortie invalide ne peut pas atteindre le store principal.
- Le mode hors ligne conserve la génération locale et toutes les fonctions d’entraînement.
- L’utilisateur sait quelles données partent vers quel service et peut refuser.
- Toute adaptation affiche ses raisons et peut être annulée.

