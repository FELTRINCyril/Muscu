# 0010 — Localisation français/anglais et journal de diagnostic

Date : 14/09/2026
Statut : accepté

## Contexte

La phase 9 ferme les écarts listés dans `docs/roadmap/08` : accessibilité,
localisation, performance, vie privée, diagnostics et CI reproductible. Deux
d'entre eux demandaient du code nouveau plutôt que des retouches : la
localisation français/anglais, et le journal de diagnostic local.

## Décisions

### 1. Le français est la langue source, l'anglais une traduction du catalogue

`CFBundleDevelopmentRegion` vaut `fr` et les littéraux restent écrits en
français dans le code. Un `Localizable.xcstrings` par bundle porte la
traduction anglaise :

| Bundle | Catalogue | Chaînes |
| --- | --- | --- |
| Application | `App/Resources/Localizable.xcstrings` | 918 |
| Widgets | `Widgets/Localizable.xcstrings` | 14 |
| Watch | `Watch/Localizable.xcstrings` | 18 |

L'alternative — passer tout le code en clés anglaises — aurait rendu chaque
diff illisible pour le propriétaire du dépôt sans rien apporter : le
catalogue fait exactement le même travail.

### 2. Les libellés hors des vues passent par `String(localized:)`

SwiftUI localise `Text("…")` tout seul, mais pas `Text(uneVariable)`. Les
titres d'onglets, les noms de catégories de suppression, les modes d'import
et tous les messages d'erreur vivaient dans des propriétés `String` — ils
seraient restés français dans une application anglaise. Le test
`LocalizationFlowTests.testTheAppIsInEnglishOnAnEnglishDevice` a trouvé le
défaut avant toute relecture : la barre d'onglets affichait encore
« Réglages ».

138 littéraux ont été enveloppés dans `String(localized:)`. Les propriétés
qui renvoient un identifiant technique (`systemImage`, `fileName`, clés de
`UserDefaults`) en sont exclues : les traduire casserait un nom de symbole
ou un nom de fichier exporté.

### 3. La langue des tests est figée, jamais héritée de la machine

Un test qui dit « vert » ou « rouge » selon la langue du Mac n'est pas un
test. Trois mesures :

- les tests UI forcent `-AppleLanguages (fr)` au lancement ;
- `Scripts/ci.sh` passe `-testLanguage fr -testRegion FR` aux tests
  unitaires — mais **pas** aux tests UI, dont un cas se lance
  explicitement en anglais ;
- `LocalizationFlowTests` vérifie les deux langues, y compris qu'aucun
  libellé français ne subsiste dans un écran anglais.

Un seul test unitaire dépendait réellement de la langue
(`testDeletionOnAnEmptyStoreIsHarmless`) ; il compare désormais à la même
chaîne localisée.

### 4. `Scripts/check-localization.py` refuse une traduction partielle

Un catalogue incomplet ne casse pas la compilation : il livre simplement du
français à un anglophone. Le script, appelé en tête de `Scripts/ci.sh`,
échoue si une chaîne n'a pas de traduction anglaise, si elle est restée à
l'état `new`, ou si les spécificateurs de format diffèrent entre la source et
la traduction — une `%@` oubliée ne se voit pas à la relecture mais casse le
formatage à l'exécution.

### 5. Limite assumée : `MuscuEngine` reste en français

Les phrases **produites par le moteur** (justifications de progression,
rationnel d'un plan, avertissements du validateur, motifs de quarantaine à
l'import, messages de synchronisation et du coach IA) restent en français
dans une application anglaise. Ce n'est pas un oubli, c'est un arbitrage :

- SwiftPM **ne compile pas** les catalogues de chaînes. Vérifié : un
  `.xcstrings` placé dans les ressources du paquet est recopié tel quel dans
  le bundle, jamais transformé en `.lproj/*.strings`.
- Avec des `.lproj` classiques, la traduction fonctionne — mais le paramètre
  `locale:` de `String(localized:bundle:locale:)` **ne choisit pas** la
  langue de recherche : c'est la langue préférée du processus qui gagne.
  Vérifié également, par un essai jeté après mesure.
- Il n'existe donc aucun moyen d'épingler la langue dans `swift test`. Les
  quelque trente tests du moteur qui vérifient une phrase deviendraient
  dépendants de la langue de la machine de CI.

La bonne correction n'est pas de contourner cela : c'est que le moteur
renvoie des résultats **structurés** (un identifiant de motif et ses valeurs)
et que l'application se charge des mots. C'est un changement de conception à
part entière, à faire dans son propre incrément, pas au milieu de la phase 9.

### 6. Le journal de diagnostic est borné, expurgé et désactivable

`MuscuEngine/Diagnostics` porte la logique testable :

- `DiagnosticsBuffer` ne dépasse jamais 200 lignes ;
- `DiagnosticRedactor` masque adresses e-mail, jetons longs mêlant lettres et
  chiffres, noms de compte dans les chemins et suites de chiffres assez
  longues pour être un numéro. Les UUID sont épargnés : ce sont nos propres
  identifiants, utiles au diagnostic ;
- `DiagnosticReportBuilder` n'assemble que versions, compteurs, dates et
  codes d'erreur.

L'expurgation s'applique **à la construction de l'évènement**, pas à
l'affichage : un appelant distrait qui recopierait une trace système ne peut
pas faire fuiter une clé.

Côté application, `PersistenceSupport` est le point unique de sauvegarde :
y brancher le journal garantit qu'aucun échec de stockage ne passe inaperçu.
`DiagnosticsCenter.isEnabled = false` efface aussi les lignes déjà écrites —
une désactivation qui laisserait l'historique en place ne voudrait rien dire.

`DataDeletion` gagne une catégorie `diagnostics` : le journal ne vit pas dans
SwiftData, l'oublier rendrait la « suppression totale » mensongère, exactement
comme pour le coach IA.

### 7. Mac Catalyst : pas de Live Activity, pas de widget, pas de Watch

Le build Release Mac Catalyst de `Scripts/ci.sh` a trouvé deux vrais défauts :

- `ActivityKit` se compile sur Mac Catalyst mais **chacun de ses symboles y
  est indisponible**. `canImport(ActivityKit)` ne suffit donc pas : seul
  `!targetEnvironment(macCatalyst)` distingue les deux cas.
  `WorkoutActivityController` a désormais une implémentation de repli qui
  répond simplement « non disponible » ; la séance s'y déroule à l'identique.
- macOS refuse d'embarquer un binaire iOS ou watchOS. Les dépendances
  `MuscuWidgets` et `MuscuWatch` portent `platformFilter: iOS`, ce qui les
  exclut de la variante Catalyst.

## Conséquences

- Une application anglaise est réellement livrable : chrome, réglages,
  widgets et montre sont traduits, et deux tests UI le vérifient dans les
  deux langues.
- Une traduction incomplète devient une erreur de CI, pas une découverte
  faite par un utilisateur.
- Un échec de stockage, de synchronisation ou de partage Santé laisse une
  trace exploitable, sans jamais exposer de donnée d'entraînement.
- Les phrases du moteur restent françaises ; c'est écrit ici et dans
  `docs/roadmap/09-execution-plan.md`, et ce n'est pas comptabilisé comme
  fait.
