# 0008 — Coach IA : protocole, validation locale et consentement

Date : 14/09/2026
Statut : accepté

## Contexte

La phase 8 ajoute une couche IA capable de créer, expliquer et adapter des
programmes. Trois risques la distinguent de tout ce qui précède : une sortie
probabiliste peut être fausse, la requête part chez un tiers, et le contenu
que nous envoyons contient du texte que nous ne contrôlons pas.

## Décisions

### 1. Le moteur décide de ce qui est acceptable, pas le modèle

`MuscuEngine/AI/` porte les schémas, l'assainissement, la validation et le
filtre de sécurité. Aucune de ces règles ne connaît le réseau : elles sont
testables sans fournisseur, sans clé et sans connexion.

Conséquence : **aucun programme n'est construit en analysant du texte libre**.
Une réponse en prose est rejetée, pas interprétée. Un identifiant d'exercice
absent du catalogue est retiré — jamais « rapproché » d'un exercice existant,
ce qui reviendrait à deviner ce que le modèle voulait dire.

### 2. La réparation est bornée, et elle est dite

Les valeurs hors bornes sont ramenées dans celles de l'éditeur : une
proposition d'IA ne doit jamais produire une prescription que l'utilisateur ne
pourrait pas modifier ensuite. Chaque correction est listée à l'écran.

Au-delà d'un tiers d'exercices inconnus, la proposition est **rejetée**.
Réparer sans limite reviendrait à fabriquer un programme et à l'attribuer au
modèle.

### 3. Le contenu non fiable est isolé, pas filtré

Les notes, les noms d'exercices importés et les commentaires sont des données.
La protection ne repose pas sur la détection de phrases suspectes — un filtre
de mots-clés se contourne — mais sur trois mesures cumulées : le contenu est
placé dans un bloc délimité dont les délimiteurs sont neutralisés, les
caractères invisibles et de contrôle sont retirés, et la longueur est bornée.
Une consigne système rappelle que ce bloc ne contient pas d'instructions.

### 4. Le consentement est granulaire et se relit

Cinq catégories, dont trois sensibles (mensurations, check-in, notes),
**exclues par défaut**. Une catégorie refusée n'est pas mise à `nil` après
coup : elle n'est jamais lue, et le JSON envoyé ne la mentionne même pas — un
test le vérifie sur la charge utile encodée.

Aucune capacité n'exige une catégorie sensible : elle en tire parti si elle est
accordée, jamais plus. Les données HealthKit, l'identité et les photos ne
partent jamais.

### 5. La clé reste dans le Trousseau

Mode BYOK uniquement. La clé est écrite dans le Trousseau avec
`WhenUnlockedThisDeviceOnly` : ni sauvegardée, ni synchronisée, ni exportée,
ni journalisée. Elle ne quitte le Trousseau que pour former l'en-tête
d'autorisation — un test vérifie qu'elle n'apparaît pas dans le corps de la
requête.

**Aucune clé fournisseur n'est embarquée dans l'application.** Sans
configuration, l'écran annonce l'indisponibilité et renvoie vers le générateur
local.

### 6. Le repli local est un vrai repli, et il est annoncé

Erreur réseau, réponse illisible, proposition rejetée : le générateur local
prend le relais. L'écran dit alors explicitement « produit par le générateur
local » avec la raison. Laisser croire que le modèle a répondu serait un
mensonge sur l'origine de la proposition.

Aucun écran d'entraînement ne dépend du réseau ni de l'IA.

### 7. Le journal technique ne contient rien de personnel

Capacité appelée, modèle, durée, résultat, nombre de corrections. Ni la
demande, ni le contexte, ni la réponse, ni le raisonnement du modèle. Un test
vérifie qu'un prénom et un poids saisis dans la demande n'apparaissent pas
dans le diagnostic exportable.

### 8. L'IA reste derrière un drapeau, désactivé par défaut

La roadmap l'exige tant que sécurité, politique de confidentialité et
évaluations ne sont pas validées. Le drapeau est visible, explicite, et son
écran dit ce qui manque pour que le coach fonctionne.

## Ce qui n'est pas fait

**Le backend géré n'est pas implémenté.** Il suppose des décisions qui ne
m'appartiennent pas : durée de conservation, région d'hébergement, fournisseur,
facturation et politique de données. Écrire un client pour un service qui
n'existe pas produirait du code jamais exécuté — le même piège que
`CloudKitSyncTransport` en phase 5, et le même refus.

**Le mode BYOK n'a jamais été exécuté contre un vrai fournisseur.** Il est
testé contre un faux service HTTP couvrant les codes 401/429/500, une réponse
tronquée, un JSON conforme mais hostile, un dépassement de délai et une
annulation. Cela couvre le comportement de l'application ; cela ne remplace pas
un essai réel avec une clé.

**Le corpus d'évaluation ne juge pas la qualité des réponses d'un modèle.**
Nous n'avons pas de modèle à évaluer. Il vérifie ce qui est vérifiable sans
fournisseur : déterminisme du repli local et refus systématique des
propositions hors contraintes, sur huit combinaisons d'objectif, niveau,
matériel, durée et restrictions.
