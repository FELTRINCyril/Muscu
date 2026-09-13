# Changelog

## Unreleased

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
