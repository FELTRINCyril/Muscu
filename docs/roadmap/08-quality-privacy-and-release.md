# 08 — Qualité, confidentialité et distribution

## Objectif

Transformer l’ensemble fonctionnel en produit fiable, accessible, performant et
distribuable sur les plateformes Apple ciblées.

## Accessibilité et ergonomie

- Dynamic Type sans troncature des informations essentielles.
- VoiceOver avec libellés, valeurs, actions et ordre de lecture cohérents.
- Alternatives textuelles aux graphiques et animations.
- Contraste suffisant et information jamais portée uniquement par la couleur.
- Cibles tactiles d’au moins 44 points lorsque possible.
- Réduction des animations, sons et haptique configurable.
- Clavier complet et focus visible sur iPad/Mac.
- Confirmations pour suppressions et fin de séance, avec annulation lorsque possible.

## Localisation et unités

- Français et anglais sans chaînes utilisateur codées en dur dans les vues.
- Formats locaux de date, heure, nombres et semaine.
- Kilogrammes et livres, avec conversion centralisée et valeur canonique documentée.
- Distances et tailles localisées.
- Les exports conservent unité et valeur source sans arrondis destructifs.
- Tester les textes longs, pluriels et langues pseudo-localisées.

## Performance et robustesse

- Mesurer lancement, ouverture de l’historique, génération et fin de séance.
- Paginer ou agréger les historiques importants.
- Calculs lourds hors du thread principal, avec annulation.
- Éviter les chargements complets du store pour les tableaux de bord.
- Budget mémoire pour médias, graphiques et Watch.
- Aucune force unwrap sur donnée persistée ou importée.
- Erreurs présentées avec action utile ; pas de `catch` silencieux.

## Vie privée

- Inventaire des données, finalités, lieux de stockage et durées de conservation.
- Privacy Manifest et déclarations App Store cohérents avec le code réel.
- Descriptions d’usage HealthKit, notifications, calendrier et photos précises.
- Écran de gestion des consentements et révocation.
- Export et suppression totale, y compris CloudKit et backend IA lorsque applicable.
- Journaux sans contenu de séances, santé, clé API ou identifiant personnel.
- Aucun SDK publicitaire ou traqueur tiers par défaut.

## Sécurité

- Secrets dans le Trousseau ou sur backend, jamais dans git, plist ou logs.
- TLS et validation normale du système ; pas de désactivation des contrôles réseau.
- Limites de taille, profondeur, nombre d’objets et plage numérique à l’import.
- Fuzz tests du décodage et migrations atomiques.
- Contenu importé/IA considéré non fiable et rendu sans exécution.
- App Groups, CloudKit et HealthKit avec les droits minimaux.
- Modèle de menaces court mis à jour pour synchronisation, IA, imports et widgets.

## Diagnostics

- Journal local borné et expurgé, désactivable.
- Export de diagnostic volontaire contenant versions, états et codes d’erreur,
  jamais les données métier brutes.
- Si un service de crash est ajouté, consentement et minimisation sont requis.
- Indicateurs de santé du store : migration, sync en attente, dernière sauvegarde.

## Stratégie de tests

- Tests unitaires de `MuscuEngine`, modèles, conversions et migrations.
- Tests d’intégration store/import/sync/HealthKit avec doubles contrôlables.
- Tests UI des parcours critiques et états erreur/vide/hors ligne.
- Tests de propriétés pour génération, progression et agrégations.
- Tests de performance avec historique volumineux.
- Matrice iPhone compact/grand, iPad, Mac Catalyst et Watch supportés.
- CI reproductible : génération du projet, tests engine, tests app, UI critiques et
  build Release sans avertissement nouveau.

Commandes minimales à maintenir :

```sh
swift test
xcodegen generate
xcodebuild -project Muscu.xcodeproj -scheme Muscu -configuration Debug test
xcodebuild -project Muscu.xcodeproj -scheme Muscu -configuration Release build
```

Adapter destinations et schémas aux cibles ajoutées, puis documenter la commande CI exacte.

## Préparation App Store

- Identifiants, versions, icônes, écran de lancement et métadonnées finalisés.
- Captures iPhone/iPad/Mac dans les langues distribuées.
- Politique de confidentialité et page d’assistance accessibles.
- Fiche nutritionnelle de confidentialité fidèle.
- Archive Release signée et testée via TestFlight sur appareils réels.
- Revue des achats : ne pas ajouter d’abonnement tant qu’aucune proposition de valeur
  et restauration d’achat ne sont spécifiées.
- Notes de version et procédure de rollback/migration documentées.

## Critères d’acceptation

- Zéro erreur de compilation et aucun avertissement nouveau accepté sans justification.
- Tous les parcours critiques sont accessibles au clavier/VoiceOver et en grande taille.
- Aucun secret ou donnée sensible n’apparaît dans l’archive ou les diagnostics.
- Une installation, mise à jour et restauration sont testées sur appareils réels.
- Les déclarations App Store correspondent aux permissions et transferts réels.
- Les performances restent acceptables avec plusieurs années d’historique.

