# 06 — Santé, mesures et analyses

## Objectif

Offrir un suivi utile de la progression et une intégration Apple Santé facultative,
avec des calculs corrects selon le type de charge.

## Mesures personnelles

Ajouter des séries temporelles facultatives pour :

- poids corporel ;
- tour de taille, poitrine, bras, cuisse et autres mesures personnalisées ;
- pourcentage de masse grasse déclaré avec source ;
- notes et photos de progression privées ;
- énergie, sommeil perçu, stress, courbatures et douleur du check-in.

Chaque valeur possède date, unité, source et commentaire. Les photos sont des actifs
séparés, compressés, supprimables et exclus des exports par défaut. Leur synchronisation
iCloud nécessite un consentement séparé.

## HealthKit

Intégration entièrement facultative et granulaire :

- écrire les entraînements terminés ;
- lire/écrire le poids corporel si autorisé ;
- lire fréquence cardiaque, énergie active et sommeil uniquement pour les vues qui
  les utilisent ;
- conserver un `HealthWorkoutLink` stable pour éviter les doublons ;
- réconcilier les modifications ou suppressions selon les règles HealthKit ;
- expliquer chaque permission juste avant la demande système ;
- continuer normalement si toute permission est refusée.

Ne pas recopier inutilement toutes les données HealthKit dans CloudKit. Conserver
les agrégats nécessaires et la provenance, conformément aux règles Apple en vigueur
au moment de l’implémentation.

## Calculs corrects

Normaliser les séries selon leur sémantique :

- charge externe : charge soulevée ;
- poids du corps : poids corporel connu ou valeur explicitement saisie ;
- lest : poids corporel + lest pour les analyses qui le nécessitent, lest seul pour
  la progression de charge ;
- assistance : poids corporel - assistance, jamais record de charge maximale ;
- unilatéral : convention par côté stockée explicitement ;
- machine/câble : valeur affichée sans prétendre à une équivalence entre appareils.

Documenter les formules de tonnage et d’estimation de 1RM. N’estimer le 1RM que sur
des séries pertinentes de 1 à 12 répétitions et indiquer qu’il s’agit d’une estimation.

## Tableaux de bord

- Volume et séries difficiles par muscle et par semaine.
- Tonnage, répétitions, durée et densité de travail.
- Évolution charge/répétitions/e1RM par exercice.
- Fréquence, régularité, adhérence au planning et calendrier de chaleur.
- Records par type : poids, répétitions, volume, temps, tours ou distance.
- Répartition mouvements/muscles et alertes simples de déséquilibre configurables.
- Comparaison d’un bloc à l’autre et tendance sans causalité médicale.
- Détection explicable de plateau avec fenêtre et seuil visibles.

Toutes les analyses doivent gérer les données manquantes et distinguer clairement
zéro, absence de donnée et permission refusée.

## Objectifs

- Objectifs de fréquence, séries hebdomadaires, exercice, poids ou mesure.
- Échéance facultative et progression visuelle non culpabilisante.
- Pause, modification et archivage sans réécrire l’historique.
- Aucun objectif de santé dangereux proposé automatiquement.

## Export et confidentialité

- Export JSON complet des mesures et consentements, hors photos par défaut.
- Export CSV séparé pour mesures, check-ins, séances et séries.
- Suppression par catégorie et suppression totale vérifiables.
- Masquer les données sensibles dans widgets, captures de diagnostic et notifications.
- Pas de suivi publicitaire ni de SDK analytique tiers par défaut.

## Tests obligatoires

- Formules pour tous les types de charge, unités et exercices unilatéraux.
- Fuseaux horaires, changements d’heure, semaines et agrégations calendaires.
- HealthKit autorisé, partiel, refusé, indisponible et doublon.
- Import/export et suppression des mesures/photos.
- Gros historiques avec mesures de temps et mémoire.
- VoiceOver et Dynamic Type pour tous les graphiques avec alternative textuelle.

## Critères d’acceptation

- Deux vues affichant le même indicateur utilisent le même calcul partagé.
- Une traction assistée ne crée jamais un faux record de charge.
- Le refus HealthKit ne bloque aucune fonction cœur.
- Les graphiques indiquent unités, période, données manquantes et formule pertinente.
- L’utilisateur peut exporter ou supprimer toutes ses données de suivi.

