# Localisation

Muscu est livré en **français** (langue source) et en **anglais**.

## Où vivent les traductions

| Bundle | Catalogue |
| --- | --- |
| Application | `App/Resources/Localizable.xcstrings` |
| Extension widgets | `Widgets/Localizable.xcstrings` |
| Application Watch | `Watch/Localizable.xcstrings` |

Chaque bundle a le sien : une extension et une application Watch ne lisent
pas les ressources de l'application hôte.

La **clé est la phrase française**. `CFBundleDevelopmentRegion` vaut `fr`, et
`project.yml` porte `developmentLanguage: fr`. Sur un appareil français, le
système ne trouve aucun `fr.lproj` et retombe sur la langue de développement,
c'est-à-dire sur les littéraux du code : rien à maintenir en double.

## Ajouter ou modifier une chaîne

1. Écrire le texte **en français**, directement dans le code.
2. Dans une vue : `Text("…")`, `Label("…", systemImage:)`, `Button("…")`,
   `navigationTitle("…")`, `Section("…")` sont localisés automatiquement —
   ce sont des `LocalizedStringKey`.
3. **Hors d'une vue** — une propriété `String`, un message d'erreur, un nom
   de catégorie — il faut écrire `String(localized: "…")`. Sans cela,
   `Text(maVariable)` affiche la chaîne telle quelle et la traduction ne
   s'applique jamais.
4. Synchroniser le catalogue :

```bash
Scripts/sync-strings.sh
```

5. Ouvrir le `.xcstrings` (Xcode l'affiche comme un tableau) et remplir la
   colonne anglaise, ou éditer le JSON.
6. Vérifier :

```bash
python3 Scripts/check-localization.py
```

Xcode fait l'étape 4 tout seul quand on compile depuis l'IDE. Le script
existe pour que la même chose soit faisable en ligne de commande et en CI.

## Ce que la CI refuse

`Scripts/check-localization.py`, appelé en tête de `Scripts/ci.sh`, échoue
si :

- une chaîne n'a **pas** de traduction anglaise ;
- une traduction est restée à l'état `new` ou `needs_review` ;
- les **spécificateurs de format** diffèrent entre la source et la
  traduction. Une `%@` oubliée ne se voit pas à la relecture, mais casse le
  formatage à l'exécution.

## Langue pendant les tests

Un test qui dit « vert » ou « rouge » selon la langue du Mac n'est pas un
test.

- Les tests UI forcent `-AppleLanguages (fr)` au lancement
  (`XCUIApplication.launchEmpty()`).
- `Scripts/ci.sh` passe `-testLanguage fr -testRegion FR` aux tests
  unitaires.
- `UITests/LocalizationFlowTests.swift` lance volontairement l'application en
  anglais et vérifie qu'aucun libellé français ne subsiste : c'est le test
  qui a trouvé que la barre d'onglets restait en français.

Pour voir l'application en anglais à la main :

```bash
xcrun simctl spawn booted defaults write -g AppleLanguages -array en
```

## Unités et formats

- Les charges sont **toujours stockées en kilogrammes**. L'unité choisie
  (kg / lb) ne change que l'affichage, et la conversion est centralisée dans
  `MuscuEngine/Domain/Units.swift`.
- Les longueurs sont stockées en centimètres, avec la même règle.
- Dates, heures, nombres et premier jour de semaine passent par
  `Date.formatted`, `Calendar.current` et `NumberFormatter` : ils suivent la
  région de l'appareil, pas la langue.
- Les exports CSV et JSON écrivent **l'unité de stockage** (kg, cm) et un
  nom de fichier stable (`muscu-seances`, …) : un export ne doit pas changer
  de forme selon la langue de celui qui l'a produit.

## Limite connue

Les phrases **produites par `MuscuEngine`** restent en français dans une
application anglaise : justifications de progression, rationnel d'un plan,
avertissements du validateur, motifs de quarantaine à l'import, messages de
synchronisation et du coach IA.

La raison est mesurée, pas supposée :

- SwiftPM ne compile pas les catalogues de chaînes — un `.xcstrings` placé
  dans les ressources d'un paquet est recopié tel quel ;
- avec des `.lproj` classiques, le paramètre `locale:` de
  `String(localized:bundle:locale:)` ne choisit pas la langue de recherche.

Il n'existe donc aucun moyen d'épingler la langue dans `swift test`, et une
trentaine de tests du moteur qui vérifient une phrase deviendraient
dépendants de la langue de la machine de CI.

La correction n'est pas de contourner ce point mais de faire renvoyer au
moteur des résultats **structurés** (identifiant de motif + valeurs), en
laissant les mots à l'application. Voir
`docs/decisions/0010-localisation-et-diagnostic.md`.
