# 09 — Plan d’exécution et définition de fini

## Règle générale

Implémenter la roadmap par incréments verticaux utilisables. Chaque phase inclut
modèle, persistance, interface, migration, tests et documentation. Ne pas regrouper
toute la roadmap dans un changement impossible à relire.

## Suivi

Mettre à jour cette liste uniquement après validation des critères de la phase :

- [x] Phase 0 — État de référence figé et reproductible
- [x] Phase 1 — Fondations et modèle v3
- [x] Phase 2 — Formats avancés et runner unifié
- [x] Phase 3 — Programmation, périodisation et adaptation
- [x] Phase 4 — Profil, mesures et analyses
- [~] Phase 5 — iCloud, iPad et Mac (iPad et Mac faits ; iCloud prêt mais non
      activable sans conteneur CloudKit — action externe requise)
- [x] Phase 6 — Planning, notifications, contenus et imports
- [~] Phase 7 — Watch, widgets, Live Activities et HealthKit (tout est
      implémenté et exécuté en simulateur ; la validation sur appareils
      réels, exigée par le jalon, reste à faire)
- [~] Phase 8 — Coach IA sécurisé (protocole, mock, validation locale et mode
      BYOK faits ; backend géré non implémenté — décisions externes requises)
- [ ] Phase 9 — Accessibilité, performance, confidentialité et Release

## Phase 0 — Référence

1. Lire l’architecture, le statut git et les modifications existantes.
2. Exécuter les tests engine/app/UI disponibles et un build Release.
3. Noter versions Xcode/Swift, destinations et éventuels échecs préexistants.
4. Créer une branche dédiée seulement si cela ne déplace ni n’écrase le travail courant.
5. Ne modifier aucune configuration de signature sans nécessité documentée.

Livrable : état de référence vérifiable et liste courte des risques.

### État de référence constaté (12/09/2026)

- Xcode 26.6 (17F113), Swift 6.3.3, XcodeGen 2.46.0, cible iOS 18.
- Destination de test : `platform=iOS Simulator,name=iPhone 17 Pro`.
- `swift test` (MuscuEngine) : 50 tests, 9 suites — vert.
- `MuscuTests` : 13 tests — vert.
- `MuscuUITests` : 16 tests, **2 échecs préexistants** dans `ProgramsFlowTests`
  (`testCreateFromScratchEditSessionAndPrescription`,
  `testGeneratorWizardAllSteps`).
- Build Release (`generic/platform=iOS Simulator`) : succès.

