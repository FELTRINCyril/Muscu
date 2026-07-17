# Muscu

Application iOS native de musculation, sombre et épurée, pour un usage personnel en
salle comme à la maison. Elle permet de créer des programmes d'entraînement, de
dérouler ses séances en direct avec un chrono de repos adaptatif, et de suivre sa
progression (records, 1RM, historique, graphiques) - le tout **100% hors ligne**.

## Fonctionnalités

- **Programmes** : trois façons de construire un programme.
  - **Manuel** : création libre, séance par séance, exercice par exercice.
  - **Modèles** : splits classiques prêts à l'emploi (Full Body, Upper/Lower, PPL,
    Arnold...), éditables ensuite (remplacement d'exercice, séries, répétitions).
  - **Générateur** : un questionnaire (objectif, expérience, jours par semaine,
    durée de séance, matériel disponible, muscles prioritaires, zones à éviter)
    produit un programme complet et cohérent, prévisualisable avant import.
- **Séances en direct** : saisie rapide poids/répétitions, chrono de repos
  automatique avec notifications, reprise après interruption (kill de l'app en
  pleine séance).
- **Formats d'exercices spécifiques** :
  - **Classique** : séries/répétitions standard, avec suggestion de charge
    (dernière performance ou pourcentage du 1RM connu).
  - **Pyramide** : montée/descente de répétitions avec **repos adaptatif** calculé
    selon l'intensité relative de la série qui vient d'être faite.
  - **Intervalles (30-30)** : blocs travail/repos chronométrés.
  - **AMRAP** : un maximum de répétitions dans un temps donné.
  - **Échauffement** : montée en charge automatique avant l'exercice principal.
- **Progression** : records par exercice (1RM estimé via la formule d'Epley, max de
  répétitions), détection automatique des performances battues en fin de séance,
  historique complet des séances, graphiques d'évolution par exercice.
- **Catalogue** : 873 exercices en français (nom, muscles, matériel, catégorie,
  instructions, image), recherche insensible aux accents, exercices personnalisés.
- **Hors ligne et sauvegarde** : aucun compte, aucun serveur - toutes les données
  restent sur l'iPhone (SwiftData). Export/import JSON complet depuis les Réglages
  (programmes, historique, records, exercices personnalisés) pour ne jamais perdre
  ses données.

## Captures d'écran

| Accueil | Programmes | Séance | Pyramide | Progression |
|---|---|---|---|---|
| ![Accueil](docs/screenshots/accueil.png) | ![Programmes](docs/screenshots/programmes.png) | ![Séance](docs/screenshots/seance.png) | ![Pyramide](docs/screenshots/pyramide.png) | ![Progression](docs/screenshots/progression.png) |

## Stack technique

- **SwiftUI** (iOS 18 minimum), thème sombre forcé, navigation par `TabView` (5 onglets).
- **SwiftData** pour toute la persistance utilisateur (programmes, historique,
  records, séance en cours).
- **MuscuEngine** : package Swift Package Manager séparé (`Packages/MuscuEngine`)
  qui porte toute la logique métier pure et testable, sans dépendance à SwiftUI ni
  SwiftData : catalogue d'exercices, générateur de programme, calcul du 1RM,
  pyramide et repos adaptatif, intervalles, échauffement.
- Interface et contenu entièrement en français.

## Build

### MuscuEngine (bibliothèque Swift, tests unitaires)

```bash
cd Packages/MuscuEngine
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### Application iOS

Le projet Xcode est généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen)
à partir de `project.yml` (le `.xcodeproj` n'est pas versionné) :

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Muscu.xcodeproj -scheme Muscu \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  clean build
```

Pour lancer dans le simulateur : ouvrir `Muscu.xcodeproj` dans Xcode, ou installer
le `.app` généré via `xcrun simctl install`.

## Structure du projet

```
App/
  Sources/
    Models/         Entités SwiftData (Program, Prescription, Records, WorkoutLog...)
    Features/        Home, Programs, Workout, Exercises, Progress, Settings
    Services/        Export/import JSON, cache d'images, chrono de repos, détection de records
    MuscuApp.swift, RootTabView.swift, Theme.swift
  Resources/
    Assets.xcassets  Icône de l'app
Packages/
  MuscuEngine/       Package SPM : catalogue, générateur de programme, 1RM,
                     pyramide, intervalles, échauffement - 46 tests unitaires
docs/
  superpowers/       Spécification de design et plan d'implémentation
  screenshots/       Captures d'écran utilisées dans ce README
project.yml          Définition du projet Xcode (source de vérité, via XcodeGen)
```

## Statut

Phase 1 (usage personnel, simulateur) complète : les 5 onglets sont fonctionnels,
les 4 formats de séries sont couverts (classique, pyramide, intervalles, AMRAP),
avec échauffement, chrono de repos, records/historique/graphiques et export/import.

Phase 2 (hors du plan actuel) : installation sur iPhone réel via SideStore/AltStore,
puis activation optionnelle d'un générateur de programme par IA.
