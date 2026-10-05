# 0012 — Séance en direct : précédent, records et disques

Date : 04/10/2026
Statut : accepté

## Contexte

Le lot 2 de `docs/roadmap/10-inspirations-open-source.md` enrichit l'écran de
saisie : valeur précédente par série, dernières séances, record célébré,
calculateur de disques, calculateur de 1RM et bips de fin de repos. Aucune de
ces fonctions ne doit toucher au schéma (v7 figé dans son contenu).

## Décisions

### 1. « Série précédente » = même rang de série de travail

Le rang compte uniquement les séries de travail prescrites principales
(`role == .working`, `subSetIndex == 0`) : un échauffement, une approche, un
back-off ou un palier de dropset ne décale pas la 3e série. La séance de
référence est la dernière de la **même séance de programme** contenant
l'exercice, sinon la dernière tout court. L'historique d'un exercice est lu
une fois par séance (cache ignoré par l'observation) : les séries en cours ne
rejoignent `CompletedSession` qu'à la fin.

### 2. Célébration sans état ni écriture

`LiveRecord.celebration` compare la série validée aux meilleures valeurs
**antérieures** (1RM saisi, records typés non qualifiés) et ne célèbre que si
aucune série précédente de la séance ne les battait déjà. « Une fois par
exercice et par séance » se déduit donc des séries enregistrées : rien à
persister, et une reprise de séance ne rejoue pas la fête. Sans référence
(premier passage sur l'exercice), rien n'est célébré. La fin de séance
(`RecordDetection`, `PersonalBestUpdater`) reste seule à écrire.

### 3. Inventaire de disques : réglage local par unité

L'inventaire (barre, paires de disques) est un réglage d'appareil, comme le
repos par défaut : il vit dans `UserDefaults`, sérialisé en JSON, **une clé
par unité** — des disques en livres ne sont pas des disques en kilos
convertis, et changer d'unité n'efface pas l'autre inventaire. Une valeur
illisible est journalisée et remplacée par le jeu standard. Le calcul se fait
en millièmes entiers de l'unité (pas de flottants) par somme de
sous-ensembles bornée, jamais par algorithme glouton.

### 4. Bips au premier plan seulement

Les trois bips sont joués par l'application ouverte. En arrière-plan, la
notification de fin existante garde son son unique : programmer trois
notifications supplémentaires afficherait trois bannières, et un son de
notification personnalisé imposerait un fichier audio dédié — complexité
jugée excessive pour le gain.
