# Accessibilité — ce qui est fait, ce qui reste

Dernière vérification : 14/09/2026.

## Dynamic Type

Les gros chiffres du runner (chronos, décomptes, compteurs de répétitions)
utilisaient `Font.system(size:)`, qui **fige** la taille : ils restaient
minuscules pour qui a agrandi le texte de son iPhone. Quatorze occurrences.

Elles passent désormais par `scaledSystemFont(size:relativeTo:)`, qui s'appuie
sur `@ScaledMetric` : la taille suit le réglage système en conservant la
proportion voulue. Les textes qui doivent tenir dans un gabarit fixe (anneau du
chrono) gardent `minimumScaleFactor`, donc ils **se réduisent au lieu de se
tronquer**.

Partout ailleurs, les styles de texte (`.headline`, `.caption`…) sont utilisés,
et suivent Dynamic Type par construction.

## VoiceOver

- Les lignes composites (séance planifiée, série d'historique, carte de
  graphique) sont regroupées en un seul élément avec un libellé complet, plutôt
  que lues fragment par fragment.
- Chaque carte de graphique porte une **alternative textuelle** : un graphique
  que VoiceOver ne sait pas décrire ne vaut rien.
- Les gestes non praticables au clavier ou à la voix ont une **action
  accessible** équivalente : déplacer une séance du planning, supprimer une
  photo.
- Les écrans de saisie exposent des identifiants stables, utilisés par les
  tests UI — ce qui garantit qu'ils restent présents.

## Information portée par la couleur

Les états d'avertissement sont en orange, mais le **texte énonce toujours la
condition** : « Accès refusé », « L'enregistrement a échoué », « Date illisible »,
« Doublon ». La couleur souligne, elle n'informe pas seule. Les avertissements
structurants ajoutent en plus une icône (`exclamationmark.triangle`,
`hand.raised`).

## Cibles tactiles

Les commandes du runner (valider, passer, ajouter une série) sont des boutons
`.controlSize(.large)` occupant la largeur disponible. Les listes utilisent les
lignes standard de SwiftUI, déjà conformes.

Point à surveiller : les glyphes `+` / `−` des steppers personnalisés de
`SetLoggerView`. Ils sont dimensionnés en points de police, pas en cible
tactile explicite.

## Confirmations et annulation

- Fin de séance, abandon, suppression d'exercice, suppression de photo,
  suppression de données : toutes passent par une confirmation.
- Les adaptations de progression et les décharges de plateau sont **annulables**
  depuis le journal, pas seulement confirmées avant application.

## Réduction des animations, sons et haptique

Sons et retour haptique sont configurables dans Réglages. Les animations se
limitent à des transitions système et à l'anneau du chrono.

## Ce qui n'est pas vérifié

- **Aucun audit avec VoiceOver réellement activé** : les libellés et l'ordre de
  lecture sont écrits avec soin et couverts par des tests d'identifiants, mais
  l'expérience réelle au lecteur d'écran n'a pas été parcourue.
- **Navigation au clavier sur iPad et Mac** : les raccourcis ⌘1–⌘5 existent,
  le parcours complet au clavier n'a pas été éprouvé.
- **Tailles de texte extrêmes** (AX5) sur chaque écran : le mécanisme est en
  place, la revue écran par écran reste à faire.

Ces trois points demandent une revue manuelle sur appareil, pas du code.
