# 0006 — Planning, rappels, contenus et imports

Date : 13/09/2026
Statut : accepté

## Contexte

La phase 6 relie les programmes au quotidien : planifier une semaine, en être
averti, l’adapter au lieu et au matériel, retrouver ses exercices, réutiliser
ce qui marche et échanger des données avec d’autres applications.

Ces sujets touchent au système (notifications, calendrier, Siri) et à des
fichiers venus de l’extérieur. Les deux sont des sources d’effets de bord :
une permission accordée par erreur, un fichier mal formé ou un import répété
peuvent abîmer des données que l’utilisateur ne peut pas reconstituer.

## Décisions

### 1. Schéma v4, obtenu en figeant le v3

Huit modèles sont ajoutés (`PlaceProfile`, `PlanningSchedule`,
`NotificationRecord`, `CalendarLink`, `SessionTemplate`,
`ExerciseLibraryEntry`, `ExerciseCollection`, `ImportQuarantineEntry`) et
quelques attributs facultatifs sur `CompletedSession` et `ScheduledWorkout`.

Avant de toucher aux modèles courants, une copie figée du v3 a été écrite dans
`App/Sources/Models/SchemaVersions/MuscuSchemaV3.swift`, avec ses valeurs par
défaut en littéral. C’est la règle posée en phase 1 : une migration étagée a
besoin d’une description stable de l’état d’où elle part. La migration V3 → V4
est légère, car elle n’ajoute que des champs à valeur par défaut.

Un test écrit un store avec le schéma v3 figé, puis l’ouvre avec le schéma
courant : c’est la seule façon de vérifier l’étape telle qu’elle se produira
sur l’appareil d’un utilisateur déjà à jour.

### 2. Le moteur décide, l’application exécute

`MuscuEngine/Planning/` porte la récurrence, la détection de collisions, la
replanification et le calcul des rappels. Aucune de ces règles ne connaît
SwiftData, `UNUserNotificationCenter` ni EventKit : elles sont donc testables
sans appareil, sans permission et sans horloge réelle.

Conséquence concrète : le passage à l’heure d’été est un test unitaire, pas une
observation faite trop tard sur un téléphone.

### 3. L’heure locale prime sur l’instant

Une récurrence est développée **jour par jour avec le calendrier**, puis
l’heure voulue est posée sur chaque jour. Ajouter 86 400 secondes décalerait
toutes les séances d’une heure au changement d’heure. Les rappels utilisent un
déclencheur calendaire pour la même raison.

### 4. Aucun rappel sans autorisation, et aucun rappel ressuscité

`NotificationPlanner.plan` renvoie une liste **vide** quand l’autorisation
n’est pas accordée : l’invariant est vérifiable par un test, pas seulement
respecté par convention. L’autorisation n’est demandée qu’au moment où
l’utilisateur active les rappels.

Un rappel supprimé volontairement est enregistré dans `NotificationRecord`.
Sans cette trace, le recalcul au lancement suivant le recréerait à l’identique
— exactement le défaut que le critère d’acceptation interdit. La trace n’est
effacée que si l’utilisateur réactive lui-même les rappels.

### 5. Le calendrier : ne toucher que ce qu’on a créé

Muscu ne modifie que les événements dont il a enregistré le `CalendarLink`. Un
événement externe qui tomberait à la même heure n’est ni lu, ni modifié, ni
supprimé — c’est vérifié par un test qui place un événement étranger au même
moment. Si l’utilisateur a supprimé notre événement depuis l’app Calendrier, le
lien mort est retiré et un nouvel événement est créé plutôt que d’en supposer
l’existence.

L’import ne lit jamais un calendrier entier : l’utilisateur désigne un créneau.

### 6. L’import CSV ne fusionne jamais dans l’historique

Une séance terminée est immuable depuis la phase 2. L’import crée donc des
séances ou les laisse de côté ; il ne complète jamais une séance existante. Le
rapport affiche `0 fusionnée` et l’écran le dit explicitement, plutôt que de
laisser croire à une fusion silencieuse.

La déduplication se fait sur une signature « date à la minute + nom normalisé »,
qui couvre aussi les séances saisies à la main. Une ligne inexploitable part en
**quarantaine** avec sa ligne brute et la raison : l’utilisateur peut corriger
son fichier au lieu de deviner ce qui a disparu.

Formats reconnus : CSV générique avec correspondance manuelle des colonnes,
plus des préréglages pour Strong et Hevy, dont les exports sont publiquement
documentés. Aucun format n’est deviné par rétro-ingénierie.

### 7. Le catalogue reste en lecture seule

Le catalogue embarqué est remplacé à chaque mise à jour de l’application : rien
de personnel ne peut y être écrit. Favoris, tags et collections vivent donc
dans des entités séparées, reliées par identifiant d’exercice.

La recherche passe par `LibrarySearch`, partagée par l’onglet Exercices, le
remplacement en séance et les entités Siri : les trois appliquent exactement
les mêmes règles, accents et fautes de frappe comprises.

**Limite assumée** : la roadmap demande « erreurs fréquentes et variantes » par
exercice. Les variantes sont calculées depuis le catalogue (mêmes muscles
principaux, même type de mouvement) et affichées avec leur raison. Les erreurs
fréquentes ne sont pas affichées : nous n’avons aucune source pour ce contenu,
et l’inventer serait un conseil technique fabriqué. Cela demande des textes
éditoriaux, qui font partie des dépendances externes déjà listées.

### 8. Un modèle est un instantané

`SessionTemplate` stocke son contenu en JSON plutôt qu’en relations. S’il
pointait sur les entités vivantes, renommer un exercice réécrirait le modèle et
supprimer le programme d’origine le viderait.

Un modèle créé depuis une séance **terminée** conserve les exercices, leur
format et le nombre de séries de travail — jamais les charges ni les
répétitions réalisées. Un record du jour ne doit pas devenir une obligation
permanente.

### 9. Les raccourcis confirment leurs écritures

Les entités exposées à Siri portent des identifiants stables. La seule
intention qui écrit (`LogBodyweightIntent`) demande confirmation avant
d’enregistrer. Les autres se contentent d’ouvrir un écran ou de lire un
résumé. Les phrases sont fournies en français et en anglais.

### 10. Ce qui n’est pas exporté

`NotificationRecord` et `CalendarLink` sont volontairement absents de
l’export JSON v4. Le premier décrit l’état du centre de notifications de *cet*
appareil ; le second pointe vers des événements du calendrier local. Les
restaurer ailleurs décrirait des rappels inexistants et autoriserait Muscu à
modifier des événements qu’il n’a pas créés. Les deux se reconstruisent seuls.

Une récurrence importée revient toujours **rappels désactivés** : l’autorisation
de notifier appartient à l’appareil, pas au fichier.

## Conséquences

- Les tests de récurrence, de rappels, de calendrier et d’import tournent sans
  appareil, sans permission et sans réseau.
- Les tests UI n’ouvrent jamais une vraie demande d’autorisation : le harnais
  substitue des doubles en mémoire derrière `--uitest-reset`.
- Le cœur de l’application reste utilisable sans notifications, sans calendrier
  et sans réseau.
