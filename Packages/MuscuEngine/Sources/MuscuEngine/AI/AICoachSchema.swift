import Foundation

/// Ce que le coach IA sait faire. Une capacite absente de cette liste ne peut
/// pas etre demandee : le protocole ne laisse aucune place a une intention
/// devinee depuis du texte libre.
public enum AICoachCapability: String, Codable, CaseIterable, Sendable, Identifiable {
    case generateProgram
    case adaptWeek
    case substituteExercise
    case explain
    case summarizeSession
    case shortenSession

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .generateProgram: return "Créer un programme"
        case .adaptWeek: return "Adapter la semaine"
        case .substituteExercise: return "Proposer un remplacement"
        case .explain: return "Expliquer"
        case .summarizeSession: return "Résumer une séance"
        case .shortenSession: return "Raccourcir une séance"
        }
    }

    /// Une capacite qui ECRIT produit un brouillon a confirmer ; les autres
    /// ne renvoient que du texte.
    public var producesDraft: Bool {
        switch self {
        case .generateProgram, .adaptWeek, .substituteExercise, .shortenSession: return true
        case .explain, .summarizeSession: return false
        }
    }
}

/// Exposition recente d'un exercice, telle qu'envoyee au fournisseur.
/// Volontairement pauvre : identifiant, charge et repetitions, rien d'autre.
public struct AICoachExerciseSummary: Codable, Equatable, Sendable {
    public var exerciseId: String
    public var sets: Int
    public var reps: Int
    public var weightKilograms: Double?

    public init(exerciseId: String, sets: Int, reps: Int, weightKilograms: Double? = nil) {
        self.exerciseId = exerciseId
        self.sets = sets
        self.reps = reps
        self.weightKilograms = weightKilograms
    }
}

/// Contexte envoye au fournisseur.
///
/// Les champs SENSIBLES sont optionnels et valent `nil` par defaut : ils
/// n'existent dans la charge utile que si l'utilisateur a consenti a leur
/// categorie. Un `nil` n'est pas encode : le JSON envoye ne mentionne meme
/// pas la categorie refusee.
public struct AICoachContext: Codable, Equatable, Sendable {
    // Categories non sensibles.
    public var goal: Goal?
    public var experience: Experience?
    public var daysPerWeek: Int?
    public var sessionMinutes: Int?
    public var equipment: TrainingEquipment?
    /// Identifiants d'exercices que le modele a le droit d'utiliser.
    public var allowedExerciseIds: [String]
    public var recentExercises: [AICoachExerciseSummary]

    // Categories sensibles, incluses uniquement sur consentement explicite.
    public var bodyweightKilograms: Double?
    public var measurements: [String: Double]?
    public var readiness: [String: Int]?
    /// Notes libres de l'utilisateur. Contenu NON FIABLE : assaini avant
    /// d'entrer ici.
    public var notes: [String]?

    public init(
        goal: Goal? = nil,
        experience: Experience? = nil,
        daysPerWeek: Int? = nil,
        sessionMinutes: Int? = nil,
        equipment: TrainingEquipment? = nil,
        allowedExerciseIds: [String] = [],
        recentExercises: [AICoachExerciseSummary] = [],
        bodyweightKilograms: Double? = nil,
        measurements: [String: Double]? = nil,
        readiness: [String: Int]? = nil,
        notes: [String]? = nil
    ) {
        self.goal = goal
        self.experience = experience
        self.daysPerWeek = daysPerWeek
        self.sessionMinutes = sessionMinutes
        self.equipment = equipment
        self.allowedExerciseIds = allowedExerciseIds
        self.recentExercises = recentExercises
        self.bodyweightKilograms = bodyweightKilograms
        self.measurements = measurements
        self.readiness = readiness
        self.notes = notes
    }
}

/// Requete versionnee.
public struct AICoachRequest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var capability: AICoachCapability
    /// Langue attendue de la reponse, par exemple `fr-FR`.
    public var locale: String
    /// Demande de l'utilisateur, deja assainie.
    public var userPrompt: String
    public var context: AICoachContext

    public init(
        schemaVersion: Int = AICoachRequest.currentSchemaVersion,
        capability: AICoachCapability,
        locale: String = "fr-FR",
        userPrompt: String,
        context: AICoachContext = AICoachContext()
    ) {
        self.schemaVersion = schemaVersion
        self.capability = capability
        self.locale = locale
        self.userPrompt = userPrompt
        self.context = context
    }
}

// MARK: - Réponse

public struct AIExerciseDraft: Codable, Equatable, Sendable {
    public var exerciseId: String
    public var sets: Int
    public var repsLower: Int
    public var repsUpper: Int
    public var restSeconds: Int
    public var notes: String

