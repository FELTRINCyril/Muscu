# Comparaison finale, ligne par ligne, des documents 01 à 08

Date : 15/09/2026.

Le plan d'exécution (`09-execution-plan.md`) exige, à la fin de la roadmap,
« une nouvelle comparaison ligne par ligne des documents 01 à 08 ». Ce
document en est le résultat.

Méthode : chaque puce et chaque critère d'acceptation des huit documents a
été confronté au code, fichier ouvert et ligne citée. Trois relectures
indépendantes ont été menées, puis leurs constats les plus lourds vérifiés
une seconde fois à la main — les relectures se contredisaient sur la fusion
des records, et c'est la vérification manuelle qui a tranché.

Ce document liste ce qui **manque**. Ce qui est fait n'y figure pas : les
sections « Réalisé » de `09-execution-plan.md` s'en chargent.

---

## Corrigé pendant cette comparaison

| Défaut | Document | Correction |
| --- | --- | --- |
| **Une semaine de décharge planifiée n'allégeait rien.** `volumeMultiplier` / `intensityMultiplier` étaient calculés, stockés, affichés — et jamais appliqués à une séance. | 03, critère « une décharge réduit réellement volume et/ou intensité » | `MuscuEngine/Programming/WeekScaling.swift` + `Services/WeekScalingResolver.swift`, appliqués au démarrage d'une séance et re-appliqués à la reprise. Un bandeau le dit à l'écran : alléger en silence serait une modification non consentie. 9 tests moteur, 5 tests application. |
| **La purge différée des suppressions logiques n'existait pas.** `MergePolicy.canPurge` était écrit et testé, sans aucun appelant. | 01, « prévoir une purge différée » | `Services/TombstonePurge.swift`, appelée au démarrage, avec un garde-fou qui échoue si un modèle portant `deletedAt` n'y figure pas. 8 tests. |
| **Le Privacy Manifest ne déclarait pas les API d'horodatage de fichier** pourtant utilisées (`contentModificationDateKey`, `attributesOfItem`). | 08, « Privacy Manifest cohérent avec le code réel » | `C617.1` ajouté à `App/Resources/PrivacyInfo.xcprivacy`. |
| **L'application Watch n'avait aucun Privacy Manifest** alors qu'elle utilise `UserDefaults`. | 08 | `Watch/PrivacyInfo.xcprivacy` ajouté et vérifié présent dans le bundle construit. |
| **Cibles tactiles des `+` / `−` sous 44 points**, et VoiceOver annonçait « plus circle fill ». | 08, accessibilité | `frame(minWidth: 44, minHeight: 44)` + libellés explicites. Vérifié par un test qui mesure la hauteur réelle. |

---

## Manques confirmés, par ordre de gravité

### 1. La synchronisation iCloud n'a aucun transport (doc 04)

`CloudKitSyncTransport` (`Services/SyncTransport.swift:126-147`) est un
squelette : `containerIdentifier` vide, `availability()` renvoie
inconditionnellement `.unavailable(.notConfigured)`, `fetchChanges` et `push`
lèvent. **Zéro `import CloudKit` dans le dépôt.** Les entitlements ne portent
aucune clé iCloud.

Tout ce qui l'entoure est réel et testé — réconciliation, file d'attente avec
backoff, politique de fusion, écran d'état, 14 tests à deux stores. C'est le
dernier fil qui manque, et il dépend d'un compte Apple Developer payant.

**Conséquence** : quatre critères d'acceptation du doc 04 sont
**invérifiables**, pas « faits » : restauration sur un nouvel appareil,
séance hors ligne visible ailleurs, Mac identique à l'iPhone, parcours réel
sur deux appareils.

### 2. La file de synchronisation n'est jamais alimentée (doc 04)

`SyncService.enqueue` n'a **aucun appelant applicatif** : ni la fin d'une
séance, ni l'édition d'un programme, ni une mesure. Les seuls appels sont
l'interrupteur d'activation (`enqueueEverything`), la résolution de conflit,
et 29 appels dans les tests.

Le jour où CloudKit sera branché, seule une réinscription complète ferait
partir quoi que ce soit. À corriger **avant** d'activer la synchronisation,
pas après.

### 3. Un record peut régresser lors d'une fusion (docs 01 et 04)

`MergeStrategy.maximumThenNewest` est documenté « maximum des performances
comparables, puis date la plus récente ». À l'exécution
(`MergePolicy.swift:97-98`) il compare **uniquement les dates**, exactement
comme `identifierOnly`. `MergePolicy.maximum` existe, est testé, et **n'est
appelé par personne**.

