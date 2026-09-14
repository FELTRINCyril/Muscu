import Foundation

/// Ce qu'une reponse d'IA devient apres controle local.
public struct AIValidationOutcome: Equatable, Sendable {
    /// Brouillon retenu, deja reparé quand c'etait possible. `nil` quand la
    /// reponse est rejetee.
    public let draft: AIProgramDraft?
    /// Corrections appliquees, listees pour l'utilisateur : une reparation
    /// silencieuse serait indiscernable d'une reponse correcte.
    public let repairs: [String]
    /// Violations qui n'ont pas pu etre corrigees.
    public let violations: [String]

    public var isAccepted: Bool { draft != nil }

    public init(draft: AIProgramDraft?, repairs: [String], violations: [String]) {
        self.draft = draft
        self.repairs = repairs
        self.violations = violations
    }
}

/// Bornes admissibles d'une prescription. Ce sont celles de l'editeur : une
/// proposition d'IA ne doit jamais produire une prescription que
/// l'utilisateur ne pourrait pas modifier ensuite.
public struct AIPrescriptionBounds: Equatable, Sendable {
    public var sets: ClosedRange<Int>
    public var reps: ClosedRange<Int>
    public var restSeconds: ClosedRange<Int>
    public var exercisesPerSession: ClosedRange<Int>
    public var sessionsPerProgram: ClosedRange<Int>

    public init(
        sets: ClosedRange<Int> = 1...10,
        reps: ClosedRange<Int> = 1...100,
        restSeconds: ClosedRange<Int> = 0...600,
        exercisesPerSession: ClosedRange<Int> = 1...15,
        sessionsPerProgram: ClosedRange<Int> = 1...14
    ) {
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.exercisesPerSession = exercisesPerSession
        self.sessionsPerProgram = sessionsPerProgram
    }

    public static let `default` = AIPrescriptionBounds()
}

/// Controle local d'une reponse d'IA.
///
/// Aucun brouillon n'est construit en analysant du texte libre : la reponse
/// arrive structuree, et ce validateur decide si elle est utilisable.
///
/// La reparation est BORNEE : on corrige ce qui est manifestement hors
/// bornes, on retire les exercices inconnus, mais au-dela d'un seuil on
/// rejette. Reparer sans limite reviendrait a fabriquer un programme et a
/// l'attribuer au modele.
public enum AIResponseValidator {
    /// Part maximale d'exercices inconnus toleree avant rejet.
    public static let maximumUnknownExerciseRatio = 0.34

