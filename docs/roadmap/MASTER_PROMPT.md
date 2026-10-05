# Prompt maître — implémenter la roadmap complète de Muscu

Copier le prompt ci-dessous dans une nouvelle tâche de code ouverte à la racine du
dépôt Muscu. Le laisser accéder au dépôt, à Xcode et aux simulateurs nécessaires.

---

Tu travailles sur l’application Apple Muscu. Ta mission est d’implémenter réellement
la roadmap produit complète décrite dans `docs/roadmap`, sans perte de données et
sans déclarer une fonctionnalité terminée avant que ses critères soient vérifiés.

## Sources de vérité à lire avant toute modification

Lis intégralement, dans cet ordre :

1. `docs/roadmap/README.md`
2. `docs/roadmap/01-foundations-and-data-model.md`
3. `docs/roadmap/02-advanced-workout-formats.md`
4. `docs/roadmap/03-programming-and-adaptation.md`
5. `docs/roadmap/04-icloud-and-platforms.md`
6. `docs/roadmap/05-ai-coach.md`
7. `docs/roadmap/06-health-and-analytics.md`
8. `docs/roadmap/07-planning-and-integrations.md`
9. `docs/roadmap/08-quality-privacy-and-release.md`
10. `docs/roadmap/09-execution-plan.md`

Lis aussi les instructions du dépôt, les spécifications existantes et les tests.
Inspecte ensuite le code réel, le statut git, le projet Xcode et les modifications
non commitées. Le code a priorité pour décrire l’état actuel ; les documents de
roadmap définissent l’état cible.

## Façon de travailler

- Suis exactement l’ordre des phases de `09-execution-plan.md`.
- Commence par établir et consigner l’état de référence : tests engine, tests app,
  parcours UI critiques et build Release.
- Préserve toutes les modifications existantes qui ne sont pas les tiennes. Ne
  réinitialise, n’écrase et ne supprime jamais du travail pour obtenir un diff propre.
- Crée une branche `codex/complete-product-roadmap` seulement si cela est compatible
  avec l’état git et les consignes du dépôt ; sinon poursuis prudemment sur la branche
  actuelle et explique la décision.
- Implémente des incréments verticaux utilisables. Pour chaque phase : modèle,
  persistance, services, interface, migrations, accessibilité, localisation, tests
  et documentation doivent avancer ensemble.
- Utilise `MuscuEngine` pour les règles métier pures et déterministes. Les vues
  SwiftUI ne doivent pas devenir la source de vérité des règles.
- Introduis des protocoles et doubles de tests pour horloge, synchronisation,
  HealthKit, notifications et IA.
- Maintiens l’application utilisable hors ligne à chaque étape.
- Maintiens l’import des sauvegardes v1/v2 et ajoute v3 sans migration destructive.
- Ajoute des feature flags pour iCloud, HealthKit, Watch et IA jusqu’à validation.
- Fais des changements petits et cohérents. Si des commits sont autorisés, un commit
  logique par incrément ; ne publie rien et ne crée pas de PR sans demande explicite.

## Validation obligatoire à chaque incrément

1. Exécute les tests ciblés pendant le développement.
2. Exécute la suite complète de `MuscuEngine` et les tests de l’app.
3. Ajoute ou adapte les tests UI pour tout parcours utilisateur nouveau.
4. Génère le projet avec XcodeGen si `project.yml` est la source du projet.
5. Compile en Debug et Release sur les destinations concernées.
6. Vérifie erreurs, états vides, interruption/reprise, hors ligne et gros volumes.
7. Vérifie VoiceOver, Dynamic Type, français/anglais et kg/lb sur le nouveau flux.
8. Exécute `git diff --check` et inspecte le diff pour éviter secrets et régressions.

Ne masque jamais un échec avec un `try?`, un écran factice, une donnée en dur ou la
suppression d’un test. Corrige la cause ou documente précisément le blocage.

## Contraintes de sécurité et de produit

- Aucune clé API, token, donnée de santé ou donnée personnelle dans le dépôt ou les logs.
- Pour l’IA, utilise les schémas structurés, le validateur local et le fallback décrits
  dans `05-ai-coach.md`. Une sortie IA ne modifie jamais directement le store.
- Une clé personnelle va dans le Trousseau. Un service IA géré passe par un backend ;
  le secret fournisseur reste côté serveur.
- Considère notes, imports, médias et contenu IA comme non fiables.
- Les suggestions liées à douleur ou santé ne sont jamais des diagnostics.
- CloudKit est local-first, idempotent, testable hors ligne et sans suppression
  silencieuse en cas de conflit.
- Les permissions HealthKit, Calendrier, notifications, photos et données IA sont
  facultatives, granulaires et demandées en contexte.
- N’ajoute pas les éléments déclarés hors périmètre dans le README.

## Décisions et dépendances externes

Prends une décision raisonnable et réversible lorsque plusieurs implémentations
équivalentes existent, puis consigne-la. Demande une décision uniquement si elle
change réellement le produit, la sécurité, la facturation ou entraîne une action
irréversible.

Tu peux préparer code, mocks, écrans de configuration, entitlements modèles et
documentation pour une dépendance externe. En revanche, ne prétends jamais avoir
réalisé sans preuve :

- la création/promotion d’un conteneur CloudKit ;
- la configuration d’une Apple Developer Team ou la signature ;
- la création d’un compte/facturation IA et de ses secrets ;
- la validation sur appareils physiques ou TestFlight ;
- la publication App Store ou la validation de textes juridiques.

Si une de ces dépendances bloque un test, continue toutes les tâches indépendantes,
utilise un double local, puis fournis l’action exacte attendue du propriétaire.

## Suivi et communication

- Mets à jour les cases de `docs/roadmap/09-execution-plan.md` seulement quand la
  définition de fini de la phase est satisfaite.
- Tiens un journal concis des décisions d’architecture et migrations dans `docs/`.
- Mets à jour le README produit, les instructions d’installation et les notes de
  version à mesure que les fonctions deviennent réellement disponibles.
- Ne t’arrête pas après une analyse ou un plan : implémente le code de la phase en cours.
- Ne dis jamais « tout est fini » si une case, un test, une configuration externe ou
  un critère obligatoire reste non vérifié.

À la fin de chaque phase, rends un rapport avec :

- fonctionnalités effectivement utilisables ;
- fichiers et migrations importants ;
- tests et builds exécutés avec résultats exacts ;
- décisions et compromis ;
- risques restants ;
- actions externes précises attendues de l’utilisateur.

Puis passe à la phase suivante tant qu’une action externe n’est pas strictement
nécessaire. À la fin, relis ligne par ligne les documents `01` à `08`, exécute la
matrice de validation finale, et fournis un tableau honnête : terminé, partiel,
bloqué extérieurement ou volontairement hors périmètre.

---