Un record distant plus récent mais **inférieur** écraserait donc un meilleur
record local.

La cause est structurelle : la décision de fusion ne voit que
`SyncMetadata`, jamais le contenu — les charges utiles sont des agrégats
opaques (`SyncRecord.payload: Data`) et appliquer un enregistrement remplace
l'agrégat entier. La corriger demande de faire remonter une valeur
comparable jusqu'au réconciliateur. Non corrigé ici : le défaut ne se
manifeste qu'avec une synchronisation active, donc jamais aujourd'hui, et le
faire à la hâte en toucherait le cœur.

### 4. Deux adaptations acceptées sont irréversibles (doc 03)

Le critère est « toute adaptation affiche ses raisons et peut être annulée ».

- `ProgressionReview.accept` applique `.adjustTime` en écrivant
  `intervalWork` / `intervalRest` **sans enregistrer les valeurs
  précédentes**. `AdaptationEntry.canRevert` exige l'un des champs
  `previous*` : le bouton « Annuler cette adaptation » n'apparaît donc
  **jamais** pour une adaptation d'intervalle.
- `PlateauReview.acceptVariant` change l'exercice sans enregistrer l'ancien
  `exerciseId` : même conséquence, et `revert` ne saurait de toute façon pas
  le restaurer.

Corriger demande d'ajouter des champs à `AdaptationEntry`, donc un schéma v6
et une migration.

### 5. Le check-in de forme ne débouche sur rien (doc 03)

`ReadinessAdvisor` produit une suggestion (volume réduit, charge réduite,
substitution, repos) avec ses facteurs. `SessionPrepView` l'affiche — et
c'est tout. **Rien n'est jamais appliqué**, aucun bouton ne l'applique, et
`AdaptationSource.readiness` est déclaré mais jamais écrit. « Reste
modifiable » est vrai par vacuité.

### 6. Les blobs de `ActiveWorkout` n'ont ni version ni taille maximale (doc 01)

Le document exige quatre choses pour un blob JSON : un numéro de version, une
taille maximale, une stratégie de migration, et **un test de décodage de
chaque ancienne version**.

- **Version : absente** des quatre blobs (`runExercisesData`,
  `runtimeStateData`, `planData`, `positionData`).
- **Taille maximale : uniquement à l'import d'archive**, jamais à l'écriture.
- **Migration** : un `try?` qui retombe sur une valeur neutre. Conséquence
  réelle : `WorkoutRuntimeState` a gagné des champs non optionnels après
  coup ; le décodeur synthétisé n'applique pas de valeur par défaut sur clé
  manquante, donc un ancien `runtimeStateData` **échoue silencieusement** et
  repart à zéro — chrono de repos et état AMRAP/intervalle perdus, sans
  trace.
- **Test de décodage d'une ancienne version : absent.**
  `LegacyRunExercise.plan(from:)` n'est exercé par aucun test ; le test qui
  prétend le couvrir construit un `ActiveWorkout` sans aucun blob.

C'est le manque le plus proche d'une perte de données réelle pour un
utilisateur qui met à jour au milieu d'une séance.

### 7. Le coach IA ne reçoit jamais le programme qu'on lui demande d'adapter (doc 05)

`AICoachContext` porte le profil, l'équipement et la forme du jour — **ni
programme, ni semaine, ni séance**. Les capacités `adaptWeek`,
`substituteExercise`, `summarizeSession` et `shortenSession` sont donc
structurellement impossibles à satisfaire. `response.adaptations` et
`response.substitutions` sont décodés puis **jetés**.

Deux corollaires :

- `AIResponseValidator.unsafeSuggestions`, le filtre anti-progression
  agressive, est **du code mort** : jamais appelé en production.
- `AICoachOutcome.violations` vaut toujours `[]` : le doc exige de montrer
  les contraintes non respectées, l'écran n'en montre aucune.

