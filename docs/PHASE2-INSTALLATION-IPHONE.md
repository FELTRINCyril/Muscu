# Phase 2 - Installation sur iPhone (SideStore) et contexte complet du projet

Ce document donne tout le contexte nécessaire pour reprendre le projet sur une autre machine
(notamment pour un assistant IA) et réaliser la phase 2 : installer l'app sur l'iPhone de Cyril
via SideStore, sans compte développeur Apple payant.

## 1. État du projet (17 juillet 2026)

L'app est **fonctionnellement complète** (phase 1 terminée) :

- Les 23 tâches du plan d'implémentation sont faites, revues et corrigées
  (voir `docs/superpowers/plans/2026-07-16-muscu-app.md` et la spec
  `docs/superpowers/specs/2026-07-16-muscu-app-design.md`).
- Une revue finale de l'ensemble a été passée, ses findings corrigés
  (dédoublonnage des records à l'import, exercices perso sélectionnables,
  charge en % du max de reps, bouton vidéo hors ligne, etc.).
- 46 tests unitaires verts sur le moteur (`Packages/MuscuEngine`).
- Vérification de bout en bout dans le simulateur : catalogue (873 exercices FR),
  génération de programme, séance complète, records, export/import, pyramides adaptatives.

### Ce qui n'a PAS pu être vérifié dans le simulateur (à faire sur l'iPhone réel)

- [ ] **Notification de fin de repos écran verrouillé / app en arrière-plan**
      (la popup d'autorisation iOS ne pouvait pas être acceptée sans tap humain).
      Vérifier : lancer une séance, valider une série, verrouiller l'écran,
      attendre la fin du repos -> notification "Repos terminé" avec son.
- [ ] **Mode avion** : tout doit fonctionner sauf les images non mises en cache
      (placeholder) et le bouton "Voir en vidéo" (désactivé avec message).
- [ ] **Compteur AMRAP** : vérifier que le tap sur la carte incrémente bien
      et que le bouton "Corriger (-1)" reste cliquable indépendamment.
- [ ] Les bips de changement de phase des intervalles (30-30) ne sonnent PAS
      si l'app est en arrière-plan (limitation connue et assumée : seul le
      chrono de repos programme une vraie notification locale).

## 2. Architecture technique (résumé)

