# Changelog

## Unreleased

### Inspirations open source

- Modèle de données v7 (migration légère depuis v6) : note d'effort, cardio et
  énergie d'une séance, date de correction, repos réel d'une série, lien de
  démonstration, redirection d'un exercice fusionné, identifiant d'échantillon
  Santé. Tous facultatifs, exportés et validés à l'import ; les mesures Santé
  ne partent pas dans la synchronisation iCloud.
- Les boutons +/- de la charge suivent le pas réellement disponible (matériel
  du lieu, paliers du profil, unité) au lieu de 2,5 kg fixes.
- Écran maintenu allumé pendant une séance (réglage, activé par défaut).
- Toutes les charges affichées suivent l'unité choisie, y compris sur la
  montre ; la saisie se fait dans cette unité.
- Le repos ne s'arrête plus à zéro : son dépassement s'affiche (« +0:12 »)
  jusqu'à la série suivante. Repos par défaut distincts pour la barre et pour
  les haltères / machines.
- Plafond de répétitions réglable pour le 1RM estimé, appliqué aux records,
  graphiques et suggestions.
- Séance en direct : valeur précédente par série (tap pour recopier),
  bandeau des dix dernières séances de l'exercice (remplace la ligne « La
  dernière fois »), record célébré dès la série validée (sans écriture),
  calculateur de disques avec inventaire kg / lb réglable, bips aux trois
  dernières secondes du repos.
- Calculateur de 1RM rapide depuis les records et la fiche exercice.
- Séance libre depuis l'accueil (sans programme) : exercices ajoutés au fil
  de l'eau, fin sur demande, même fin de séance que les autres et reprise
  après interruption. Ajout d'un exercice et réordonnancement des exercices
  restants en pleine séance ; un exercice commencé ne bouge pas.
- Séries au temps et à la distance : mesure choisie dans l'éditeur de
  prescription ou en séance, chronomètre / compte à rebours avec saisie
  manuelle, saisie de distance. Aucun tonnage ; nouveaux records « Durée
  maximale », distance maximale et meilleur temps à distance égale.
- Repos réel enregistré pour chaque série (borné à une heure) et affiché dans
  l'historique.
- Note d'effort de séance 1-10 en fin de séance, affichée dans le résumé et
  l'historique. Export CSV : colonnes `effort_seance`, `distance_m` et
  `repos_reel_secondes` ajoutées en fin de ligne.
- Séance passée modifiable depuis l'historique : horaires, note d'effort,
  séries et exercices (ajout, correction, suppression), en mode édition
  explicite et après confirmation. `editedAt` et la révision sont renseignés ;
  les records issus de la séance sont recalculés depuis l'historique (sans
  jamais faire redescendre un record venu d'ailleurs), y compris à la
  suppression d'une séance ; l'entraînement Santé est remplacé ; la
  synchronisation laisse gagner la correction la plus récente (décision 0014).
- Santé : une séance terminée dans Muscu est écrite avec son vrai début
  (la date enregistrée est sa fin).
- « Refaire » et « Refaire à vide » une séance de l'historique : séance libre
  préremplie, titre conservé.
- Partage d'une séance en texte et en carte image carrée (ImageRenderer).
- Fin d'une séance de programme modifiée : écarts de structure listés et
  proposition de mettre à jour la séance du programme, de garder le programme
  ou d'enregistrer un nouveau modèle.
- Temps actif / temps de repos dans le résumé et l'historique.
- Import CSV : matériel déduit d'un nom « Exercice (Matériel) », et création
  de modèles ou d'un programme à partir des titres de séance importés.
- Santé (lot 5, toujours facultatif) : sur iOS 26 et plus, la séance est
  suivie en direct par Santé (`HKWorkoutSession` + `HKLiveWorkoutBuilder` sur
  iPhone) — pause avec « Reprendre plus tard », abandon sans enregistrement,
  reprise après un arrêt brutal — et l'entraînement ainsi enregistré remplace
  l'écriture après coup, sans doublon. Carte discrète en séance : bpm (si une
  montre ou un capteur le fournit, jamais « 0 »), kcal, durée. Sur iOS 18-25
  et Mac Catalyst, rien ne change.
- FC moyenne / min. / max. et énergie active de la séance, enregistrées depuis
  la séance en direct ou lues dans Santé sur l'intervalle de la séance (7
  derniers jours), affichées dans le résumé et l'historique.
- Note d'effort écrite dans Santé (score d'effort relié à l'entraînement), mise
  à jour si elle est corrigée sans remplacer l'entraînement (décision 0015).
- Import depuis Santé de la masse grasse et du tour de taille (interrupteur
  par mesure, lecture seule), incrémental et dédoublonné par identifiant
  d'échantillon, comme le poids désormais. Les nouveaux types sont présentés
  par un bouton expliqué, jamais au lancement.
- Live Activity interactive (lot 6, iOS 17+, hors Mac Catalyst) : boutons
  « Valider la série », « Passer » (le repos) et « +30 s » sur l'écran
  verrouillé et dans la Dynamic Island étendue. Ils agissent sur la séance en
  cours par le même chemin que les boutons de l'application (persistance pour
  la reprise, même chrono de repos), même application relancée en
  arrière-plan. « Valider » n'est proposé que pour une série classique
  poids × répétitions dont les valeurs proposées sont connues ; une série
  qui n'est plus celle affichée n'est jamais validée. Contenu enrichi :
  charge × répétitions prévues, série suivante, repos en décompte puis en
  dépassement « +0:12 » (décision 0016).
- Widget « Dernière séance » (petit / moyen) : date, durée, séries, tonnage
  (absent plutôt que « 0 kg » s'il n'est pas mesurable), record éventuel ; un
  tap ouvre l'application sur « Refaire » cette séance, après confirmation.
  Lien direct « Démarrer la prochaine séance » sur le widget Prochaine séance.
  Schéma d'URL `muscu://`, qui ne fait que naviguer.
