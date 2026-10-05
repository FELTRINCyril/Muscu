# Muscu

Application iOS native de musculation, sombre et épurée, pour un usage personnel en
salle comme à la maison. Elle permet de créer des programmes d'entraînement, de
dérouler ses séances en direct avec un chrono de repos adaptatif, et de suivre sa
progression (records, 1RM, historique, graphiques). Toutes les données
personnelles restent hors ligne ; seules les images d’exercices sont téléchargées
à la demande depuis un snapshot public épinglé, puis mises en cache.

## Fonctionnalités

- **Profil** (facultatif) : objectif, niveau, matériel, jours disponibles, durée
  de séance, zones à ménager, unité d'affichage et **paliers de chargement
  réellement disponibles**. Le générateur et les règles de progression s'y
  adaptent ; l'application reste utilisable sans profil.
- **Programmes** : trois façons de construire un programme.
  - **Manuel** : création libre, séance par séance, exercice par exercice.
  - **Modèles** : splits classiques prêts à l'emploi (Full Body, Upper/Lower, PPL,
    Arnold...), éditables ensuite (remplacement d'exercice, séries, répétitions).
  - **Générateur** : un questionnaire (objectif, expérience, jours par semaine,
    durée de séance, matériel disponible, muscles prioritaires, zones à éviter)
    produit un programme complet et cohérent, prévisualisable avant import.
    Il peut aussi produire un **plan de 4 à 16 semaines** daté, avec
    périodisation linéaire, ondulatoire ou constante et semaines de décharge.
    Chaque choix est expliqué avant enregistrement, et le programme est vérifié
    par un validateur local (matériel, niveau, exclusions, zones à ménager,
    bornes de volume, récupération, durée estimée).
- **Planification et adaptation** :
  - **Plan** : calendrier des semaines et des séances datées, déplacement d'une
    séance et marquage (prévue, terminée, partielle, ignorée, reportée). Le
    planning ne modifie jamais l'historique déjà enregistré.
  - **Planning jour / semaine / mois** : séances prévues et réalisées côte à
    côte, chevauchements signalés sans jamais bloquer une décision volontaire,
    et proposition de replanification d'une séance manquée — appliquée
    uniquement après confirmation.
  - **Récurrence hebdomadaire** : jours, heure, dates de début et de fin,
    semaines de pause. L'heure reste l'heure locale : un changement de fuseau
    ou d'heure d'été ne décale rien.
  - **Rappels facultatifs** : avant la séance, le matin même, ou après une
    période sans entraînement. Rien n'est programmé sans autorisation
    explicite, et un rappel supprimé ne réapparaît jamais. Depuis la
    notification : démarrer, reporter à demain ou ignorer.
  - **Calendrier Apple** (facultatif) : export d'une séance vers le calendrier
    choisi. Muscu ne modifie que les événements qu'il a créés.
  - **Avant la séance** : check-in facultatif (énergie, sommeil, courbatures,
    stress, douleur) et suggestion expliquée. Une douleur déclenche un message
    prudent invitant à consulter un professionnel — jamais un diagnostic.
  - **Plateaux** : détection de stagnation avec sa fenêtre et son seuil
    affichés, puis décharge ou variante **proposées** — jamais appliquées sans
    votre accord, et annulables depuis le journal.
  - **Recalcul du plan** : les semaines à venir sont réalignées après
    confirmation ; les semaines déjà entamées ne bougent jamais.
  - **Progression expliquée** : huit règles sélectionnables (double progression,
    charge fixe, répétitions, séries, % du 1RM, cible de RIR, lesté/assisté,
    temporelle). Chaque proposition cite les performances qui la justifient,
    n'est appliquée qu'après votre accord, et reste **annulable** depuis le
    journal d'adaptation.
- **Rôles de série** : échauffement, approche, travail ou back-off. Une
  approche ou un back-off s'ajoute sans consommer de série prescrite ; seul le
  travail fait avancer la séance.
- **Test de 1RM guidé** (facultatif) : avertissement de sécurité, protocole
  construit sur une référence connue — jamais inventée — et résultat enregistré
  comme performance **mesurée**, distincte d'un 1RM estimé.
- **Séances en direct** : saisie rapide poids/répétitions, chrono de repos
  automatique avec notifications, reprise après interruption (kill de l'app en
  pleine séance). Les +/- de charge suivent le pas réellement disponible, le
  dépassement du repos s'affiche jusqu'à la série suivante, le repos par
  défaut distingue la barre des haltères / machines, et l'écran reste allumé
  pendant la séance (réglable).
  - **Valeur précédente par série** (« Préc. 80 kg × 8 ») : la même série de
    travail lors de la dernière séance comparable ; un tap recopie charge et
    répétitions sans valider.
  - **Dernières séances** de l'exercice en bandeau horizontal (« il y a
    3 sem. — 20 kg × 15, 9 »), lisible par VoiceOver.
  - **Record célébré en direct** (1RM estimé ou charge réellement portée),
    une fois par exercice et par séance, avec vibration ; respecte « Réduire
    les animations ». La fin de séance reste seule à enregistrer les records.
  - **Calculateur de disques** pour les exercices à la barre : disques par
    côté, dessin de la barre, charges voisines si la cible est impossible.
    Barre et disques possédés réglables (jeux standards kg et lb).
  - **Bips de fin de repos** : trois bips courts aux trois dernières secondes
    (si les sons sont activés), avec une vibration légère.
  - **Séance libre** depuis l'accueil, sans programme : les exercices
    s'ajoutent au fil de l'eau avec le sélecteur habituel, la séance se
    termine sur demande et rejoint l'historique comme les autres (records,
    Santé, résumé), reprise après interruption comprise.
  - **Ajouter un exercice** et **réordonner les exercices restants** en
    pleine séance, pour cette séance seulement. Un exercice déjà commencé ne
    bouge jamais.
  - **Séries au temps et à la distance** (gainage, portage, course) :
    chronomètre ou compte à rebours avec saisie manuelle, distance en mètres
    affichée en km au-delà de 1 000 m. Sans tonnage ; records de durée, de
    distance et de meilleur temps à distance égale.
  - **Repos réel** mesuré entre deux séries et affiché discrètement dans
    l'historique (non mesuré pour la première série ou après plus d'une
    heure d'interruption).
  - **Note d'effort de séance** (1 à 10, du « très facile » au « maximal »),
    facultative, en fin de séance ; affichée dans l'historique et exportée.
  - **Temps actif / temps de repos** dans le résumé de fin de séance et le
    détail de l'historique, à partir du repos réellement mesuré — rien
    n'est affiché quand une mesure manque.
  - **Mettre à jour le programme** : en fin de séance de programme, si la
    structure a changé (exercice ajouté, retiré, remplacé ou déplacé, nombre
    de séries, mesure), Muscu liste les écarts et propose de mettre à jour la
    séance du programme, de le garder tel quel ou d'enregistrer un nouveau
    modèle. Jamais les charges réalisées.
