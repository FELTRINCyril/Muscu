# Tester sur un iPhone et une Apple Watch sans compte développeur payant

Un compte Apple **gratuit** permet d'installer l'application sur ses propres
appareils, avec deux limites : la signature expire au bout de **7 jours**, et
certaines capacités ne sont pas disponibles.

## Ce qui marche, et ce qui ne marche pas

| Fonction | Compte gratuit | Pourquoi |
| --- | --- | --- |
| Séances, historique, planning, records, analyses | ✅ | Aucune capacité spéciale |
| Rappels de séance | ✅ | Notifications **locales** : aucun entitlement |
| Coach IA (clé personnelle) | ✅ | Réseau simple |
| Live Activity | ✅ | Clé d'`Info.plist`, pas un entitlement |
| Application Watch + transfert des séances | ✅ | `WatchConnectivity` n'exige aucun entitlement |
| Widgets | ❌ | Exigent un **groupe d'applications** |
| Partage avec Santé | ❌ | Exige l'entitlement **HealthKit** |
| Synchronisation iCloud | ❌ | Exige **CloudKit**, réservé aux comptes payants |

Les deux fonctions indisponibles **dégradent proprement** : l'écran Santé
annonce l'indisponibilité, et les widgets affichent leur état vide. Rien ne
plante, rien n'est perdu.

## Étapes

1. **Ajouter votre Apple ID** dans Xcode : `Settings → Accounts → +`.
   Votre équipe apparaît comme « *Votre nom* (Personal Team) ».
2. **Relever son identifiant** : `Settings → Accounts`, sélectionnez l'équipe ;
   l'identifiant à 10 caractères est affiché à côté de son nom.
3. **Préparer l'iPhone** : branchez-le, déverrouillez-le, acceptez « Faire
   confiance à cet ordinateur », puis activez
   `Réglages → Confidentialité et sécurité → Mode développeur` et redémarrez.
4. **Vérifier que la Watch est appairée à cet iPhone.** L'application Watch est
   embarquée dans l'app iPhone : elle s'installe avec elle.
5. **Récupérer l'identifiant de l'appareil** :
   ```bash
   xcrun devicectl list devices
   ```
6. **Installer**, en remplaçant l'identifiant d'équipe et celui de l'appareil :
   ```bash
   xcodebuild -project Muscu.xcodeproj -scheme Muscu \
     -destination 'id=IDENTIFIANT_APPAREIL' \
     -configuration Debug \
     DEVELOPMENT_TEAM=VOTRE_EQUIPE \
     CODE_SIGN_ENTITLEMENTS="$PWD/App/Resources/Sans-compte-payant.entitlements" \
     build
   ```
   Le fichier d'entitlements vide s'applique à toutes les cibles : c'est
   exactement ce qu'il faut, puisqu'aucune ne peut réclamer de capacité.

   Le chemin doit être **absolu** (`$PWD/…`) : un chemin relatif serait
   résolu depuis chaque projet, y compris le paquet `MuscuEngine`, et la
   compilation échouerait sur un fichier introuvable.
7. **Faire confiance au certificat** sur l'iPhone, au premier lancement :
   `Réglages → Général → VPN et gestion de l'appareil`.

## Ce qu'il faut vérifier une fois installé

Ce sont les points que le simulateur ne peut pas démontrer.

1. **Transfert hors de portée** — faire une séance sur la Watch avec l'iPhone
   éteint ou laissé loin, puis rapprocher les deux. La séance doit arriver
   **une seule fois**. La montre affiche entre-temps « séance(s) en attente
   d'envoi ».
2. **Transfert rejoué** — refaire l'opération : l'historique ne doit pas
   contenir de doublon.
3. **Live Activity** — lancer une séance, verrouiller l'iPhone, vérifier
   l'affichage, puis sa disparition à la fin **et** à l'abandon.
4. **Autonomie** — une séance complète au poignet.

## Après les 7 jours

La signature expire et l'application refuse de s'ouvrir. Il suffit de
réinstaller avec la même commande. Les données restent sur l'appareil tant que
l'application n'est pas supprimée.
