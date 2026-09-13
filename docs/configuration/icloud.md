# Activer la synchronisation iCloud

Ce document décrit **les actions que seul le propriétaire du compte
développeur peut réaliser**, et ce que l'application fait déjà sans elles.

## État actuel, sans configuration

- La synchronisation est **désactivée** et l'écran *Réglages → Synchronisation*
  affiche « Synchronisation indisponible / pas encore configurée ».
- `CloudKitSyncTransport.availability()` renvoie `notConfigured` : aucun appel
  réseau n'est tenté, aucune promesse n'est faite.
- **Tout le reste fonctionne** : séances, programmes, historique, mesures,
  export et import restent entièrement disponibles hors ligne.

Rien dans l'application ne prétend synchroniser tant que les étapes ci-dessous
n'ont pas été faites.

## Ce qui est déjà prêt côté code

| Élément | État |
|---|---|
| Moteur de réconciliation (fusion, conflits, tombstones) | Implémenté, 27 tests |
| File d'attente persistante avec backoff exponentiel | Implémenté et testé |
| Scénarios à deux appareils (hors ligne, ordre inversé, rejeu, conflits) | 14 tests d'intégration |
| Écran d'état, conflits à trancher, diagnostic exportable | Implémenté |
| Transport CloudKit | **Squelette seulement**, non validé |
| Modèle d'entitlements | `App/Resources/Muscu.entitlements.modele` |

## Étapes à réaliser (propriétaire du compte)

1. **Apple Developer** — disposer d'une équipe active et renseigner
   `DEVELOPMENT_TEAM` dans `project.yml`.
2. **Créer le conteneur CloudKit** `iCloud.com.cyril.Muscu` depuis Xcode
   (onglet *Signing & Capabilities* → *+ Capability* → *iCloud* → *CloudKit*)
   ou depuis le tableau de bord CloudKit.
3. **Activer le fichier d'entitlements** : renommer
   `App/Resources/Muscu.entitlements.modele` en `Muscu.entitlements`, puis
   ajouter dans `project.yml`, sous `targets.Muscu.settings.base` :
   ```yaml
   CODE_SIGN_ENTITLEMENTS: App/Resources/Muscu.entitlements
   ```
4. **Renseigner l'identifiant du conteneur** dans
   `CloudKitSyncTransport.containerIdentifier`.
5. **Implémenter puis valider le transport** : la conversion `SyncRecord` ↔
   `CKRecord` est volontairement absente. L'écrire sans pouvoir l'exécuter une
   seule fois donnerait une fausse impression de fonctionnement.
6. **Valider en environnement Development** avec deux appareils réels et un
   compte iCloud de test : scénario hors ligne, reprise, changement de compte.
7. **Promouvoir le schéma en Production** uniquement après cette validation.

## Procédure de retour arrière

La synchronisation n'est pas une source de vérité : elle recopie. En cas de
problème après activation :

1. Désactiver l'interrupteur dans *Réglages → Synchronisation*. L'application
   repasse immédiatement en local pur, **sans rien supprimer**.
2. Exporter une sauvegarde v3 complète (*Réglages → Exporter*).
3. Si nécessaire, réinstaller et réimporter cette sauvegarde en mode
   **Remplacer** : une sauvegarde de sécurité est créée automatiquement avant.

Aucune étape de ce retour arrière ne dépend d'iCloud.

## Ce qui n'est volontairement pas fait

- **Le miroir CloudKit automatique de SwiftData** n'est pas utilisé : il
  interdit les contraintes `@Attribute(.unique)` (20 dans ce modèle) et ne
  fournit ni file d'attente inspectable, ni conflits visibles, ni
  déduplication idempotente — toutes exigées par la roadmap.
- **Les données de santé** ne partent pas vers iCloud dans cette phase :
  HealthKit relève de la phase 7 et de son propre consentement.