Manquent aussi : le fil de discussion, le cache de réponses, le bouton
« Réessayer » (`isRetryable` n'est utilisé que par les tests), et toute
documentation de durée de conservation, de région et de politique du
fournisseur.

### 8. Des champs sont stockés, exportés, et lus par personne

`AthleteProfile` : `birthDate`, `lengthUnit`, `secondaryGoals`,
`priorityMuscles`, `weeklyFrequencyByMuscle`. `PrescribedExercise` :
`targetDurationSeconds`, `targetDistanceMeters`. `CompletedSet` :
`distanceMeters`, `calories`. `ScheduledWorkout` → `countdownSeconds` des
intervalles. `ExerciseGroup.requiresManualStationValidation`.

Chacun traverse le modèle et l'export sans qu'aucun écran ne le saisisse ni
qu'aucun moteur ne le lise. Le plus visible : **les exclusions d'exercices du
profil ne sont jamais transmises au générateur**, ce qui rend le critère
« chaque séance respecte les exclusions » inapplicable.

### 9. Manques fonctionnels par document

**Doc 02** — nœud « récupération » dans le déroulé ; validation manuelle des
stations de circuit à l'exécution ; compte à rebours de départ des
intervalles ; bips à 3-2-1 ; aperçu des segments ; EMOM à contenu variable ;
AMRAP multi-exercices ; création manuelle des paliers de pyramide ; repos
adaptatif désactivable ; éditeur : déplacer un exercice **dans** un groupe,
réordonner les groupes et leur contenu, dupliquer un groupe ; record
spécifique aux circuits ; densité de travail et durée sous tension jamais
affichées.

Le récapitulatif de fin de séance affiche « Série N » pour les tours d'un
superset et pour les paliers d'un dropset, alors que l'historique les
distingue correctement — et il recalcule le tonnage en `poids × reps` au lieu
de passer par `SetMetrics`, donc il est faux pour le poids du corps, le lesté
et l'assisté.

**Doc 03** — vérification des mouvements essentiels au split ; gestion des
vacances et indisponibilités ; date de départ d'un plan figée à `.now` dans
l'assistant ; `timeProgression` propose un ajustement sans aucune condition
de réussite ; cinq règles sur huit n'ont pas de condition de réduction.

**Doc 04** — menus macOS (aucun `.commands`) ; gestion du pointeur ; cinq
raccourcis clavier seulement, posés sur un `NavigationLink` dans une `List` ;
export CSV des records ; feuille de partage ; rappel de sauvegarde ;
`CompletedSession.revision` jamais incrémenté.

**Doc 05** — backend géré (assumé et documenté).

**Doc 06** — lecture HealthKit de la fréquence cardiaque et du sommeil ;
énergie active déclarée en écriture mais jamais réellement écrite ; pas de
réconciliation d'une séance **modifiée** après écriture dans Santé ; les
records typés (temps, tours, distance, tonnage de séance) sont enregistrés
mais **invisibles** — `RecordsView` interroge `ExerciseRecord` et non
`PersonalBest` ; les consentements ne figurent pas dans l'export.

**Doc 07** — « erreurs fréquentes » par exercice ; médias personnalisés ;
document de licence des images (la source est épinglée dans le code, les
droits ne sont écrits nulle part) ; filtre par difficulté ; pas de sélecteur
jour/semaine/mois dans le planning.

**Doc 08** — voir « Ce qui n'est pas vérifié » dans
`docs/qualite/accessibilite.md` et la limite de localisation du moteur dans
`docs/qualite/localisation.md`.

### 10. Trous de couverture de tests

- **Reprise après interruption** : testée pour le superset et le classique
  seulement. Dropset, rest-pause, myo-reps, circuit, pyramide, For Time et
  EMOM reposent sur une reprise non couverte.
- **Triset et giant set** ne sont instanciés par aucun test.
- **Tests UI** : aucun pour le circuit, le For Time, ni pour l'écran des
  graphiques — les identifiants `charts.*` n'apparaissent dans aucun test,
  donc « VoiceOver et Dynamic Type pour tous les graphiques » n'est pas
  vérifié.
- **Photos de progression** : aucun test d'export, d'import ni de
  suppression.
- **Mémoire** : aucune mesure (`XCTMemoryMetric` absent), alors que le doc 08
  demande un budget mémoire.
- **iPad** : un seul test, ignoré hors destination iPad. **Mac Catalyst** :
  build seul, aucun test.
- **Secrets** : aucun script ne scanne le dépôt ni le binaire.

---

## Ce que cela change pour le suivi

La phase 3 était cochée `[x]`. Son critère « une décharge réduit réellement
volume et/ou intensité » était faux jusqu'à aujourd'hui pour les semaines de
décharge planifiées. Il est désormais vrai et testé — mais les points 4 et 5
ci-dessus restent des critères de la phase 3 non satisfaits. La case passe
donc à `[~]`.

Aucune case ne doit être cochée sur la foi d'un champ présent dans le
modèle : c'est le mode de défaillance que cette comparaison a trouvé sept
fois.