Les deux échecs UI étaient des taps synthétisés perdus (barre d'onglets,
bouton de barre d'outils, segment de format) et non des régressions produit :
ils sont corrigés par un helper `selectTab` et l'usage de `tapUntilReveals`
là où un tap peut se perdre. La suite UI est verte depuis.

Branche : travail poursuivi sur `codex/fix-audit-findings`, qui portait déjà
des modifications non commitées. Créer `codex/complete-product-roadmap` aurait
déplacé ce travail en cours : la consigne de ne rien écraser prime.

## Phase 1 — Fondations

Implémenter les entités et identifiants de `01`, les migrations et l’export v3.
Extraire les règles métier de SwiftUI vers `MuscuEngine`. Conserver la lecture des
exports v1/v2 et le parcours actuel pendant la migration.

Jalon : données existantes migrées sans perte, round-trip export v3 testé.

### Réalisé (12/09/2026)

- Schémas figés `MuscuSchemaV1` / `MuscuSchemaV2` et schéma courant
  `MuscuSchemaV3`, plan de migration à deux étapes légères.
- Entités v3 : `AthleteProfile`, `BodyMeasurement`, `ReadinessEntry`,
  `PersonalBest`, `HealthWorkoutLink`, `ExerciseGroup`, `TrainingPlan`,
  `TrainingBlock`, `TrainingWeek`, `ScheduledWorkout` ; métadonnées de
  synchronisation (`createdAt`/`updatedAt`/`deletedAt`) sur les entités
  existantes.
- Règles métier extraites vers `MuscuEngine` : `LoadKind`/`SetMetrics`,
  `Units` (kilogramme canonique), `Tempo`/`EffortRating`/`SetRole`,
  `ProgressionRule`, `MergePolicy`, `ExerciseClassification`.
- Export v3 avec manifeste (compteurs + somme de contrôle SHA-256) ; import
  v1/v2/v3 validé avant mutation, idempotent, annulé en bloc en cas d'erreur.
- Tests de migration sur deux stores figés, tests d'import des formats v1/v2,
  tests de falsification d'archive.
- Décision consignée : `docs/decisions/0001-schema-v3-et-migrations.md`.

Résultats : MuscuEngine 120 tests verts, MuscuTests 35 tests verts,
MuscuUITests 16 tests verts, builds Debug et Release réussis.

## Phase 2 — Exécution avancée

Construire le modèle `WorkoutNode` et la machine à états. Livrer d’abord superset,
puis circuit, dropset/rest-pause/myo-reps, pyramides et formats chronométrés. Chaque
format reçoit historique et tests de reprise avant le suivant.

Jalon : les formats de `02` sont créables, exécutables et reprenables.

### Réalisé (12/09/2026)

- `MuscuEngine` : `WorkoutPlan` / `WorkoutNode` / `WorkoutPosition` et
  `WorkoutStateMachine`, seule autorité sur l'étape courante, l'avancement et
  le repos à lancer. `SessionDuration` partage l'estimation de durée entre
  l'accueil, l'éditeur de groupe et le générateur.
- Formats livrés avec leur écran : superset / triset / giant set / circuit,
  dropset, rest-pause, myo-reps, pyramide, intervalles, EMOM, AMRAP, For Time.
- Éditeur de séance : création d'un groupe depuis une sélection, réglages
  (type, tours, repos entre exercices et entre tours, transition), conversion
  vers un type compatible, sortie d'un exercice, dissociation, duplication.
- Runner : aperçu de séance avec navigation vers un exercice passé ou à venir,
  correction de la dernière série, ajout/retrait de série ou de tour sans
  toucher au programme source, substitution conservant prévu **et** réalisé.
- Saisie détaillée facultative : effort (RIR), échec musculaire, commentaire.
- Historique distinguant exercices, tours et sous-séries ; records typés et
  spécifiques à leur configuration (`PersonalBestUpdater`).
- Récupération d'un store illisible (`StoreRecovery`) : export d'une copie de
  secours depuis l'alerte, sans jamais supprimer l'original.
- Décision consignée : `docs/decisions/0002-runner-unifie.md`.

Deux défauts réels trouvés par les tests et corrigés : la correction de la
dernière série se fondait sur l'ordre d'AFFICHAGE (faux dans un superset) —
d'où l'ajout d'un rang de saisie explicite `CompletedSet.sequenceIndex` ; et la
position de reprise était reconstruite en rejouant la machine à états, ce qui
est impossible pour un rest-pause dont la sortie dépend des résultats saisis.

Résultats : MuscuEngine 127 tests verts, MuscuTests 61 tests verts,
MuscuUITests 18 tests verts, builds Debug et Release réussis sans avertissement
nouveau.

## Phase 3 — Programmation

Ajouter profil, blocs, semaines, règles de progression, décharge et adaptations.
Étendre le générateur local avant l’IA afin de disposer d’un validateur et fallback.

Jalon : programme de plusieurs semaines déterministe et progression explicable.

### Réalisé (13/09/2026)

- `MuscuEngine/Programming/` : `ProgressionEngine` (8 règles, chaque proposition
  portant ses facteurs), `Periodization` (linéaire, ondulatoire, constante, avec
  décharges), `PlanGenerator` (plan de 4 à 16 semaines daté, déterministe),
  `ProgramValidator` (contraintes matérielles, niveau, exclusions, zones à
  ménager, volume, récupération, durée), `ReadinessAdvisor` et `PlateauDetector`.
- App : écran **Profil**, étape « plan » du générateur, **calendrier de plan**
  (déplacement et états de séance), écran **Avant la séance** (check-in +
  propositions expliquées), **journal d'adaptation** avec annulation.
- `AdaptationEntry` conserve proposition, facteurs, décision et valeurs
  avant/après ; l'export v3 l'inclut.
- Décision consignée : `docs/decisions/0003-programmation-et-adaptation.md`.

Trois défauts réels trouvés par les tests et corrigés : `TrainingWeek.isDeload`
se déduisait d'un volume réduit, ce qui classait à tort les semaines
d'intensification en décharge ; `--uitest-reset` ne purgeait pas les entités
ajoutées en phases 1 et 3, rendant la suite UI dépendante de son ordre
d'exécution (désormais gardé par un test unitaire) ; `ProfileView` conservait le
profil dans un `@State`, qui n'observe pas un modèle SwiftData et laissait
l'écran figé sur d'anciennes valeurs.

Résultats : MuscuEngine 205 tests verts, MuscuTests 80 tests verts,
MuscuUITests 21 tests verts, builds Debug et Release réussis sans avertissement
nouveau.

## Phase 4 — Suivi

Ajouter mesures, objectifs et calculs partagés, puis tableaux de bord. Reporter
HealthKit à la phase 7 pour limiter les permissions pendant la stabilisation.

Jalon : indicateurs cohérents, exportables et performants sur gros historique.

### Réalisé (13/09/2026)

- `MuscuEngine/Analytics/` : `TrainingAnalytics` (volume et séries difficiles
  par muscle et par semaine, tonnage, densité, séries par exercice, fréquence,
  séries consécutives, adhérence, répartition, déséquilibres, comparaison de
  périodes) et `GoalEvaluator`. `AnalyticsBridge` est le seul pont
  SwiftData → moteur : deux vues ne peuvent plus diverger.
- `ChartsView` réécrit sur ces calculs : unité, période, formule, données
  manquantes et alternative textuelle VoiceOver sur chaque carte.
- Mesures corporelles (saisie, liste, évolution) et objectifs (création,
  avancement factuel, pause, archivage).
- Écran **Mes données** : export CSV (séances, séries, mesures, check-in) et
  suppression par catégorie ou totale, avec compte rendu de ce qui a été
  supprimé.
- Décision consignée : `docs/decisions/0004-suivi-et-analyses.md`.

Deux défauts réels trouvés par les tests et corrigés : `ChartsView` recalculait
ses propres formules et ignorait les types de charge (une traction assistée
alimentait la courbe de 1RM) ; `MeasurementsView`, affichée comme SEGMENT de
l'onglet Progression, posait son propre `navigationTitle` et écrasait celui du
parent, cassant la navigation par onglets.

HealthKit reste volontairement reporté en phase 7, conformément à ce plan.

Résultats : MuscuEngine 238 tests verts, MuscuTests 99 tests verts,
MuscuUITests 24 tests verts, builds Debug et Release réussis sans avertissement
nouveau.

## Phase 5 — Cloud et grands écrans

Mettre en place la synchronisation derrière un feature flag, tests à deux stores,
écran d’état, iPad puis Mac Catalyst. Activer Production CloudKit uniquement après
validation réelle et procédure de rollback.

Jalon : scénario deux appareils hors ligne/en ligne sans doublon ni perte.

### Réalisé (13/09/2026)

**Fait et vérifié**

- `MuscuEngine/Sync/` : `SyncRecord` (racines d'agrégat et stratégie de fusion
  par type), `SyncReconciler` (décisions, application idempotente, insensible à
  l'ordre d'arrivée), `SyncOutbox` (file persistante, backoff exponentiel),
  `SyncStatus`.
- `SyncService` local-first, `SyncSerialization` réutilisant les DTO de
  l'export v3, `InMemorySyncTransport` pour les tests à deux stores.
- **14 tests à deux appareils** : hors ligne, ordre inversé, rejeu, suppression
  concurrente, modification concurrente avec conflit visible, historique
  immuable, changement de compte, diagnostic sans donnée personnelle.
- Écran *Réglages → Synchronisation* : état, file d'attente, conflits à
  trancher, diagnostic exportable.
- Import **Fusionner / Remplacer** avec sauvegarde de sécurité automatique et
  restauration en cas d'échec.
- Application **universelle** : `TARGETED_DEVICE_FAMILY "1,2"` et
  `SUPPORTS_MACCATALYST`. Navigation adaptative (onglets / barre latérale,
  raccourcis ⌘1–⌘5). Builds Debug **et** Release vérifiés sur iPhone, iPad et
  Mac Catalyst, sans avertissement.
- Décision consignée : `docs/decisions/0005-synchronisation-icloud.md`.

**Non validé, car dépendant d'une action externe**

La synchronisation réelle avec iCloud n'a jamais été exécutée. `CloudKitSyncTransport`
est un squelette qui renvoie `notConfigured` ; la conversion vers `CKRecord`
n'est volontairement pas écrite. L'écran de synchronisation n'affiche donc
aucun interrupteur et annonce clairement son indisponibilité.

Étapes attendues du propriétaire : `docs/configuration/icloud.md`.

Cette case ne sera cochée qu'après validation sur deux appareils réels avec un
compte iCloud de test, puis promotion du schéma en Production.

## Phase 6 — Quotidien et échanges

Livrer planning interne, notifications, profils de lieux, bibliothèque, modèles,
CSV et EventKit/App Intents facultatifs.

Jalon : une semaine peut être planifiée, déplacée, rappelée et exportée.

### Réalisé (13/09/2026)

**Modèle**

- Schéma **v4** obtenu en FIGEANT d'abord le v3
  (`App/Sources/Models/SchemaVersions/MuscuSchemaV3.swift`, 21 modèles copiés,
  valeurs par défaut en littéral). Migration V3 → V4 légère : huit nouveaux
  modèles et quelques attributs facultatifs, aucune donnée transformée.
- Un test écrit un store avec le schéma v3 figé puis l'ouvre avec le schéma
  courant : c'est la seule façon de vérifier l'étape telle qu'elle se produira
  chez un utilisateur déjà à jour.
- Export JSON **v4** (lieux, récurrences, modèles, favoris/tags, collections),
  toujours capable de lire les archives v1, v2 et v3.

**Moteur** (`MuscuEngine/Planning`, `Places`, `Library`, `Interop`)

- `WeeklyRecurrence` / `RecurrenceExpander` : jours, bornes, semaines de pause.
  L'expansion avance jour par jour AVEC le calendrier puis pose l'heure voulue ;
  un calcul en secondes décalerait tout d'une heure au changement d'heure.
- `ScheduleConflictDetector` (même jour, récupération insuffisante) et
  `RescheduleAdvisor` (séances manquées, proposition expliquée).
- `NotificationPlanner` : sans autorisation, le plan est VIDE — l'invariant est
  vérifiable par un test. `reconcile` ne reprogramme jamais un rappel supprimé.
- `EquipmentInventory` (charges praticables, inventaire vide permissif) et
  `SubstitutionFinder` (classement déterministe, chaque proposition porte ses
  raisons).
- `TextMatching` (Damerau-Levenshtein) et `LibrarySearch` : recherche unique,
  partagée par l'onglet Exercices, le remplacement en séance et Siri.
- `CSVParser` (RFC 4180 étendu) et `CSVImportPlanner` (correspondance des
  colonnes, préréglages Strong/Hevy, doublons, quarantaine).

**Application**

- Planning jour / semaine / mois, déplacement par balayage, menu contextuel ET
  action d'accessibilité ; chevauchements signalés sans jamais bloquer ;
  replanification des séances manquées uniquement après confirmation.
- Récurrences avec rappels par récurrence, interrupteur global dans Réglages.
- Échanges avec l'app Calendrier : export vers un calendrier choisi, retrait
  des seuls événements créés par Muscu, import d'un créneau décrit par
  l'utilisateur.
- Lieux et inventaire ; substitutions classées et expliquées, appliquées au
  programme uniquement après confirmation explicite.
- Bibliothèque : recherche tolérante, filtres cumulables, favoris, tags,
  collections.
- Modèles de séance et de programme, création depuis une séance terminée
  **sans** recopier les performances, duplication, versions, archivage,
  partage par fichier.
- Assistant d'import CSV avec aperçu, rapport et quarantaine consultable.
- App Intents : prochaine séance, programme, exercice, poids corporel (avec
  confirmation), minuteur de repos, résumé hebdomadaire ; phrases FR et EN.
- Décision consignée : `docs/decisions/0006-planning-et-integrations.md`.
  Format CSV documenté : `docs/formats/csv.md`.

**Deux défauts réels trouvés par les tests et corrigés**

- Le lecteur CSV ne découpait jamais un fichier Windows : Swift regroupe CR+LF
  en UN SEUL `Character`, et la boucle ne voyait donc ni `\r` ni `\n`. Le
  fichier entier était lu comme une seule ligne.
- `ISO8601DateFormatter` avec `withFullDate` acceptait « 2026-01-05 18:00:00 »
  en n'en lisant que la date : l'heure disparaissait en silence, au point de
  casser la déduplication à l'import. Les formats explicites passent désormais
  avant la date seule.

**Une limite assumée, non contournée**

La roadmap demande « erreurs fréquentes et variantes » par exercice. Les
variantes sont CALCULÉES depuis le catalogue (mêmes muscles principaux, même
type de mouvement) et affichées avec leur raison. Les erreurs fréquentes ne
sont pas affichées : aucune source ne les fournit, et les inventer produirait
un conseil technique fabriqué. Cela relève des contenus éditoriaux déjà listés
comme dépendance externe.

Résultats : MuscuEngine 347 tests verts, MuscuTests 195 tests verts,
MuscuUITests 35 tests verts (1 ignoré, spécifique iPad), builds Debug **et**
Release réussis sur iPhone, iPad et Mac Catalyst sans avertissement.

## Écarts fermés après la phase 6 (13/09/2026)

Six éléments spécifiés dans la roadmap restaient non livrés alors que leur
phase était cochée. Aucun ne dépendait d'une action externe.

- **Séries d'approche et de back-off** (`02`) : rôle choisi à la saisie. Une
  série d'approche ou de back-off s'AJOUTE sans consommer de série prescrite ;
  le back-off compte dans le volume, l'approche non. L'historique affiche le
  rôle au lieu d'un numéro de série qui serait faux.
- **Test de 1RM guidé** (`03`) : avertissement de sécurité affiché AVANT le
  protocole, protocole construit sur une référence connue et refusé sans elle,
  tentatives strictement croissantes, résultat enregistré comme performance
  mesurée et distinct d'un 1RM estimé.
- **Recalcul des séances futures** (`03`) : aperçu confirmé avant écriture,
  semaines déjà entamées listées et laissées intactes, historique jamais
  touché. Le plan conserve désormais son style de périodisation ; un plan plus
  ancien ne voit que ses dates réalignées, faute de pouvoir deviner le reste.
- **Photos de progression** (`06`) : stockées hors de la base, exclues de la
  sauvegarde iCloud et des exports, supprimées avec leur fichier.
- **Calendrier de chaleur** (`06`) : trois grandeurs, définition, échelle et
  maximum affichés ; un jour sans donnée n'est pas un jour à zéro.
- **Détection de plateau** (`06`) : écran dédié, fenêtre et seuil visibles,
  décharge ou variante proposées et jamais appliquées sans accord, décisions
  journalisées et annulables.

Un défaut réel trouvé par les tests : `UIGraphicsImageRenderer` suit l'échelle
de l'écran par défaut ; une photo « réduite à 1 600 px » était stockée en
4 800 px sur un appareil 3x, soit trois fois le poids voulu.

Schéma **v5** : le v4 a d'abord été figé (29 modèles), puis un modèle et deux
attributs facultatifs ajoutés. Décision consignée :
`docs/decisions/0007-reliquat-et-schema-v5.md`.

## Phase 7 — Écosystème Apple

Ajouter HealthKit, cible Watch, App Group, widgets et Live Activities. Vérifier
autonomie, permissions, expiration et déduplication sur appareils réels.

Jalon : une séance Watch rejoint l’historique une seule fois et la Live Activity expire proprement.

### Réalisé (14/09/2026)

**Fait et vérifié**

- **HealthKit** : écriture des séances terminées, lecture et écriture du poids
  corporel, `HealthWorkoutLink` pour la déduplication, réconciliation des
  suppressions. L'autorisation est expliquée AVANT la demande système et n'est
  déclenchée que par l'activation de l'interrupteur. Un refus n'active rien,
  ne supprime rien, ne bloque rien ; un appareil sans Santé est traité comme
  indisponible, pas comme un refus.
- **App Group** `group.com.cyril.Muscu` : conteneur partagé entre
  l'application, ses widgets et la montre.
- **Widgets** (prochaine séance, semaine écoulée) alimentés par un instantané
  écrit par l'application. Les widgets ne lisent jamais la base, et
  l'instantané ne contient que ce qu'ils affichent — vérifié par un test.
- **Live Activity** de séance en cours : elle se termine à la fin ET à
  l'abandon, porte une péremption de quatre heures, et toute activité restée
  ouverte après un arrêt brutal est fermée au démarrage.
- **Application Watch** à cible unique, embarquée dans l'app iOS :
  enregistrement de séries, envoi en file d'attente vers l'iPhone, état vide
  explicite quand rien n'a été reçu. **Installée et lancée** sur un simulateur
  Apple Watch Series 11.
- **Déduplication du transfert** : l'identifiant est frappé à la montre et
  devient l'identifiant unique de la séance. Rejouer un transfert dix fois
  n'ajoute rien.
- Décision consignée : `docs/decisions/0009-ecosysteme-apple.md`.

**Deux défauts réels trouvés en exécutant**

- L'extension widget compilait mais **refusait de s'installer** : son
  `Info.plist` écrit à la main n'avait pas de `CFBundleExecutable`.
- `--uitest-reset` ne réinitialisait ni les réglages Santé ni l'instantané des
  widgets : l'état d'un test survivait au suivant. Même défaut que celui
  trouvé en phase 8 pour le coach IA, sur d'autres clés.

**Non validé, car dépendant d'appareils réels**

Le jalon exige une vérification sur appareils réels. Ne sont PAS démontrés :
l'autonomie pendant une séance Watch, la livraison différée d'un transfert
quand l'iPhone est réellement hors de portée, l'expiration de la Live Activity
sur un écran verrouillé physique, HealthKit avec des données réelles et
plusieurs sources d'écriture, et le rendu des widgets sur un vrai écran
d'accueil.

Cette case ne sera cochée qu'après ces vérifications, qui demandent une équipe
Apple Developer, un iPhone et une Apple Watch appairés.

## Phase 8 — IA

Créer d’abord protocole, mock, schémas et validation locale. Ajouter ensuite le mode
BYOK, puis éventuellement le backend géré. L’IA reste derrière un feature flag tant
que sécurité, politique de confidentialité et évaluations ne sont pas validées.

Jalon : génération/adaptation structurée, consentie, validée et avec fallback local.

### Réalisé (14/09/2026)

**Fait et vérifié**

- `MuscuEngine/AI/` : schémas versionnés (`AICoachRequest` / `AICoachResponse`),
  assainissement des contenus non fiables, validation locale avec réparation
  **bornée**, filtre de sécurité (progression > 10 %, valeurs impossibles),
  consentement granulaire et garde-fou de budget mensuel.
- Protocole `AICoachService` : service mock déterministe pour tests et
  previews, service distant en mode **BYOK** (clé dans le Trousseau).
- `AICoachCoordinator` : consentement, budget, assainissement, envoi, contrôle
  de schéma, validation, filtre de sécurité, puis repli déterministe sur le
  générateur local. Aucune étape n'est optionnelle.
- Écrans : demande et aperçu du brouillon (rien n'est écrit sans confirmation),
  réglages (drapeau, fournisseur, consentement par catégorie, budget, journal),
  journal technique expurgé.
- Faux fournisseur HTTP : codes 401/429/500, réponse tronquée, texte libre,
  schéma inconnu, mauvaise capacité, dépassement de délai et annulation.
- Corpus d'évaluation : huit combinaisons objectif × niveau × matériel × durée
  × restrictions, vérifiant le déterminisme du repli local et le refus des
  propositions hors contraintes.
- Suppression : catégorie « Coach IA » effaçant réglages, consentement, usage,
  journal **et** clé du Trousseau.
- Décision consignée : `docs/decisions/0008-coach-ia.md`.

**Un défaut réel trouvé par un test UI**

`--uitest-reset` vidait SwiftData mais ni `UserDefaults` ni le Trousseau :
l'état du coach IA d'un test survivait au suivant, et le harnais mentait sur
ce qu'il réinitialisait.

**Non validé, car dépendant d'une action externe**

- Le **backend géré** n'est pas implémenté : il suppose des décisions de
  conservation, de région, de fournisseur et de facturation qui appartiennent
  au propriétaire. Écrire un client pour un service inexistant produirait du
  code jamais exécuté.
- Le mode **BYOK n'a jamais été exécuté contre un vrai fournisseur**. Le
  comportement de l'application est couvert par un faux service ; l'essai réel
  avec une clé reste à faire.

Cette case ne sera cochée qu'après un essai réel et la publication d'une
politique de confidentialité décrivant fournisseur, région et conservation.

## Phase 9 — Distribution

Fermer les écarts d’accessibilité, localisation, performance, confidentialité et CI.
Tester migrations, archives et TestFlight sur chaque famille d’appareils annoncée.

Jalon : checklist de `08` complète et archive Release distribuable.

### Réalisé (14/09/2026)

**CI reproductible.** `Scripts/ci.sh` est le point d'entrée unique :
génération du projet, contrôle de localisation, tests du moteur, tests
unitaires de l'application, suite UI optionnelle, puis builds Release pour
iPhone, iPad, Mac Catalyst et watchOS, avec refus de tout avertissement
nouveau provenant de nos propres sources. `.github/workflows/ci.yml`
l'appelle tel quel : « vert en local » et « vert en CI » veulent dire la même
chose.

La CI a trouvé trois vrais défauts dès ses premiers passages :

1. `CODE_SIGNING_ALLOWED=NO` retire les entitlements, donc le groupe
   d'applications, donc quatre tests de widgets échouaient. La signature
   ad hoc est conservée pour le simulateur ; seul Mac Catalyst s'en passe.
2. `ActivityKit` **se compile** sur Mac Catalyst mais chacun de ses symboles
   y est indisponible : `canImport` ne suffit pas, il faut
   `!targetEnvironment(macCatalyst)`. `WorkoutActivityController` a désormais
   un repli explicite.
3. macOS refuse d'embarquer un binaire iOS ou watchOS : `MuscuWidgets` et
   `MuscuWatch` portent `platformFilter: iOS`.

**Localisation français/anglais.** Le français reste la langue source ; un
catalogue de chaînes par bundle porte l'anglais (918 chaînes pour
l'application, 14 pour les widgets, 18 pour la montre). 138 littéraux qui
vivaient **hors des vues** — titres d'onglets, catégories de suppression,
modes d'import, messages d'erreur — passent par `String(localized:)` : sans
cela, `Text(uneVariable)` affiche la chaîne telle quelle et la traduction ne
s'applique jamais. `Scripts/check-localization.py` refuse une traduction
manquante, restée à l'état `new`, ou dont les spécificateurs de format
diffèrent de la source. `Scripts/sync-strings.sh` régénère les catalogues
sans ouvrir Xcode.

**Journal de diagnostic.** `MuscuEngine/Diagnostics` porte la logique
testable : journal borné à 200 lignes, expurgation appliquée à la
construction de chaque évènement (adresses, jetons, noms de compte dans les
chemins, longues suites de chiffres), rapport limité aux versions, compteurs,
dates et codes d'erreur. `PersistenceSupport` étant le point unique de
sauvegarde, aucun échec de stockage ne passe inaperçu. Couper le journal
efface aussi les lignes déjà écrites, et `DataDeletion` gagne une catégorie
`diagnostics` pour que la « suppression totale » reste vraie.

**Dynamic Type.** Les quatorze `Font.system(size:)` figés du runner passent
par `scaledSystemFont` / `timerFont` (`@ScaledMetric`) : les gros chiffres
suivent enfin le réglage système, et se réduisent au lieu de se tronquer là
où le gabarit est fixe.

**Performance et robustesse.** `PerformanceAndRobustnessTests` (12 tests)
travaille sur trois ans d'historique — 468 séances de 15 séries.
`DecodingFuzzTests` (5 tests) attaque le décodage avec un générateur
pseudo-aléatoire déterministe.

**Documentation.** `docs/decisions/0010-localisation-et-diagnostic.md`,
`docs/qualite/localisation.md`, `docs/qualite/accessibilite.md`,
`docs/qualite/preparation-app-store.md`,
`docs/confidentialite/inventaire-des-donnees.md`,
`docs/securite/modele-de-menaces.md`.

### Limites, écrites précisément

- **Les phrases produites par `MuscuEngine` restent en français** dans une
  application anglaise (justifications de progression, rationnel d'un plan,
  avertissements du validateur, motifs de quarantaine, messages de
  synchronisation et du coach IA). Mesuré, pas supposé : SwiftPM ne compile
  pas les catalogues de chaînes, et le paramètre `locale:` de
  `String(localized:bundle:locale:)` ne choisit pas la langue de recherche.
  Aucun moyen d'épingler la langue dans `swift test` : une trentaine de tests
  du moteur deviendraient dépendants de la langue de la machine de CI. La
  correction est de faire renvoyer au moteur des résultats **structurés** et
  de laisser les mots à l'application — un incrément à part entière.
- **Aucun audit avec VoiceOver réellement activé**, ni parcours clavier
  complet sur iPad/Mac : demande une revue manuelle sur appareil.
- **Archive Release signée, TestFlight et validation sur appareils réels** :
  bloqués par l'absence de compte Apple Developer payant.
- Les captures d'écran App Store dans les deux langues restent à produire une
  fois les écrans figés.

## Dépendances externes à signaler

L’agent doit préparer code et documentation, mais demander au propriétaire lorsque requis :

- Apple Developer Team, identifiants, signatures et capacités ;
- conteneur CloudKit et promotion du schéma Production ;
- décisions de conservation/région pour le backend IA ;
- compte/facturation du fournisseur IA et secrets ;
- textes légaux, politique de confidentialité et contenus médias licenciés ;
- appareils réels et validation TestFlight.

Une dépendance externe ne justifie pas d’abandonner les autres tâches indépendantes.

## Définition de fini par phase

Une case ne peut être cochée que si :

- le code réellement utilisé est implémenté, sans écran factice ;
- les données anciennes sont migrées ou la compatibilité est explicitement testée ;
- tests unitaires et tests UI critiques passent ;
- Debug et Release compilent sur les destinations concernées ;
- états vide, erreur, hors ligne, interruption et reprise sont traités ;
- accessibilité et localisation sont vérifiées sur le nouveau parcours ;
- aucune clé ni donnée sensible n’est ajoutée ;
- documentation et captures nécessaires sont à jour ;
- les limites ou actions externes restantes sont écrites précisément.

## Rapport final attendu

À la fin de chaque phase, produire : changements, migrations, tests exécutés avec
résultats, décisions prises, risques et actions externes. À la fin de la roadmap,
faire une nouvelle comparaison ligne par ligne des documents `01` à `08`. Ne jamais
annoncer « tout est fini » tant qu’un critère obligatoire reste non vérifié.