    public static func validate(
        _ draft: AIProgramDraft,
        allowedExerciseIds: Set<String>,
        bounds: AIPrescriptionBounds = .default
    ) -> AIValidationOutcome {
        var repairs: [String] = []
        var violations: [String] = []

        let name = PromptSanitizer.clean(draft.name)
        if name.isEmpty {
            violations.append("Le programme proposé n’a pas de nom.")
        }

        var totalExercises = 0
        var unknownExercises = 0
        var sessions: [AISessionDraft] = []

        for session in draft.sessions {
            var exercises: [AIExerciseDraft] = []

            for exercise in session.exercises {
                totalExercises += 1

                // Un identifiant inconnu ne peut pas etre « rapproché » d'un
                // exercice existant : ce serait deviner ce que le modele
                // voulait dire.
                guard allowedExerciseIds.contains(exercise.exerciseId) else {
                    unknownExercises += 1
                    repairs.append("Exercice inconnu retiré : « \(PromptSanitizer.clean(exercise.exerciseId)) ».")
                    continue
                }

                var repaired = exercise
                repaired.notes = PromptSanitizer.clean(exercise.notes)

                if let clamped = clamp(exercise.sets, into: bounds.sets), clamped != exercise.sets {
                    repairs.append("Séries ramenées de \(exercise.sets) à \(clamped) pour « \(exercise.exerciseId) ».")
                    repaired.sets = clamped
                }

                let lower = clamp(exercise.repsLower, into: bounds.reps) ?? bounds.reps.lowerBound
                let upper = clamp(exercise.repsUpper, into: bounds.reps) ?? bounds.reps.upperBound
                if lower != exercise.repsLower || upper != exercise.repsUpper {
                    repairs.append("Répétitions ramenées à \(lower)–\(upper) pour « \(exercise.exerciseId) ».")
                }
                repaired.repsLower = min(lower, upper)
                repaired.repsUpper = max(lower, upper)

                if let rest = clamp(exercise.restSeconds, into: bounds.restSeconds), rest != exercise.restSeconds {
                    repairs.append("Repos ramené de \(exercise.restSeconds) s à \(rest) s pour « \(exercise.exerciseId) ».")
                    repaired.restSeconds = rest
                }

                exercises.append(repaired)
            }

            guard !exercises.isEmpty else {
                repairs.append("Séance « \(PromptSanitizer.clean(session.name)) » retirée : aucun exercice exploitable.")
                continue
            }

            if exercises.count > bounds.exercisesPerSession.upperBound {
                repairs.append("Séance « \(PromptSanitizer.clean(session.name)) » ramenée à \(bounds.exercisesPerSession.upperBound) exercices.")
                exercises = Array(exercises.prefix(bounds.exercisesPerSession.upperBound))
            }

            sessions.append(AISessionDraft(
                name: PromptSanitizer.clean(session.name),
                exercises: exercises
            ))
        }

        if totalExercises > 0 {
            let ratio = Double(unknownExercises) / Double(totalExercises)
            if ratio > maximumUnknownExerciseRatio {
                violations.append(
                    "\(unknownExercises) exercice(s) sur \(totalExercises) sont inconnus du catalogue : "
                    + "la proposition ne peut pas être réparée sans l’inventer."
                )
            }
        }

        if sessions.isEmpty {
            violations.append("Aucune séance exploitable dans la proposition.")
        } else if sessions.count > bounds.sessionsPerProgram.upperBound {
            repairs.append("Programme ramené à \(bounds.sessionsPerProgram.upperBound) séances.")
            sessions = Array(sessions.prefix(bounds.sessionsPerProgram.upperBound))
        }

        guard violations.isEmpty else {
            return AIValidationOutcome(draft: nil, repairs: repairs, violations: violations)
        }

        return AIValidationOutcome(
            draft: AIProgramDraft(
                name: name,
                notes: PromptSanitizer.clean(draft.notes),
                sessions: sessions
            ),
            repairs: repairs,
            violations: []
        )
    }

    /// Controle d'une reponse complete : version de schema, capacite
    /// attendue, et charge utile coherente avec la capacite.
    public static func check(
        _ response: AICoachResponse,
        expecting capability: AICoachCapability
    ) -> AICoachError? {
        guard response.schemaVersion == AICoachRequest.currentSchemaVersion else {
            return .unsupportedSchema(response.schemaVersion)
        }
        guard response.capability == capability else {
            return .malformedResponse("réponse reçue pour « \(response.capability.displayName) » au lieu de « \(capability.displayName) »")
        }
        if capability.producesDraft, response.program == nil,
           (response.adaptations?.isEmpty ?? true), (response.substitutions?.isEmpty ?? true) {
            return .malformedResponse("aucune proposition exploitable")
        }
        return nil
    }

    /// Filtre de securite applique AVANT de montrer une suggestion.
    ///
    /// Le moteur local a le dernier mot : une progression agressive ou une
    /// valeur impossible est ecartee, quelle que soit la confiance du modele.
    public static func unsafeSuggestions(
        _ suggestions: [AIAdaptationSuggestion],
        currentWeights: [String: Double],
        maximumIncreaseRatio: Double = 0.10
    ) -> [String] {
        var reasons: [String] = []

        for suggestion in suggestions {
            if let sets = suggestion.newSets, !(1...10).contains(sets) {
                reasons.append("Nombre de séries impossible (\(sets)) pour « \(suggestion.exerciseId) ».")
            }
            if let reps = suggestion.newRepsUpper, !(1...100).contains(reps) {
                reasons.append("Nombre de répétitions impossible (\(reps)) pour « \(suggestion.exerciseId) ».")
            }
            guard let proposed = suggestion.newWeightKilograms else { continue }

            if !proposed.isFinite || proposed < 0 || proposed > 500 {
                reasons.append("Charge impossible (\(proposed) kg) pour « \(suggestion.exerciseId) ».")
                continue
            }
            guard let current = currentWeights[suggestion.exerciseId], current > 0 else { continue }
            let increase = (proposed - current) / current
            if increase > maximumIncreaseRatio {
                reasons.append(
                    "Progression trop brutale pour « \(suggestion.exerciseId) » : "
                    + "+\(Int((increase * 100).rounded())) % alors que la limite est de \(Int(maximumIncreaseRatio * 100)) %."
                )
            }
        }

        return reasons
    }

    private static func clamp(_ value: Int, into range: ClosedRange<Int>) -> Int? {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
