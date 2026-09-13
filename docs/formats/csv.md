# Formats CSV de Muscu

## Export

L’export CSV est **stable et documenté** : il peut être lu par un tableur ou
un autre outil sans rien connaître de Muscu.

Conventions communes :

- séparateur `,`, guillemets doubles échappés en les doublant ;
- dates ISO 8601 (`2026-01-05T18:00:00Z`) ;
- nombres au point décimal ;
- **unités canoniques** : kilogrammes et centimètres, quelle que soit l’unité
  d’affichage choisie dans l’application ;
- un champ commençant par `=`, `+` ou `@` est préfixé d’une apostrophe pour
  qu’une note ne devienne pas une formule exécutée à l’ouverture du fichier.

Quatre jeux de données sont exportables séparément depuis
*Réglages → Mes données* :

| Fichier | Contenu | Colonnes |
| --- | --- | --- |
| `muscu-seances` | une ligne par séance terminée | `id`, `date`, `programme`, `seance`, `duree_secondes`, `series_de_travail`, `repetitions`, `tonnage_kg`, `series_sans_tonnage`, `poids_de_corps_kg`, `notes` |
| `muscu-series` | une ligne par série réalisée | `seance_id`, `date`, `exercice_id`, `exercice`, `exercice_prevu_id`, `format`, `role`, `tour`, `serie`, `sous_serie`, `charge_kg`, `type_de_charge`, `repetitions`, `duree_secondes`, `effort`, `echec`, `tempo`, `cote`, `notes` |
| `muscu-mesures` | mensurations et poids | `id`, `date`, `type`, `nom_personnalise`, `valeur`, `unite`, `source`, `notes`, `supprimee` |
| `muscu-checkins` | check-in de forme | `id`, `date`, `energie`, `sommeil`, `courbatures`, `stress`, `douleur`, `zone_douleur`, `notes` |

`series_sans_tonnage` compte les séries dont la charge effective est inconnue
(par exemple un exercice au poids du corps sans poids de corps renseigné) :
leur tonnage n’est pas inventé, il est compté à part.

L’export JSON complet (`Réglages → Mes données → Exporter`) reste le format de
référence pour une sauvegarde : lui seul contient tout, avec un manifeste et
une somme de contrôle.

## Import

*Réglages → Importer un CSV*. Rien n’est écrit avant l’étape finale.

### Colonnes reconnues

| Champ | Obligatoire | Notes |
| --- | --- | --- |
| Date | oui | ISO 8601, `yyyy-MM-dd HH:mm:ss`, `dd/MM/yyyy`, `22 Jan 2026, 17:41`… |
| Exercice | oui | relié au catalogue quand le nom correspond, sinon conservé tel quel |
| Nom de séance | non | sert à regrouper les lignes et à détecter les doublons |
| Numéro de série | non | à défaut, l’ordre des lignes est conservé |
| Type de série | non | `normal`, `warmup`, `failure`, `dropset`… ; une valeur inconnue part en quarantaine |
| Charge | non | convertie en kilogrammes selon l’unité choisie ou la colonne d’unité |
| Répétitions / Durée / Distance | au moins une | sans aucune mesure, la ligne part en quarantaine |
| Effort (RPE) | non | |
| Notes | non | |

Une ligne doit porter une date, un exercice et au moins une mesure.

### Formats pré-remplis

- **CSV générique** : correspondance proposée d’après les en-têtes, en français
  comme en anglais, puis modifiable colonne par colonne.
- **Strong** : détecté par `Workout Name`, `Exercise Name`, `Set Order`.
- **Hevy** : détecté par `exercise_title`, `set_index`, `start_time` ; les
  distances sont lues en kilomètres.

Un préréglage ne fait que **pré-remplir** la correspondance : chaque colonne
reste modifiable, et une colonne peut être marquée « Ignorée ».

### Doublons, quarantaine et rapport

- La signature d’une séance est `date à la minute + nom normalisé`. Réimporter
  le même fichier ne crée donc aucun doublon, et une séance déjà saisie à la
  main est reconnue.
- Deux politiques : *Ignorer les doublons* (par défaut) ou *Importer quand
  même*, qui crée une seconde séance.
- Une séance terminée est immuable : **l’import ne fusionne jamais** dans une
  séance existante. Le compteur « fusionnées » reste donc à zéro.
- Une ligne inexploitable part en **quarantaine** avec sa ligne brute et la
  raison, consultable dans l’écran d’import.
- Le rapport indique : créées, fusionnées, doublons, ignorées, en quarantaine,
  ainsi que les noms d’exercices non reconnus.

### Limites de sécurité

- 200 000 lignes maximum par fichier ;
- un guillemet jamais refermé fait échouer la lecture au lieu d’avaler le reste
  du fichier ;
- l’écriture se fait en une seule transaction : un échec n’applique rien.
