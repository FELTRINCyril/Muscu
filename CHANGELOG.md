# Changelog

## Unreleased

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
