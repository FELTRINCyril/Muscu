# 03 — Programmation, périodisation et adaptation

## Objectif

Passer d’un générateur ponctuel à un système capable de construire un plan,
d’appliquer une surcharge progressive et de proposer des ajustements explicables.

## Profil et objectifs

Le questionnaire doit pouvoir enregistrer :

- objectif principal et objectifs secondaires ;
- expérience réelle par mouvement ;
- jours disponibles et contraintes horaires ;
- durée minimale et maximale ;
- équipement par lieu d’entraînement ;
- préférences et exercices exclus ;
- muscles prioritaires ;
- zones à ménager ;
- fréquence souhaitée par groupe musculaire ;
- unités et incréments de charge disponibles.

Les zones à ménager ne constituent jamais un avis médical. L’interface doit inviter
l’utilisateur à consulter un professionnel en cas de douleur ou blessure.

## Génération déterministe v2

Étendre `MuscuEngine` pour produire :

- un plan de 4 à 16 semaines ;
- des semaines et séances datables ;
- une répartition du volume par groupe musculaire ;
- une sélection tenant compte des mouvements déjà choisis ;
- une alternance réaliste des exercices entre séances similaires ;
- des substitutions compatibles ;
- une semaine de décharge configurable ;
- une explication courte de chaque choix.

Le moteur doit vérifier :

- catégories, niveau et équipement ;
- durée estimée, échauffement compris ;
- récupération entre groupes musculaires ;
- bornes de volume configurables ;
- absence d’exercice incompatible avec une zone à ménager ;
- présence des mouvements essentiels au split lorsque possible.

## Progression

Implémenter plusieurs règles sélectionnables :

- double progression ;
- augmentation fixe de charge ;
- progression en répétitions ;
- progression en séries ;
- pourcentage du 1RM ;
- RPE/RIR cible ;
- progression spécifique aux tractions lestées ou assistées ;
- progression temporelle pour intervalles et circuits.

Chaque règle possède : seuils, incrément, plafond, condition de réussite, condition
de maintien et condition de réduction. Une proposition ne modifie pas le programme
sans historique visible et possibilité d’annuler.

Exemple de double progression :

1. rester à la même charge tant que toutes les séries n’atteignent pas le haut de
   la fourchette avec le RIR minimal demandé ;
2. proposer l’incrément disponible suivant ;
3. revenir au bas de la fourchette ;
4. maintenir ou réduire si plusieurs séances échouent, sans diagnostic médical.

## Périodisation

Ajouter des blocs :

- accumulation/hypertrophie ;
- intensification/force ;
- réalisation/test facultatif ;
- décharge.

Permettre une périodisation linéaire ou ondulatoire simple. Les semaines futures
sont des prescriptions modifiables ; l’historique reste immuable.

## Readiness et fatigue

Avant une séance, proposer un check-in facultatif :

- énergie ;
- sommeil perçu ;
- courbatures ;
- stress ;
- douleur avec zone et intensité.

Le moteur local peut suggérer : séance normale, réduction du volume, réduction de
charge, substitution ou repos. Toute suggestion doit expliquer les facteurs pris
en compte et rester modifiable. Une douleur inhabituelle déclenche uniquement un
message prudent, jamais une prescription médicale.

## Tests, décharges et plateaux

- Test de 1RM facultatif avec protocole et avertissement de sécurité.
- Estimation sans test maximal privilégiée par défaut.
- Détection d’un plateau sur plusieurs expositions comparables.
- Proposition de décharge ou de variante, jamais application silencieuse.
- Conservation des raisons et décisions dans un journal d’adaptation.

## Calendrier du programme

- Commencer un plan à une date choisie.
- Déplacer une séance sans casser la semaine.
- Marquer réalisée, partielle, ignorée ou reportée.
- Recalculer les séances futures après confirmation.
- Gérer vacances, indisponibilités et semaines libres.

## Critères d’acceptation

- Le même profil et la même graine donnent le même plan local.
- Chaque séance respecte durée, matériel, niveau et exclusions.
- Toute progression est justifiée par des performances identifiables.
- L’utilisateur peut refuser ou annuler une adaptation.
- Une décharge réduit réellement volume et/ou intensité selon la règle documentée.
- Les changements futurs n’altèrent jamais l’historique.
- Les algorithmes sont couverts par des tests de propriétés et des cas limites.
