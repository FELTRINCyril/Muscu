# Muscu - App iOS de musculation - Document de design

Date : 2026-07-16
Statut : valide (design approuve section par section en brainstorming)

## 1. Vision

App iOS native de musculation, sombre et epuree, extremement simple a prendre en main.
Elle permet de creer des programmes complets (manuellement, depuis des modeles de splits,
ou via un generateur intelligent), de derouler ses seances en direct (saisie poids/reps,
chrono de repos automatique), de gerer des formats d'exercices specifiques (pyramides
adaptatives, intervalles 30-30), et de suivre sa progression (1RM, maxes, historique,
graphiques). Tout fonctionne hors ligne, donnees stockees sur l'iPhone.

Utilisateur cible : l'auteur (usage personnel), entrainement principalement en salle,
mais aussi maison / poids du corps / calisthenics.

## 2. Contraintes et decisions structurantes

- **Plateforme** : app iOS native SwiftUI. Pas de compte developpeur Apple payant :
  installation sur iPhone via sideload (SideStore/AltStore, re-signature automatique).
  Phase 1 : developpement et test complet dans le simulateur Xcode sur Mac
  (Xcode a installer, gratuit).
- **Cible** : iOS 18 minimum (iPhone de l'utilisateur : iOS 26).
- **Persistance** : SwiftData, 100% local. Aucun serveur, aucun compte.
- **Hors ligne** : toutes les fonctions coeur (programmes, seances, progression)
  fonctionnent sans internet. Internet utilise uniquement pour : telechargement/cache
  des images d'exercices, ouverture de videos YouTube, generation IA (optionnelle).
- **Sauvegarde** : export/import JSON manuel dans les reglages (important avec le
  sideload : une app supprimee = donnees perdues).
- **Langue** : interface et contenu en francais. Unites : kg.

## 3. Architecture

- **UI** : SwiftUI, theme sombre par defaut, navigation par TabView (5 onglets).
- **Donnees** : SwiftData pour les modeles utilisateur ; base d'exercices embarquee
  en JSON dans le bundle, importee/mise a jour dans SwiftData au premier lancement.
- **Structure du code** (MVVM leger, decoupage par feature) :
  - `Models/` : entites SwiftData + types purs (prescriptions, formats de series)
  - `Features/Home`, `Features/Programs`, `Features/Workout`, `Features/Exercises`,
    `Features/Progress`, `Features/Settings`
  - `Engine/` : logique pure testable sans UI : generateur de programmes,
    calcul pyramides + repos adaptatif, calcul 1RM, generateur d'echauffement,
    proposition de charge
  - `Services/` : cache d'images, chrono/notifications, export/import,
    interface fournisseur IA
- **Tests** : l'Engine (regles metier) est du Swift pur, couvert par des tests
  unitaires (generateur, pyramides, 1RM, arrondi de charge).

### Onglets

1. **Accueil** : prochaine seance ("Lancer la seance" en un tap), vue semaine
   (seances faites/prevues), records recents.
2. **Programmes** : liste des programmes, creation (3 modes), edition, activation.
3. **Exercices** : catalogue, recherche, filtres (muscle, materiel, categorie),
   fiche detaillee, creation d'exercices perso.
4. **Progression** : records/maxes, historique des seances, graphiques par exercice.
5. **Reglages** : sons/vibrations du chrono, telechargement des images,
   export/import JSON, configuration IA (masquee tant que non configuree).

## 4. Base d'exercices

- Source : **free-exercise-db** (open source, licence publique), ~870 exercices :
  nom, muscles primaires/secondaires, materiel, niveau, categorie, instructions, images.
- **Traduction en francais** des noms, categories, muscles et instructions,
  effectuee a la construction de l'app (fichier JSON embarque, ~3 Mo de texte).
- **Images** : non embarquees. Telechargees a la demande depuis le CDN GitHub de
  free-exercise-db, puis mises en cache disque de facon permanente. Bouton
  "Tout telecharger" dans les reglages (~150 Mo optimises) pour un hors-ligne total.
  Sans image en cache et sans reseau : placeholder propre, l'app reste fonctionnelle.
- **Videos** : pas de source gratuite fiable en francais. Bouton "Voir en video"
  sur la fiche exercice qui ouvre une recherche YouTube sur le nom de l'exercice
  (necessite internet, assume).
- **Exercices personnalises** : creation par l'utilisateur (nom, muscles, materiel,
  notes), stockes en SwiftData, melanges au catalogue.