- **App iOS native SwiftUI + SwiftData**, iOS 18 minimum, 100% hors ligne, aucune donnée serveur.
- **`Packages/MuscuEngine`** : package SPM de logique pure (1RM Epley, pyramides + repos
  adaptatif, échauffement, intervalles, catalogue d'exercices, générateur de programmes).
  Tests : `cd Packages/MuscuEngine && swift test`.
- **`App/Sources`** : Models (SwiftData), Services (ImageStore, RestTimer, ExportImport,
  RecordDetection, AIProviderConfig, NetworkStatus, FeedbackSettings), Features (Home,
  Programs, Workout, Exercises, Progress, Settings).
- **Le projet Xcode n'est pas commité** : il est généré par XcodeGen depuis `project.yml`.
- Catalogue : `Packages/MuscuEngine/Sources/MuscuEngine/CatalogData/exercises_fr.json`
  (873 exercices traduits, champs nameFr/instructionsFr). Images téléchargées à la demande
  depuis le CDN GitHub de free-exercise-db et mises en cache disque.
- Générateur IA : architecture prête (protocole `ProgramGenerator`, config clé API en
  Keychain, section masquée dans Réglages) mais AUCUN appel réseau implémenté (volontaire).

## 3. Construire l'app

Prérequis : Xcode complet (l'app ne compile pas avec les seuls Command Line Tools),
XcodeGen (`brew install xcodegen`, ou binaire GitHub si la formule brew pose problème).

```bash
xcodegen generate
xcodebuild -project Muscu.xcodeproj -scheme Muscu \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Astuce : si `xcode-select -p` pointe encore sur les Command Line Tools et que sudo
n'est pas disponible, préfixer chaque commande xcodebuild/xcrun par
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Bundle id : `com.cyril.Muscu` (préfixe `com.cyril` dans project.yml).

## 4. Phase 2 : installer sur l'iPhone via SideStore

Objectif : app installée en permanence sans compte développeur payant, avec
re-signature automatique tous les 7 jours directement depuis l'iPhone.

### 4.1 Générer l'IPA

1. Ouvrir le projet dans Xcode (`xcodegen generate` puis `open Muscu.xcodeproj`).
2. Signing & Capabilities : équipe = compte Apple personnel gratuit ("Personal Team").
   Si le bundle id est refusé (déjà pris), changer le préfixe dans `project.yml`
   (ex. `com.cyrilfeltrin`) et régénérer.
3. Product > Archive ne fonctionne pas pour un vrai export IPA avec un compte gratuit ;
   deux options :
   - **Option simple** : brancher l'iPhone en USB, le sélectionner comme destination
     dans Xcode et Run - l'app s'installe signée 7 jours. SideStore n'est alors utile
     que pour la re-signature sans Mac (voir 4.3).
   - **Option IPA pour SideStore** : Product > Build pour "Any iOS Device", puis créer
     l'IPA manuellement à partir du .app :
     `mkdir Payload && cp -R Muscu.app Payload/ && zip -r Muscu.ipa Payload`
     (SideStore re-signe lui-même l'IPA, la signature d'origine importe peu).
4. Sur l'iPhone : Réglages > Général > VPN et gestion de l'appareil > faire confiance
   au profil développeur.

### 4.2 Installer SideStore

Suivre https://sidestore.io/ :
1. Installer AltServer sur le Mac (nécessaire une seule fois pour amorcer).
2. Installer SideStore sur l'iPhone via AltServer (iPhone branché, même wifi).
3. Dans SideStore : se connecter avec le compte Apple gratuit, installer le profil
   "pairing file" généré (suivre la doc officielle, elle évolue régulièrement).

### 4.3 Installer et maintenir Muscu

1. Transférer `Muscu.ipa` sur l'iPhone (AirDrop ou Fichiers).
2. Ouvrir SideStore > My Apps > + > choisir Muscu.ipa -> installation signée 7 jours.
3. La re-signature se fait depuis SideStore directement sur l'iPhone (bouton Refresh),
   sans Mac, tant que le "pairing file" est valide. Activer le rafraîchissement
   en arrière-plan de SideStore.

### 4.4 Après installation : checklist de validation sur appareil

Dérouler la checklist de la section 1 (notifications, mode avion, AMRAP).
Penser aussi à :
- Exporter une sauvegarde JSON (Réglages > Données) après les premières séances :
  avec le sideload, une app supprimée = données perdues (l'import les restaure).
- "Tout télécharger" les images en wifi pour un hors-ligne complet (~150 Mo).

## 5. Limitations connues / choix assumés

- Zones à ménager "Genoux"/"Poignets" du questionnaire : inertes (le catalogue n'a pas
  ces clés musculaires ; seules les zones correspondant à un muscle réel filtrent).
- Le générateur est déterministe : "Régénérer" avec les mêmes réponses redonne le
  même programme.
- `ByteCountFormatter` affiche "KB/MB" au lieu de "Ko/Mo" (limitation Foundation).
- La rotation "prochaine séance" de l'accueil se base sur les noms (renommer un
  programme réinitialise la rotation).
- Remplacer un exercice en cours de séance : les séries déjà loggées sur l'ancien
  exercice restent regroupées avec lui dans l'historique.

## 6. Où trouver l'historique du développement

- Spec : `docs/superpowers/specs/2026-07-16-muscu-app-design.md`
- Plan (23 tâches) : `docs/superpowers/plans/2026-07-16-muscu-app.md`
- Journal de progression détaillé (par tâche, avec commits et findings) :
  `.superpowers/sdd/progress.md` (non commité - historique local) ; l'historique
  git (`git log`) reste la référence commitée.
- Chaque commit correspond à une tâche ou un correctif de revue, messages en français.
