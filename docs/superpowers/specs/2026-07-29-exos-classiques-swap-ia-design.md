# Muscu - Exos classiques, swap d'alternatives, generation IA - Document de design

Date : 2026-07-29
Statut : valide (design approuve en brainstorming, 3 chantiers valides individuellement)

## Contexte et problemes

Retour utilisateur apres installation sur iPhone (post campagne QA) :

1. Les programmes crees depuis un modele ou le generateur choisissent des exercices
   exotiques ("Developpe au sol alterne", "Around the world", "Extension triceps a la
   bande") au lieu des classiques de salle. Cause identifiee : `RuleBasedGenerator.pickExercise`
   filtre le catalogue par muscle/equipement puis prend le premier par ordre alphabetique
   d'id (`RuleBasedGenerator.swift:154-163`), ce qui favorise systematiquement les ids
   `Alternating_*`, `Band_*`, `Ab_*`. Templates et wizard partagent 100% de ce code.
2. Pas d'edition directe depuis l'apercu de generation, et pas de remplacement rapide
   d'un exercice par une alternative equivalente (squat barre -> presse a cuisses).
3. La generation IA est une coquille vide : ecran de config (URL/cle/modele) mais aucun
   appel reseau. L'architecture est prete (`DraftProgram` Codable, protocole
   `ProgramGenerator`).

## Chantier 1 : liste blanche curee d'exercices classiques

### Donnees

Nouvelle table statique Swift dans MuscuEngine (`Generator/StapleExercises.swift`) :

- ~60-80 exercices "classiques de salle" bases sur la liste utilisateur (pecs, dos,
  epaules, bras, jambes, abdos), chacun mappe vers son id reel du catalogue
  (`exercises_fr.json`, ids type `Barbell_Bench_Press_-_Medium_Grip`). Chaque id est
  verifie contre le catalogue a l'implementation ET par un test unitaire qui echoue
  si un id de la table n'existe pas dans le JSON.
- Chaque entree porte : `catalogId`, `movementGroup` (groupe de mouvement, ex :
  "poussee horizontale pecs" = DC barre, DC halteres, DC incline, DC decline, poulies),
  `rank` (ordre de preference dans le groupe : DC barre avant DC halteres), et
  l'equipement requis (deja dans le catalogue, pas duplique).
- Choix table Swift typee plutot que JSON compagnon : verification a la compilation,
  testable, donnee de code curee a la main.

### Generateur

`RuleBasedGenerator.pickExercise` pioche uniquement dans la liste blanche :

- Filtres existants conserves (muscle, equipement via `isEquipmentAllowed`, avoidAreas).
- Tri par `rank` du groupe au lieu du tri alphabetique. Reste deterministe
  (test `testDeterministicGenerationProducesIdenticalResults` conserve, adapte si besoin).
- Repli sur le catalogue complet (comportement actuel) uniquement si aucun exo de la
  liste blanche ne satisfait les filtres (ex : equipement "poids du corps seul").
- Templates corriges automatiquement (meme code).

### Bouton "Regenerer" repare

Aujourd'hui inutile (meme input -> meme sortie). Ajout d'un parametre de variation
(seed/offset) dans `GeneratorInput` : chaque appui fait tourner les choix vers
l'alternative suivante du meme groupe de mouvement. Deterministe a seed egal.

## Chantier 2 : edition directe et swap par alternatives

### Bouton "Modifier" sur l'apercu de generation

Dans `DraftPreviewView` (apercu apres generation template/wizard) : bouton toolbar
"Modifier" qui enregistre le brouillon comme programme puis ouvre directement
`ProgramEditorView` dessus (nom, seances, exos, series, repos - tout existe deja,
on raccourcit le chemin qui exigeait enregistrer -> onglet Programmes -> ouvrir).

### Swap rapide par alternatives (sans mode edition)

- Fonction `alternatives(for:)` dans MuscuEngine : les autres membres du meme
  `movementGroup` (tries par rank), et pour un exercice hors liste blanche ou perso,
  repli sur "meme muscle principal + meme mechanic (compound/isolation)" du catalogue.
- UI : icone d'echange (`arrow.triangle.2.circlepath`) sur chaque ligne d'exercice
  dans `DraftPreviewView` ET `SessionEditorView`. Ouvre une sheet compacte listant
  les alternatives (nom + equipement), avec en bas "Autre exercice..." qui ouvre
  `ExercisePickerView` pre-filtre sur le muscle principal (deja supporte via
  `initialMuscleFilter`).