## 5. Programmes

### Structure

- **Programme** : nom, description, liste ordonnee de seances, actif/inactif.
- **Seance** : nom (ex: "Push"), liste ordonnee d'exercices prescrits,
  option echauffement.
- **Exercice prescrit** : reference vers un exercice du catalogue + prescription :
  - format : series fixes / fourchette de reps / pyramide / intervalles / AMRAP
  - series x reps (fixe "8" ou fourchette "8-12")
  - repos entre series (secondes)
  - charge : libre, ou %1RM, ou % du max de reps
  - notes libres
- **Echauffement** : bloc genere automatiquement si active : suggestion de cardio
  leger (5 min) + series de montee en charge progressive sur le premier exercice
  lourd de la seance (ex: 40% x8, 60% x5, 80% x2 du poids de travail).

### Creation - 3 modes

1. **De zero** : editeur complet. Ajout d'exercices depuis le catalogue,
   reordonnancement par glisser, duplication de seance/exercice.
2. **Depuis un modele** : choix du nombre de seances/semaine -> splits recommandes :
   - 2j : Full Body x2
   - 3j : Full Body x3, Upper/Lower/Full, PPL
   - 4j : Upper/Lower x2, Push/Pull/Upper/Lower
   - 5j : PPLUL, ULPPL, Arnold Split
   - 6j : PPL x2, Arnold x2
   Chaque modele est pre-rempli avec des exercices classiques et des prescriptions
   par defaut, entierement modifiable ensuite.
3. **Generateur intelligent (local, moteur de regles)** : questionnaire :
   - objectif : prise de masse / force / perte de poids / endurance /
     progression tractions / calisthenics
   - experience : debutant (<1 an) / intermediaire (1-3 ans) / avance (3+ ans)
   - jours par semaine (2-6), duree max par seance (45 min / 1h / 1h30)
   - materiel : salle complete / maison / poids du corps
   - preference de split (ou "choisis pour moi")
   - points faibles a prioriser, zones a menager (ex: lombaires, genoux)
   Regles appliquees : split choisi selon jours+preference (tableau ci-dessus),
   volume hebdomadaire par muscle selon experience, fourchettes de reps selon
   objectif (force 3-6, hypertrophie 6-12, endurance 12-20), repos selon objectif
   (force ~3 min, hypertrophie ~90 s, endurance ~45 s), selection d'exercices
   filtree par materiel et zones a menager, priorisation des points faibles
   (volume supplementaire), echauffement active par defaut.

### Generation IA (architecture prevue, activation ulterieure)

- Interface `ProgramGenerator` avec deux implementations : `RuleBasedGenerator`
  (local, par defaut) et `AIGenerator`.
- `AIGenerator` : protocole fournisseur interchangeable (URL de base + cle API +
  nom de modele dans les reglages), compatible API Claude et APIs type OpenAI.
  Le questionnaire est envoye avec un schema JSON de sortie identique au format
  interne de programme ; la reponse est validee puis importee comme n'importe
  quel programme.
- Sans cle configuree, l'option n'apparait pas dans l'UI. Pas de cle dans le code.

## 6. Formats d'exercices speciaux

### Pyramide (tractions, dips, pompes...)