    public init(
        exerciseId: String,
        sets: Int,
        repsLower: Int,
        repsUpper: Int,
        restSeconds: Int,
        notes: String = ""
    ) {
        self.exerciseId = exerciseId
        self.sets = sets
        self.repsLower = repsLower
        self.repsUpper = repsUpper
        self.restSeconds = restSeconds
        self.notes = notes
    }
}

public struct AISessionDraft: Codable, Equatable, Sendable {
    public var name: String
    public var exercises: [AIExerciseDraft]

    public init(name: String, exercises: [AIExerciseDraft]) {
        self.name = name
        self.exercises = exercises
    }
}

public struct AIProgramDraft: Codable, Equatable, Sendable {
    public var name: String
    public var notes: String
    public var sessions: [AISessionDraft]

    public init(name: String, notes: String = "", sessions: [AISessionDraft]) {
        self.name = name
        self.notes = notes
        self.sessions = sessions
    }
}

/// Suggestion d'ajustement sur un exercice existant.
public struct AIAdaptationSuggestion: Codable, Equatable, Sendable {
    public var exerciseId: String
    public var newSets: Int?
    public var newRepsUpper: Int?
    public var newWeightKilograms: Double?
    public var reason: String

    public init(
        exerciseId: String,
        newSets: Int? = nil,
        newRepsUpper: Int? = nil,
        newWeightKilograms: Double? = nil,
        reason: String
    ) {
        self.exerciseId = exerciseId
        self.newSets = newSets
        self.newRepsUpper = newRepsUpper
        self.newWeightKilograms = newWeightKilograms
        self.reason = reason
    }
}

public struct AISubstitutionSuggestion: Codable, Equatable, Sendable {
    public var replacedExerciseId: String
    public var replacementExerciseId: String
    public var reason: String

    public init(replacedExerciseId: String, replacementExerciseId: String, reason: String) {
        self.replacedExerciseId = replacedExerciseId
        self.replacementExerciseId = replacementExerciseId
        self.reason = reason
    }
}

/// Reponse versionnee.
///
/// On conserve le schema, le modele et l'explication DESTINEE A L'UTILISATEUR.
/// Jamais le raisonnement interne du modele : ce n'est pas une donnee utile,
/// et le stocker reviendrait a garder des contenus qu'on ne maitrise pas.
public struct AICoachResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var capability: AICoachCapability
    public var modelIdentifier: String
    public var explanation: String
    public var program: AIProgramDraft?
    public var adaptations: [AIAdaptationSuggestion]?
    public var substitutions: [AISubstitutionSuggestion]?

    public init(
        schemaVersion: Int = AICoachRequest.currentSchemaVersion,
        capability: AICoachCapability,
        modelIdentifier: String,
        explanation: String,
        program: AIProgramDraft? = nil,
        adaptations: [AIAdaptationSuggestion]? = nil,
        substitutions: [AISubstitutionSuggestion]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.capability = capability
        self.modelIdentifier = modelIdentifier
        self.explanation = explanation
        self.program = program
        self.adaptations = adaptations
        self.substitutions = substitutions
    }
}

/// Erreurs du coach, toutes destinees a etre AFFICHEES : une IA indisponible
/// doit le dire et renvoyer vers le generateur local.
public enum AICoachError: Error, Equatable, Sendable {
    case notConfigured
    case consentMissing(String)
    case budgetExceeded(limit: Int)
    case cancelled
    case timedOut(seconds: Int)
    case transport(String)
    case unsupportedSchema(Int)
    case malformedResponse(String)
    case rejected([String])

    public var userMessage: String {
        switch self {
        case .notConfigured:
            return "Le coach IA n’est pas configuré. Le générateur local reste disponible et fonctionne hors ligne."
        case .consentMissing(let category):
            return "Cette demande nécessite votre accord pour partager : \(category)."
        case .budgetExceeded(let limit):
            return "Limite mensuelle atteinte (\(limit) demandes). Le générateur local reste disponible."
        case .cancelled:
            return "Demande annulée."
        case .timedOut(let seconds):
            return "Aucune réponse après \(seconds) s. Réessayez, ou utilisez le générateur local."
        case .transport(let detail):
            return "Le service n’a pas répondu correctement : \(detail)"
        case .unsupportedSchema(let version):
            return "Réponse dans un format non pris en charge (version \(version))."
        case .malformedResponse(let detail):
            return "Réponse illisible : \(detail)"
        case .rejected(let reasons):
            return "Proposition écartée : " + reasons.joined(separator: " ")
        }
    }

    /// Une erreur RECUPERABLE justifie une nouvelle tentative ; les autres
    /// demandent une action de l'utilisateur.
    public var isRetryable: Bool {
        switch self {
        case .timedOut, .transport: return true
        case .notConfigured, .consentMissing, .budgetExceeded, .cancelled,
             .unsupportedSchema, .malformedResponse, .rejected: return false
        }
    }
}
