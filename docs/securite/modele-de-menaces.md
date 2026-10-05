# Modèle de menaces

Court par choix : un document que personne ne relit ne protège rien. Il couvre
les quatre endroits où des données entrent ou sortent — synchronisation, coach
IA, imports, widgets et montre — et sera mis à jour à chaque phase qui les
touche.

Dernière révision : 14/09/2026.

## Ce qu'on protège

1. L'**historique d'entraînement** : irremplaçable, non reconstituable.
2. Les **données sensibles** : mesures corporelles, douleurs déclarées, photos.
3. La **clé du fournisseur IA** : un secret qui engage un compte payant.

## Menaces et parades

### Import de fichiers (CSV, JSON, modèles)

| Menace | Parade |
| --- | --- |
| Fichier volumineux qui épuise la mémoire | 200 000 lignes maximum, 20 Mo pour une archive JSON |
| Archive falsifiée | Somme de contrôle SHA-256 du contenu, vérifiée **avant** toute écriture |
| Valeurs hors bornes | Validation complète avant mutation ; l'import est annulé en bloc en cas d'erreur |
| Ligne illisible ignorée en silence | Mise en **quarantaine** avec la ligne brute et la raison |
| Formule injectée dans un CSV exporté | Champ commençant par `=`, `+` ou `@` cité et préfixé d'une apostrophe |
| Guillemet jamais refermé qui avale le fichier | Refus explicite, pas de devinette |

### Coach IA

| Menace | Parade |
| --- | --- |
| Injection d'instructions par une note ou un nom d'exercice importé | Contenu isolé dans un bloc délimité dont les délimiteurs sont neutralisés ; caractères invisibles retirés ; consigne système rappelant que ce bloc est une donnée |
| Réponse construisant un programme absurde ou dangereux | Schéma strict, identifiants d'exercices restreints au catalogue, réparation **bornée**, filtre de sécurité sur les progressions |
| Fuite de données sensibles | Consentement par catégorie, sensibles exclues par défaut ; une catégorie refusée n'est jamais lue |
| Fuite de la clé | Trousseau `WhenUnlockedThisDeviceOnly`, jamais dans le corps d'une requête ni dans un journal |
| Coût incontrôlé | Limite mensuelle, confirmation avant une requête longue |

### Synchronisation (quand elle sera activée)

| Menace | Parade |
| --- | --- |
| Doublons à la reprise | Réconciliation idempotente et insensible à l'ordre d'arrivée |
| Perte silencieuse | Historique terminé immuable ; conflits **visibles**, jamais résolus dans le dos |
| Changement de compte iCloud | La synchronisation s'arrête au lieu de fusionner deux comptes |

### Widgets et montre

| Menace | Parade |
| --- | --- |
| Donnée sensible visible sur un écran verrouillé | L'instantané ne contient que ce que le widget affiche — vérifié par un test |
| Base ouverte depuis un autre processus | Les widgets ne lisent jamais la base, seulement un fichier d'instantané |
| Transfert rejoué créant un doublon | Identifiant frappé à la montre, unique dans le modèle |

## Ce qui n'est pas couvert

- Un **appareil déverrouillé entre les mains d'un tiers** : Muscu ne propose ni
  verrouillage par code ni Face ID pour l'application elle-même.
- Un **appareil jailbreaké** : le Trousseau et le bac à sable n'y garantissent
  plus rien.
- La **politique du fournisseur IA** : ce qu'il fait des requêtes reçues relève
  de son contrat, pas de ce code.