- **Historique modifiable** : corriger une séance passée (horaires, note
  d'effort, séries et exercices ajoutés, modifiés ou retirés) en mode édition
  explicite, avec confirmation qui annonce les records touchés. Les records
  sont recalculés sans régression, l'entraînement Santé est remplacé, la
  séance repart en synchronisation (la correction la plus récente gagne) et
  les widgets suivent.
- **Refaire une séance** de l'historique (« Refaire » avec les charges et
  répétitions comme cibles, ou « Refaire à vide ») : une séance libre
  préremplie, reprenable après interruption.
- **Partager une séance** en texte ou en carte image carrée au style de
  l'application : date, durée, exercices, séries et records — rien d'autre.
- **Calculateur de 1RM** (Records, fiche exercice) : charge × répétitions →
  1RM estimé et tableau 95-50 % arrondi au palier chargeable. Rien n'est
  enregistré ; le test de 1RM guidé reste la mesure.
- **Formats d'exercices** — tous pilotés par une machine à états unique
  (`MuscuEngine.WorkoutStateMachine`), reprenable à n'importe quelle transition :
  - **Classique** : séries/répétitions standard, avec suggestion de charge
    (progression de +2,5 kg après validation du haut de fourchette, dernière
    performance ou pourcentage du 1RM connu). L'éditeur de prescription
    choisit ce que mesure l'exercice : poids × répétitions (par défaut),
    temps, distance, ou temps + distance, avec une cible.
  - **Superset, triset, giant set, circuit** : exercices enchaînés A1 → A2 → …,
    repos court entre exercices et repos de fin de tour distincts, tour et
    exercice courants affichés, reprise exacte après fermeture de l'app.
  - **Dropset** : 1 à 5 paliers de baisse de charge, en pourcentage ou en kg,
    cumulatifs et arrondis au palier de chargement réellement disponible.
  - **Rest-pause** et **myo-reps** : série principale puis mini-séries, avec
    seuil d'arrêt, maximum configurable et arrêt manuel.
  - **Pyramide** : paliers libres (jusqu'à 30), repos **adaptatif** calculé
    selon l'intensité du palier fait par rapport au plus haut palier, ou
    choisi **palier par palier** (0 à 10 min). Le repos annoncé pendant la
    séance est exactement celui qui est lancé.
  - **Intervalles** et **EMOM** : blocs travail/repos chronométrés.
  - **AMRAP** : un maximum de répétitions dans un temps donné.
  - **For Time** : travail fixe, temps mesuré, plafond de temps facultatif.
  - **Échauffement** : montée en charge automatique avant l'exercice principal.
- **Lieux et matériel** : profils de lieu (domicile, salle, voyage,
  personnalisé) avec inventaire, charges minimale et maximale et incrément.
  Un inventaire vide ne masque rien. Les remplacements d'exercice proposés en
  séance tiennent compte du matériel réellement disponible, et chaque
  proposition cite ses raisons.
- **Photos de progression** : privées, stockées hors de la base, exclues des
  exports et de la sauvegarde iCloud, supprimées avec leur fichier.
- **Calendrier de chaleur** : séances, séries difficiles ou tonnage par jour,
  avec l'échelle, le maximum de la période et les données manquantes annoncés.
- **Bibliothèque** : recherche tolérante aux accents et aux fautes simples,
  filtres cumulables (muscle, matériel, catégorie, difficulté, tags, lieu),
  favoris, tags personnels et collections. Les annotations personnelles vivent
  à part du catalogue, qui reste en lecture seule.
  - **Habituels** en tête de la bibliothèque et du sélecteur d'exercice :
    classés selon la fréquence et la récence de vos séances (une séance d'il y
    a 30 jours compte pour moitié) ; l'ordre alphabétique reste inchangé
    dessous.
  - **Doublons** : un exercice personnalisé ou importé qui recoupe le
    catalogue ou un autre exercice (même nom, même nom d'import « Exercice
    (Matériel) », noms proches) est proposé à la fusion, paire par paire et
    après confirmation. Tout l'historique rejoint l'exercice conservé (séries,
    records — le meilleur des deux —, programmes, modèles, favoris, tags,
    collections, objectifs) ; le doublon est masqué et redirigé, jamais
    supprimé brutalement, et la redirection voyage par l'export et la
    synchronisation.
  - **Fiche exercice** : statistiques sur 4 / 12 semaines ou tout l'historique
    (meilleur 1RM estimé, force relative au poids de corps connu à la date,
    intensité moyenne en % du 1RM, charge moyenne), formules affichées, sans
    niveau « débutant / élite » inventé ; **lien de démonstration personnel**
    (http/https uniquement) ouvert dans le navigateur, la recherche vidéo
    restant proposée en repli.
- **Modèles** : enregistrer une séance ou un programme comme modèle, y compris
  depuis une séance terminée — sans recopier les charges ni les répétitions
  réalisées. Duplication, versions, archivage et partage par fichier.
- **Import / export inter-apps** : export CSV stable et documenté
  ([docs/formats/csv.md](docs/formats/csv.md)), et import CSV avec assistant de
  correspondance des colonnes, aperçu, détection des doublons et **quarantaine**
  des lignes illisibles. Préréglages Strong et Hevy. Le matériel écrit entre
  parenthèses (« Deadlift (Barbell) ») guide la correspondance avec le
  catalogue. Après l'import, chaque titre de séance peut devenir un modèle ou
  une séance d'un nouveau programme (exercices et nombre de séries usuel),
  avec aperçu et confirmation.
- **Coach IA** (facultatif, **désactivé par défaut**) : demande en français,
  brouillon prévisualisé et confirmé avant toute écriture, corrections
  appliquées affichées, repli annoncé sur le générateur local. Votre clé reste
  dans le Trousseau ; les catégories de données sensibles sont exclues par
  défaut et le partage se règle catégorie par catégorie.
- **Santé** (facultatif) : vos séances terminées sont écrites dans l'app Santé
  — une seule fois, même après plusieurs synchronisations — avec votre note
  d'effort, et votre poids peut être partagé dans les deux sens. Sur iOS 26 et
  plus, Santé suit la séance en direct (fréquence cardiaque d'une montre ou
  d'un capteur, énergie active, durée) ; la FC moyenne / min. / max. et les
  kcal rejoignent le résumé et l'historique. Masse grasse et tour de taille
  peuvent être importés, sans doublon. Ce que Muscu lit et écrit est annoncé
  avant la demande système ; un refus ne bloque aucune fonction.
- **Widgets et Live Activity** : la prochaine séance (avec un lien direct
  « Démarrer la prochaine séance »), la semaine écoulée et la dernière séance
  (date, durée, séries, tonnage, record ; un tap propose de la refaire) sur
  l'écran d'accueil. Sur l'écran verrouillé et dans la Dynamic Island, la
  séance en cours est interactive : exercice, série n/N, charge × répétitions
  prévues, série suivante, repos en décompte puis en dépassement (« +0:12 »),
  et les boutons « Valider la série », « Passer » et « +30 s ». « Valider »
  n'apparaît que pour une série classique dont la charge et les répétitions
  sont connues ; sinon le bouton ouvre l'application. Les widgets lisent un
  instantané qui ne contient que ce qu'ils affichent.
- **Apple Watch** : la séance en cours sur l'iPhone se suit au poignet —
  exercice, série n/N, charge × répétitions prévues (unité du profil), série
  suivante, repos en décompte puis en dépassement — avec « Valider la série »
  (charge et répétitions ajustables à la Digital Crown), « Passer » et
  « +30 s », exécutés sur l'iPhone par le même chemin que ses boutons ;
  iPhone injoignable, la commande est refusée plutôt que différée. Démarrez
  la prochaine séance ou une séance libre depuis la montre : elle démarre sur
  l'iPhone et se suit en miroir. Vibration aux trois dernières secondes et à
  la fin du repos. Si Santé est active, la montre enregistre la séance Santé
  (fréquence cardiaque, kcal, durée) — un seul entraînement par séance, relié
  à l'historique avec la FC moyenne / min. / max. Sans iPhone, la montre
  enregistre seule, sous le vrai nom des exercices de la prochaine séance ; la
  séance part dès qu'il est joignable et rejoint l'historique **une seule
  fois**. Complication : séance en cours ou prochaine séance.
- **Raccourcis et Siri** : démarrer la prochaine séance, ouvrir un programme ou
  un exercice, enregistrer le poids corporel (avec confirmation), lancer un
  minuteur de repos, afficher le résumé de la semaine, « Quel est mon 1RM ? »
  (estimé et de référence, avec leur date), « Mes records récents »,
  « Terminer la séance » et « Abandonner la séance » (toujours confirmés, par
  le même chemin que les boutons de l'application). Phrases en français et en
  anglais.
- **Saisie détaillée d'une série** (facultative, repliée par défaut) : effort
  ressenti (RIR), échec musculaire, commentaire, tempo et type de charge
  (externe, poids du corps, lesté, assisté) avec convention unilatérale.
- **Progression et suivi** : records par exercice (1RM estimé via la formule
  d'Epley, max de répétitions), détection automatique des performances battues en
  fin de séance, historique complet des séances.
  - **Tableaux de bord** : volume et séries difficiles par muscle et par semaine,
    tonnage, fréquence, adhérence au planning, répartition musculaire avec
    alertes de déséquilibre, comparaison de périodes, évolution par exercice
    (1RM estimé, charge max, répétitions, tonnage). Chaque graphique indique son
    **unité, sa période, sa formule** et le nombre de séries dont la donnée
    manque — « zéro » et « donnée absente » ne sont jamais confondus. Chacun
    expose une alternative textuelle lue par VoiceOver.
  - **Indice de force** : somme des meilleurs 1RM estimés de vos cinq
    exercices principaux sur la période, tendance ↑ / ↓ / = (zone neutre de
    ±1 %) face à la période précédente sur les exercices présents dans les
    deux ; un exercice sans donnée est exclu et nommé, jamais compté à zéro.
  - **Records du mois** : chaque exercice chargé du mois avec une barre
    « meilleure charge du mois / record historique », records battus en tête.
  - **Mesures corporelles** : poids, tours de taille/poitrine/bras/cuisse et
    autres, avec date, unité, source et commentaire.
  - **Objectifs** : fréquence, séries hebdomadaires par muscle ou poids visé,
    échéance facultative, avancement factuel, mise en pause et archivage sans
    réécrire l'historique.
  - Les records sont **typés** (charge, 1RM estimé, répétitions, tonnage, temps,
    tours) et **spécifiques à leur configuration** : un AMRAP de 8 minutes n'est
    jamais comparé à un AMRAP de 12 minutes, et une traction assistée ne crée
    jamais de faux record.
  - L'historique distingue explicitement exercices, tours et sous-séries.
- **Mes données** (Réglages) : export CSV séparé (séances, séries, mesures,
  check-in) en plus de l'export JSON complet, et **suppression par catégorie ou
  totale**, qui rend compte de ce qui a réellement été supprimé.
  - L'import propose **Fusionner** ou **Remplacer**. Le remplacement crée
    d'abord une sauvegarde de sécurité et restaure automatiquement si l'import
    échoue : rien n'est irréversible.
  - **Sauvegardes automatiques** (désactivées par défaut) : au plus une fois
    par jour, au passage en arrière-plan ou après une séance terminée, l'export
    JSON complet est écrit dans l'app Fichiers (Sur mon iPhone › Muscu ›
    Sauvegardes) ; les sept plus récentes sont gardées. Écran « Sauvegardes »
    avec date, taille, **Restaurer** (import en mode Remplacer) et
    **Partager**. Les photos de progression en restent exclues.
- **Multi-appareils** : application universelle iPhone / iPad / Mac Catalyst,
  avec onglets en largeur compacte et barre latérale en largeur régulière
  (raccourcis ⌘1–⌘5). Les deux présentations affichent les mêmes écrans.
  - La **synchronisation iCloud** est implémentée en local-first : file
    d'attente persistante, backoff, tombstones, conflits visibles et
    diagnostic exportable sans donnée personnelle. Elle est **désactivée tant
    qu'un conteneur CloudKit n'a pas été configuré** — voir
    [docs/configuration/icloud.md](docs/configuration/icloud.md). L'application
    fonctionne intégralement hors ligne sans elle.
- **Catalogue** : 873 exercices en français (nom, muscles, matériel, catégorie,
  instructions, image), recherche insensible aux accents, exercices personnalisés.
- **Hors ligne et sauvegarde** : aucun compte, aucun serveur - toutes les données
  restent sur l'iPhone (SwiftData). Export/import JSON complet depuis les Réglages
  (programmes, historique, records, exercices personnalisés, réglages et séance
  active) avec validation et aperçu avant confirmation.
  - Format d'archive **v3** : enveloppe `{ version, exportedAt, manifest, payload }`
    dont le manifeste porte les compteurs par type et une somme de contrôle SHA-256
    du contenu. Une archive tronquée ou modifiée est refusée avant toute écriture.
  - Les archives **v1 et v2** restent importables ; les champs absents prennent une
    valeur neutre plutôt qu'une valeur devinée.
  - L'import est **idempotent** : réimporter la même sauvegarde ne crée aucun doublon.

## Captures d'écran

| Accueil | Programmes | Séance | Pyramide | Progression |
|---|---|---|---|---|
| ![Accueil](docs/screenshots/accueil.png) | ![Programmes](docs/screenshots/programmes.png) | ![Séance](docs/screenshots/seance.png) | ![Pyramide](docs/screenshots/pyramide.png) | ![Progression](docs/screenshots/progression.png) |

## Stack technique

- **SwiftUI** (iOS 18 minimum), thème sombre forcé, navigation adaptative
  (onglets en compact, barre latérale en régulier) sur iPhone, iPad et Mac Catalyst.
- **SwiftData** pour toute la persistance utilisateur (programmes, historique,
  records, séance en cours, profil, mesures, check-in, planning). Le schéma est
  versionné (`MuscuSchemaV1` → `V2` → `V3`) avec un plan de migration testé sur
  des stores figés : cf. `docs/decisions/0001-schema-v3-et-migrations.md`.
- **MuscuEngine** : package Swift Package Manager séparé (`Packages/MuscuEngine`)
  qui porte toute la logique métier pure et testable, sans dépendance à SwiftUI ni
  SwiftData : catalogue d'exercices, générateur de programme, calcul du 1RM,
  pyramide et repos adaptatif, intervalles, échauffement, ainsi que les règles
  transversales du modèle v3 — types de charge et calculs associés (`SetMetrics`),
  unités (le **kilogramme** est la valeur canonique stockée), tempo et RPE/RIR,
  politique de fusion pour la synchronisation — ainsi que toute la
  programmation : machine à états du déroulé (`WorkoutStateMachine`), moteur de
  progression, périodisation, détection de plateau, conseil de forme et
  validateur de programme.
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
Shared/             Code partagé app / widgets / Watch (App Group, instantané)
Widgets/            Extension WidgetKit et Live Activity
Watch/              Application watchOS à cible unique (miroir, séance Santé)
WatchWidgets/       Complication de la montre (WidgetKit)
Packages/
  MuscuEngine/       Package SPM : catalogue, générateur de programme, 1RM,
                     pyramide, intervalles, échauffement, règles du modèle v3
                     (Domain/, Runner/, Programming/, Analytics/, Sync/,
                     Planning/, Places/, Library/, Interop/, AI/, Health/)
                     - 429 tests unitaires
Tests/
  Fixtures/          Stores SwiftData figés (migration) et exports v1/v2 (import)
docs/
  roadmap/           Plan produit complet et plan d'exécution par phases
  decisions/         Journal des décisions d'architecture et de migration
  formats/           Formats d'échange documentés (CSV d'export et d'import)
  configuration/     Étapes externes requises (conteneur iCloud, signature)
  superpowers/       Spécification de design et plan d'implémentation
  screenshots/       Captures d'écran utilisées dans ce README
project.yml          Définition du projet Xcode (source de vérité, via XcodeGen)
```

## Statut

Le produit livré aujourd'hui couvre les 5 onglets, les 4 formats de séries
(classique, pyramide, intervalles, AMRAP), l'échauffement, le chrono de repos,
les records/historique/graphiques et l'export/import.

La suite du développement suit `docs/roadmap`, phase par phase. L'avancement
réel est tenu à jour dans [docs/roadmap/09-execution-plan.md](docs/roadmap/09-execution-plan.md) :
une case n'est cochée que lorsque tous les critères de la phase sont vérifiés.

Avant une diffusion publique, il reste à signer l'application avec le compte
développeur choisi, valider une archive Release sur un iPhone physique et
effectuer les vérifications administratives App Store.