- Siri et Raccourcis : « Quel est mon 1RM ? » (réponse parlée et petite vue :
  1RM estimé et de référence, avec leur date), « Mes records récents »,
  « Terminer la séance » et « Abandonner la séance » (confirmation, refus
  propre sans séance en cours ou sans série enregistrée). « Démarrer la
  prochaine séance » ouvre désormais l'écran de préparation.
- Apple Watch (lot 7) : séance en miroir — l'iPhone pousse à chaque
  transition l'état de la Live Activity (exercice, série n/N, charge ×
  répétitions prévues, série suivante, repos en décompte puis dépassement) ;
  « Valider la série » (ajustement à la Digital Crown), « Passer », « +30 s »
  et « Passer l'échauffement » exécutés sur l'iPhone par le chemin des boutons
  de l'application, refusés clairement si l'iPhone est injoignable, protégés
  contre le double tap et l'état périmé (identité de série). Démarrage de la
  prochaine séance ou d'une séance libre depuis la montre (sur l'iPhone, puis
  miroir). Mode autonome conservé, avec le vrai nom de l'exercice choisi dans
  la prochaine séance. Vibrations des trois dernières secondes et de fin de
  repos. Séance Santé au poignet (`HKWorkoutSession` + `HKLiveWorkoutBuilder`,
  `startWatchApp`, partage avec l'iPhone) : un seul hôte par séance — la
  montre si elle est appairée et équipée, sinon l'iPhone (iOS 26+), sinon
  écriture après coup — et un seul entraînement, relié avec FC moyenne / min.
  / max. et kcal (décision 0017). Complication rectangulaire et circulaire.
- Correction : une séance faite à la montre seule était refusée par l'iPhone
  (dates encodées en secondes, lues en ISO 8601). Les deux formats sont
  désormais acceptés.

### Écosystème Apple (phase 7)

- HealthKit facultatif : séances terminées écrites une seule fois, poids
  corporel partagé sur demande, suppression réconciliée. L'autorisation est
  expliquée avant d'être demandée, et un refus ne bloque rien.
- Widgets « Prochaine séance » et « Semaine », alimentés par un instantané qui
  ne contient que ce qu'ils affichent.
- Live Activity de séance en cours, fermée à la fin comme à l'abandon.
- Application Watch : enregistrement de séries et envoi en file d'attente vers
  l'iPhone. Une séance rejoint l'historique une seule fois, même si le
  transfert est rejoué.

### Coach IA (phase 8, derrière un drapeau désactivé par défaut)

- Protocole de service indépendant du fournisseur, service mock déterministe
  et mode BYOK avec clé conservée dans le Trousseau.
- Schémas JSON stricts : aucun programme n'est construit à partir de texte
  libre ; une sortie invalide n'atteint jamais les données.
- Validation locale avec réparation bornée et corrections listées, filtre de
  sécurité sur les progressions et les valeurs impossibles.
- Consentement granulaire, catégories sensibles exclues par défaut, résumé de
  ce qui part réellement.
- Repli déterministe sur le générateur local, annoncé comme tel.
- Journal technique sans donnée personnelle, effaçable, et suppression de
  l'ensemble des réglages et de la clé depuis « Mes données ».

### Écarts fermés (séries, tests, plan, photos, plateaux)

- Séries d'approche et de back-off saisissables : elles s'ajoutent sans
  consommer de série prescrite.
- Test de 1RM guidé, facultatif, précédé d'un avertissement de sécurité et
  refusé faute de référence fiable.
- Recalcul des semaines à venir d'un plan, confirmé avant écriture et sans
  toucher aux semaines déjà entamées.
- Photos de progression privées : hors de la base, hors des exports, hors de
  la sauvegarde iCloud, supprimées avec leur fichier.
- Calendrier de chaleur (séances, séries difficiles ou tonnage) avec échelle,
  maximum et données manquantes annoncés.
- Écran de détection de plateau : fenêtre et seuil visibles, décharge ou
  variante proposées, jamais appliquées sans accord.
- Modèle de données v5 (migration légère depuis v4).

### Planning, contenus et intégrations (phase 6)

- Planning jour / semaine / mois, récurrence hebdomadaire avec semaines de
  pause, détection des chevauchements et replanification confirmée des séances
  manquées.
- Rappels facultatifs par récurrence (avant la séance, le jour même, reprise),
  jamais programmés sans autorisation, jamais recréés après suppression.
- Export facultatif vers l'app Calendrier : seuls les événements créés par
  Muscu sont modifiés ou retirés.
- Profils de lieu et inventaire de matériel ; remplacements d'exercice classés
  et expliqués, appliqués au programme uniquement après confirmation.
- Bibliothèque : recherche tolérante aux fautes, filtres cumulables, favoris,
  tags et collections.
- Modèles de séance et de programme, y compris depuis une séance terminée sans
  recopier les performances ; partage par fichier.
- Import CSV (générique, Strong, Hevy) avec correspondance des colonnes,
  aperçu, doublons détectés et quarantaine des lignes illisibles.
- App Intents : prochaine séance, programme, exercice, poids corporel, minuteur
  de repos et résumé hebdomadaire.
- Modèle de données v4 (migration légère depuis v3) et export JSON v4, toujours
  compatible avec les sauvegardes v1, v2 et v3.

- Harden program generation, persistence, imports, workout restoration and image caching.
- Add a privacy manifest, stable third-party attribution, application unit tests and CI.

## 0.1.0

- Initial local-first MVP with programs, workout formats, exercise catalogue,
  progress tracking and JSON backup.
