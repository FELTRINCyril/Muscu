# Préparation App Store — état et reste à faire

Dernière vérification : 14/09/2026.

## Prêt

| Élément | État |
| --- | --- |
| Identifiants | `com.cyril.Muscu`, `.Widgets`, `.watchkitapp` |
| Version | `MARKETING_VERSION` 0.1.0, build 1 |
| Icône | `AppIcon` dans `App/Resources/Assets.xcassets` |
| Écran de lancement | Généré (`INFOPLIST_KEY_UILaunchScreen_Generation`) |
| Privacy Manifest | `App/Resources/PrivacyInfo.xcprivacy`, cohérent avec l'inventaire des données |
| Descriptions d'usage | Santé et Calendrier, rédigées dans `project.yml` |
| Inventaire des données | `docs/confidentialite/inventaire-des-donnees.md` |
| Modèle de menaces | `docs/securite/modele-de-menaces.md` |
| Procédure de retour arrière | `docs/configuration/icloud.md` |
| Notes de version | `CHANGELOG.md` |
| Achats intégrés | Aucun — et aucun ne sera ajouté sans proposition de valeur ni restauration spécifiées |

## Reste à faire, et ce que ça demande

| Élément | Bloqué par |
| --- | --- |
| Équipe de développement dans `project.yml` | Adhésion payante |
| Archive Release **signée** | Idem |
| TestFlight sur appareils réels | Idem |
| Captures iPhone / iPad / Mac | Une archive installable |
| Politique de confidentialité en ligne | Une page publiée par le propriétaire ; le contenu est déjà écrit dans l'inventaire des données |
| Page d'assistance | Idem |
| Fiche de confidentialité App Store | Se remplit depuis l'inventaire des données : aucune collecte, aucun suivi |
| Localisation anglaise | Voir `docs/qualite/localisation.md` |

## Ce qu'il faudra vérifier sur l'archive

1. **Aucun secret dans le binaire** : la clé du fournisseur IA vit dans le
   Trousseau, jamais dans le paquet. À revérifier sur l'archive produite
   (`strings` sur le binaire).
2. **Installation, mise à jour et restauration** : installer la version
   précédente, créer des données, mettre à jour, vérifier que la migration
   passe et que rien n'est perdu.
3. **Permissions réellement demandées** : elles doivent correspondre aux
   déclarations App Store — Santé, notifications, calendrier, photothèque.
