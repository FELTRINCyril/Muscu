# Licences et provenance des contenus

## Catalogue d'exercices, images et instructions

**Source** : [free-exercise-db](https://github.com/yuhonas/free-exercise-db)
**Licence** : The Unlicence — domaine public, usage commercial autorisé, aucune
attribution exigée.

Le jeu de données est **épinglé à une révision précise** dans
`App/Sources/Services/ImageStore.swift`, et non suivi en continu : un
changement amont ne peut pas modifier silencieusement le contenu de
l'application.

Les **traductions françaises** des noms d'exercices et des instructions sont
produites et maintenues par ce dépôt (`Packages/MuscuEngine/Sources/MuscuEngine/CatalogData/exercises_fr.json`).
Elles suivent la même licence que le reste du dépôt.

Les images ne sont **pas embarquées** dans l'application : elles sont
téléchargées à la demande et mises en cache localement, dans la limite de
250 Mo (`ImageStore.maximumCacheBytes`). Le cache est vidable depuis Réglages.

## Vidéos

Aucune vidéo n'est hébergée ni redistribuée. Le bouton « Voir en vidéo » ouvre
une **recherche** dans le navigateur : le contenu appartient à ses auteurs et
Muscu n'en fait aucune copie.

## Formats d'import

Les formats CSV de Strong et de Hevy sont **publiquement documentés** par ces
applications. Muscu lit leurs exports ; il n'utilise ni leur marque, ni leur
code, ni leurs données.

## Dépendances

Aucune dépendance tierce. `Package.swift` ne déclare aucun paquet externe, et
tous les `import` du code sont des frameworks Apple ou le paquet local
`MuscuEngine`. Aucun SDK publicitaire, aucun traqueur, aucune bibliothèque
d'analytique.

## Avant publication

Ce fichier doit rester exact. Si un contenu sous une autre licence entre dans
le dépôt — un jeu d'icônes, une police, un jeu de données — il doit y être
ajouté **avant** d'être utilisé, avec sa licence et l'obligation d'attribution
qu'elle impose.