- L'utilisateur renseigne son **max de reps** sur l'exercice (repris automatiquement
  des records s'il existe).
- L'app propose plusieurs pyramides calibrees sur ce max, avec volume total affiche,
  ex. pour max 10 : "2-4-6-4-2" (montante-descendante ~60% du max au pic),
  "1-2-3-4-5-4-3-2-1" (progressive), "6-5-4-3-2-1" (descendante). Les paliers sont
  calcules en % du max, pas en valeurs fixes.
- **Repos adaptatif** : le repos apres chaque serie est calcule sur l'**intensite
  relative** de la serie effectuee : `intensite = reps_serie / max_reps`.
  Formule : `repos = repos_min + intensite^1.5 x (repos_max - repos_min)`,
  avec repos_min = 30 s et repos_max = 180 s par defaut (ajustables).
  Exemple : max 8, serie de 5 -> intensite 62% -> ~1 min 45 ; max 15, serie de 5
  -> intensite 33% -> ~1 min. Chaque valeur reste modifiable a la main dans
  l'editeur et ajustable pendant la seance (+30 s / passer).

### Intervalles (30-30, Tabata, EMOM...)

- Parametres : duree d'effort, duree de repos, nombre de rounds.
- Presets proposes : 30-30, Tabata (20-10 x8), EMOM.
- En seance : enchainement automatique effort/repos avec decompte plein ecran,
  bips distincts debut/fin d'effort, vibrations. Saisie des reps par round
  optionnelle en fin de bloc.

### AMRAP

- Max de reps dans un temps donne ; saisie du total en fin de bloc.

## 7. Deroulement de seance

- Lancement en un tap depuis l'accueil (prochaine seance du programme actif).
- **Un exercice a la fois**, plein ecran : nom, image, "Serie 2/4",
  objectif du jour ("8-12 reps @ 75 kg"), derniere perf affichee
  ("La derniere fois : 4x8 @ 72,5 kg").
- **Charge proposee** : si la prescription est en %1RM (ou % max reps), l'app
  calcule et affiche le poids/les reps a faire, arrondi au chargement reel
  (pas de 2,5 kg ; arrondi vers le bas).
- **Validation de serie** : champs poids et reps pre-remplis (objectif ou derniere
  perf), gros steppers +/-, un tap pour valider -> le chrono de repos demarre
  automatiquement.
- **Chrono de repos** : plein ecran, son + vibration a la fin, boutons +30 s et
  passer. Si l'app passe en arriere-plan ou ecran verrouille : notification locale
  a la fin du repos.
- Actions pendant la seance : sauter un exercice, le remplacer (suggestions du
  meme groupe musculaire), ajouter/supprimer une serie, quitter et reprendre
  (la seance en cours est persistee en continu).
- **Fin de seance** : recapitulatif (duree, tonnage total, records battus),
  enregistrement dans l'historique.

## 8. Progression

- **Records (maxes)** : 1RM par exercice (ex: 100 kg DC) et max de reps
  (ex: 20 tractions). Saisie manuelle + mise a jour automatique proposee quand
  une perf en seance les depasse. 1RM estime via formule d'Epley
  (`1RM = poids x (1 + reps/30)`) ; confirmation avant d'ecraser un record.
- **Historique** : chaque seance detaillee (chaque serie : poids, reps),
  consultable par date et par exercice.
- **Graphiques** (Swift Charts) : evolution du 1RM estime, du tonnage et des reps
  par exercice ; volume hebdomadaire.
- **Accueil** : vue semaine (fait/prevu), derniers records.

## 9. Gestion des erreurs et cas limites

- Pas de reseau : images remplacees par un placeholder, bouton video desactive
  avec message, tout le reste fonctionne.
- Interruption de seance (appel, crash, fermeture) : la seance en cours est
  persistee a chaque serie validee, proposition de reprise au relancement.
- Records aberrants : confirmation avant d'ecraser un record ; jamais de mise a
  jour silencieuse.
- Import JSON : validation du schema avant import, aucune donnee ecrasee en cas
  d'echec, message clair.
- Chrono en arriere-plan : base sur des dates absolues (pas un compteur),
  donc fiable meme si iOS suspend l'app ; notification locale programmee des le
  demarrage du repos et annulee si l'utilisateur revient avant.
- %1RM sans 1RM renseigne : l'app demande le 1RM (ou propose de l'estimer depuis
  une perf) au lieu d'afficher une charge vide.

## 10. Deploiement

- **Phase 1 (maintenant)** : projet Xcode, developpement et validation complete
  dans le simulateur iPhone sur le Mac. Xcode a installer (gratuit).
- **Phase 2** : installation sur l'iPhone de l'utilisateur via SideStore/AltStore
  (compte Apple gratuit, re-signature automatique 7 jours geree par SideStore).
  Documentation d'installation fournie a ce moment-la.

## 11. Hors scope (volontairement)

- Notifications push serveur, comptes utilisateurs, synchronisation cloud, social.
- Apple Watch, widgets, Live Activities (envisageables plus tard).
- Nutrition / suivi calorique.
- Publication App Store.
- Activation effective de la generation IA (l'architecture est prete ;
  activation quand l'utilisateur fournira une cle API).
