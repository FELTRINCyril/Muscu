# Muscu — plan produit complet

Ce dossier décrit l’évolution de Muscu depuis l’application locale actuelle vers
un produit complet, synchronisé et multi-plateforme. Il constitue la source de
vérité fonctionnelle pour les prochains développements.

Le mot « complet » désigne ici toutes les fonctionnalités manquantes identifiées
dans l’audit et l’inventaire produit de septembre 2026. Il ne signifie pas que
toute fonctionnalité imaginable dans le domaine du fitness doit être ajoutée.
Une nouvelle idée non décrite ici doit faire l’objet d’une décision produit avant
d’élargir le périmètre.

## Documents

1. [01-foundations-and-data-model.md](01-foundations-and-data-model.md) — socle,
   schéma, migrations et conventions transversales.
2. [02-advanced-workout-formats.md](02-advanced-workout-formats.md) — supersets,
   trisets, circuits, dropsets, rest-pause, myo-reps, tempo, RPE et RIR.
3. [03-programming-and-adaptation.md](03-programming-and-adaptation.md) — profil,
   objectifs, périodisation, surcharge progressive et récupération.
4. [04-icloud-and-platforms.md](04-icloud-and-platforms.md) — synchronisation
   iCloud, sauvegardes, iPad, Mac, Apple Watch, widgets et Live Activities.
5. [05-ai-coach.md](05-ai-coach.md) — génération et adaptation avec IA, sécurité,
   validation et fonctionnement dégradé.
6. [06-health-and-analytics.md](06-health-and-analytics.md) — mesures corporelles,
   HealthKit, graphiques, volume, fatigue, objectifs et exports.
7. [07-planning-and-integrations.md](07-planning-and-integrations.md) — calendrier,
   rappels, équipement, modèles, médias et import/export interopérable.
8. [08-quality-privacy-and-release.md](08-quality-privacy-and-release.md) —
   accessibilité, localisation, sécurité, observabilité et distribution.
9. [09-execution-plan.md](09-execution-plan.md) — ordre d’implémentation,
   dépendances et portes de validation.
10. [MASTER_PROMPT.md](MASTER_PROMPT.md) — prompt prêt à donner à un agent de code.

## État fonctionnel cible

À la fin du plan, un utilisateur doit pouvoir :

- construire ou générer un programme complet, puis le faire évoluer par cycles ;
- exécuter des séries classiques et tous les formats avancés décrits ;
- suivre charge, répétitions, RPE/RIR, tempo, douleur, fatigue et récupération ;
- retrouver automatiquement ses données sur iPhone, iPad et Mac via iCloud ;
- utiliser une séance simplifiée sur Apple Watch ;
- bénéficier d’un coach IA dont chaque proposition est validée par le moteur local ;
- planifier ses séances et recevoir des rappels utiles, non envahissants ;
- consulter une progression détaillée et exporter l’intégralité de ses données ;
- continuer à s’entraîner hors ligne et laisser la synchronisation se faire ensuite.

## Principes non négociables

- **Local-first** : une séance ne dépend jamais du réseau pour fonctionner.
- **Aucune perte de données** : migrations testées, écritures explicites,
  sauvegardes et mécanisme de récupération.
- **Pas de secret embarqué** : aucune clé fournisseur incluse dans l’application.
- **IA sous contrôle** : sortie structurée, validation déterministe, consentement
  explicite et aucune recommandation médicale.
- **Synchronisation explicable** : état visible, conflits déterministes et option
  permettant de travailler uniquement en local.
- **Compatibilité** : les exports JSON v1 et v2 restent importables.
- **Accessibilité** : VoiceOver, Dynamic Type, contraste et Reduce Motion sont
  des critères de livraison, pas une phase facultative.
- **Tests obligatoires** : chaque fonctionnalité possède des tests unitaires,
  d’intégration et, pour les parcours principaux, des tests UI.

## Hors périmètre volontaire

- diagnostic, traitement médical ou rééducation prescrite ;
- réseau social public, messagerie entre utilisateurs et classement mondial ;
- marketplace payante de coachs ou de programmes ;
- suivi nutritionnel clinique ;
- compatibilité Android ou Web dans ce plan ;
- contrôle d’appareils de musculation propriétaires sans API publique documentée.

Ces sujets peuvent devenir des projets séparés. Ils ne doivent pas retarder la
livraison du socle décrit ici.