- Le remplacement conserve tout (series, reps, repos, format, charge) et ne change
  que `exerciseId` + `displayName`. Sur un draft : mutation du `DraftExercise` ;
  sur un programme : mutation de la `PrescribedExercise` (contrairement au swap du
  runner qui ne touche que le snapshot de seance).

## Chantier 3 : generation IA complete

### Providers

Enum `AIProvider` avec 4 cas :

- `anthropic` (Claude) : POST `https://api.anthropic.com/v1/messages`, en-tetes
  `x-api-key` + `anthropic-version: 2023-06-01`, sortie structuree via
  `output_config.format` (json_schema). Modele par defaut : `claude-opus-5`.
- `openai` (ChatGPT) : POST chat completions, `Authorization: Bearer`.
- `gemini` (Google) : API generativelanguage, cle en parametre ou en-tete.
- `openAICompatible` : URL de base custom + cle, format OpenAI. Couvre Cursor et
  tout provider compatible.

Les formats de requete/reponse exacts d'OpenAI et Gemini seront verifies contre leur
documentation au moment de l'implementation (pas ecrits de memoire).

### Reglages

Refonte de `AIProviderConfigView` : picker de provider, champ URL de base (visible
uniquement pour openAICompatible), champ modele (avec defaut par provider), cle API
en Keychain par provider (`KeychainHelper`, service existant, un compte par provider),
bouton "Tester la connexion" (requete minimale, affiche succes/erreur). La section IA
des reglages reste visible (elle sert a configurer) ; c'est l'option dans le wizard
qui est conditionnee a `isConfigured`.

### Generation

- Nouveau `AIProgramGenerator` dans MuscuEngine avec un protocole
  `AsyncProgramGenerator` (`func generate(_ input: GeneratorInput) async throws -> DraftProgram`).
  Le protocole synchrone existant reste pour `RuleBasedGenerator`.
- Client HTTP injectable (protocole `AIHTTPClient` avec impl `URLSession` cote app,
  mock dans les tests) : MuscuEngine reste testable sans reseau.
- Prompt construit a partir de : reponses du wizard (`GeneratorInput`), texte libre
  utilisateur (objectifs/contraintes), et la liste blanche des exercices autorises
  (ids + noms francais + muscle + equipement). Le LLM doit repondre en JSON strict
  au schema `DraftProgram` (deja Codable).
- Validation : decodage JSON, verification de chaque `exerciseId` contre le catalogue.
  Id inconnu -> tentative de correspondance par nom (`ExerciseCatalog.search`), sinon
  nouvel essai (1 retry avec message d'erreur au LLM), sinon erreur claire a
  l'utilisateur avec proposition de repli sur le generateur local.

### Wizard

- Si `AIProviderConfig.isConfigured` ET reseau disponible (`NetworkStatus`) : choix
  "Generateur local / Generer avec l'IA" + champ texte libre pour les objectifs.
  Sinon : comportement actuel inchange (option IA grisee avec explication si cle
  configuree mais hors ligne, invisible si pas de cle).
- Appel asynchrone : ecran d'attente avec annulation (Task cancellable), timeout
  raisonnable (60 s). Le resultat arrive dans le meme `DraftPreviewView` que le
  generateur local (avec le swap du chantier 2 disponible).

## Ordre d'implementation et dependances

1. Chantier 1 (table + generateur) : fondation, fournit les groupes de mouvement.
2. Chantier 2 (swap + edition) : depend des groupes du chantier 1.
3. Chantier 3 (IA) : depend de la liste blanche (prompt) et de l'apercu (affichage).

## Tests

- MuscuEngine : validite des ids de la table (vs JSON), selection du generateur
  (classiques choisis, rangs respectes, repli equipement, determinisme, rotation
  regenerer), `alternatives(for:)` (groupe, repli muscle), `AIProgramGenerator`
  (prompt contient la liste blanche, parsing reponse valide, id inconnu -> retry,
  echec -> erreur typee) avec client HTTP mocke.
- Tests unitaires existants (46) preserves.
- Suites XCUITest existantes : ProgramsFlowTests devra etre adapte si les libelles
  changent ; ajout de cas pour le swap et le bouton Modifier.
- Aucune cle API en dur nulle part (convention repo).

## Hors perimetre

- Mode "ajuster un programme existant par l'IA" (option ecartee au cadrage).
- Streaming des reponses LLM (une seule reponse JSON suffit).
- Partage/sync des programmes.
