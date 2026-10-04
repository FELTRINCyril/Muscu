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
