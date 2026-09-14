import Foundation
import SwiftData
import MuscuEngine

/// Résultat d'une demande au coach, prêt à être affiché.
struct AICoachOutcome: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case model(String)
        /// Repli déterministe : le générateur local a produit la proposition.
        case localFallback(reason: String)
    }

    var source: Source
    var explanation: String
    var draft: AIProgramDraft?
    /// Corrections appliquées à la proposition du modèle, listées telles
    /// quelles : une réparation muette serait indiscernable d'une réponse
    /// correcte.
    var repairs: [String]
    /// Contraintes qui n'ont PAS pu être respectées.
    var violations: [String]

    var isFromModel: Bool {
        if case .model = source { return true }
        return false
    }
}

/// Orchestration d'une demande au coach IA.
///
/// Chaîne imposée par la roadmap, dans cet ordre : consentement, budget,
/// assainissement, envoi, contrôle du schéma, validation locale, filtre de
/// sécurité, puis repli déterministe. Aucune étape n'est optionnelle.
@MainActor
enum AICoachCoordinator {
    static let defaultTimeoutSeconds = 45

    /// Contexte construit à partir du store, **filtré par le consentement**.
    /// Une catégorie refusée n'est pas mise à `nil` après coup : elle n'est
    /// jamais lue.
    static func makeContext(
        capability: AICoachCapability,
        consent: AIConsent,
        catalog: ExerciseCatalog?,
        in context: ModelContext
    ) -> AICoachContext {
        var result = AICoachContext()
        result.allowedExerciseIds = (catalog?.all.map(\.id) ?? []).sorted()

        if consent.allows(.trainingProfile), let profile = ProfileStore.currentProfile(in: context) {
            result.goal = profile.primaryGoal
            result.experience = profile.experience
            result.daysPerWeek = profile.availableWeekdays.count > 0 ? profile.availableWeekdays.count : nil
            result.sessionMinutes = profile.sessionMinutesMaximum
            result.equipment = profile.equipment
        }

        if consent.allows(.recentPerformance) {
            result.recentExercises = recentExercises(in: context)
        }

        if consent.allows(.bodyMeasurements) {
            result.bodyweightKilograms = ProfileStore.latestBodyweightKilograms(in: context)
        }

        if consent.allows(.readinessCheckIns), let readiness = latestReadiness(in: context) {
            result.readiness = readiness
        }

        if consent.allows(.personalNotes) {
            // Contenu NON FIABLE : nettoyé avant d'entrer dans la charge utile.
            let notes = recentNotes(in: context).map { PromptSanitizer.clean($0) }.filter { !$0.isEmpty }
            result.notes = notes.isEmpty ? nil : notes
        }

        return result
    }

    /// Envoie une demande et renvoie une proposition utilisable, ou explique
    /// pourquoi elle ne l'est pas.
    static func perform(
        capability: AICoachCapability,
        prompt: String,
        service: AICoachService?,
        consent: AIConsent,
        budget: AIBudget,
        usage: AIUsage,
        catalog: ExerciseCatalog?,
        localFallback: (() -> AIProgramDraft?)? = nil,
        in context: ModelContext,
        now: Date = .now,
        timeoutSeconds: Int = defaultTimeoutSeconds
    ) async -> Result<AICoachOutcome, AICoachError> {
        let missing = consent.missingCategories(for: capability)
        if let first = missing.first {
            return .failure(.consentMissing(first.displayName))
        }
        if let error = AIBudgetGuard.check(usage: usage, budget: budget, now: now) {
            return .failure(error)
        }
        guard let service, service.isConfigured else {
            return fallback(reason: AICoachError.notConfigured.userMessage, localFallback: localFallback, now: now)
        }

        let request = AICoachRequest(
            capability: capability,
            userPrompt: PromptSanitizer.userPrompt(prompt),
            context: makeContext(capability: capability, consent: consent, catalog: catalog, in: context)
        )

        let started = Date()
        do {
            let response = try await service.send(request, timeoutSeconds: timeoutSeconds)
            if let error = AIResponseValidator.check(response, expecting: capability) { throw error }

            guard let program = response.program else {
                record(capability, model: response.modelIdentifier, outcome: .accepted, since: started, repairs: 0, violations: 0, message: "réponse textuelle")
                return .success(AICoachOutcome(
                    source: .model(response.modelIdentifier),
                    explanation: response.explanation,
                    draft: nil,
                    repairs: [],
                    violations: []
                ))
            }

            let validation = AIResponseValidator.validate(
                program,
                allowedExerciseIds: Set(request.context.allowedExerciseIds)
            )

            guard let draft = validation.draft else {
                record(capability, model: response.modelIdentifier, outcome: .rejected, since: started, repairs: validation.repairs.count, violations: validation.violations.count, message: "proposition rejetée")
                // Une sortie invalide n'atteint jamais le store : on bascule
                // sur le générateur local plutôt que de ne rien rendre.
                return fallback(
                    reason: AICoachError.rejected(validation.violations).userMessage,
                    localFallback: localFallback,
                    now: now
                )
            }

            record(
                capability,
                model: response.modelIdentifier,
                outcome: validation.repairs.isEmpty ? .accepted : .repaired,
                since: started,
                repairs: validation.repairs.count,
                violations: 0,
                message: validation.repairs.isEmpty ? "acceptée" : "acceptée après correction"
            )

            return .success(AICoachOutcome(
                source: .model(response.modelIdentifier),
                explanation: response.explanation,
                draft: draft,
                repairs: validation.repairs,
                violations: []
            ))
        } catch let error as AICoachError {
            record(capability, model: service.identifier, outcome: .failed, since: started, repairs: 0, violations: 0, message: error.userMessage)
            // Une erreur réseau ne doit pas laisser l'utilisateur sans rien :
            // le générateur local fonctionne hors ligne.
            return fallback(reason: error.userMessage, localFallback: localFallback, now: now)
        } catch is CancellationError {
            record(capability, model: service.identifier, outcome: .failed, since: started, repairs: 0, violations: 0, message: "annulée")
            return .failure(.cancelled)
        } catch {
            record(capability, model: service.identifier, outcome: .failed, since: started, repairs: 0, violations: 0, message: error.localizedDescription)
            return fallback(reason: AICoachError.transport(error.localizedDescription).userMessage, localFallback: localFallback, now: now)
        }
    }

    // MARK: - Repli

    private static func fallback(
        reason: String,
        localFallback: (() -> AIProgramDraft?)?,
        now: Date
    ) -> Result<AICoachOutcome, AICoachError> {
        guard let draft = localFallback?() else {
            return .failure(.transport(reason))
        }
        AICoachLog.record(AICoachLogEntry(
            date: now,
            capabilityRaw: AICoachCapability.generateProgram.rawValue,
            modelIdentifier: "générateur local",
            outcome: .fallback,
            durationMilliseconds: 0,
            repairCount: 0,
            violationCount: 0,
            message: "repli local"
        ))
        return .success(AICoachOutcome(
            source: .localFallback(reason: reason),
            explanation: "Proposition produite par le générateur local, hors ligne et déterministe.",
            draft: draft,
            repairs: [],
            violations: []
        ))
    }

    private static func record(
        _ capability: AICoachCapability,
        model: String,
        outcome: AICoachLogEntry.Outcome,
        since started: Date,
        repairs: Int,
        violations: Int,
        message: String
    ) {
        AICoachLog.record(AICoachLogEntry(
            date: .now,
            capabilityRaw: capability.rawValue,
            modelIdentifier: model,
            outcome: outcome,
            durationMilliseconds: Int(Date().timeIntervalSince(started) * 1_000),
            repairCount: repairs,
            violationCount: violations,
            message: message
        ))
    }

    // MARK: - Lecture du store

    private static func recentExercises(in context: ModelContext, limit: Int = 30) -> [AICoachExerciseSummary] {
        var descriptor = FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 10
        let sessions = ((try? context.fetch(descriptor)) ?? []).filter { $0.deletedAt == nil }

        var summaries: [AICoachExerciseSummary] = []
        for session in sessions {
            for set in session.workingSets where summaries.count < limit {
                summaries.append(AICoachExerciseSummary(
                    exerciseId: set.exerciseId,
                    sets: 1,
                    reps: set.reps,
                    weightKilograms: set.weight > 0 ? set.weight : nil
                ))
            }
        }
        return summaries
    }

    private static func latestReadiness(in context: ModelContext) -> [String: Int]? {
        var descriptor = FetchDescriptor<ReadinessEntry>(sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let entry = (try? context.fetch(descriptor))?.first else { return nil }

        var values: [String: Int] = [:]
        if let energy = entry.energy { values["energie"] = energy }
        if let sleep = entry.sleepQuality { values["sommeil"] = sleep }
        if let soreness = entry.soreness { values["courbatures"] = soreness }
        if let stress = entry.stress { values["stress"] = stress }
        return values.isEmpty ? nil : values
    }

    private static func recentNotes(in context: ModelContext, limit: Int = 5) -> [String] {
        var descriptor = FetchDescriptor<CompletedSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 10
        let sessions = ((try? context.fetch(descriptor)) ?? []).filter { $0.deletedAt == nil }
        return sessions.compactMap { $0.notes.isEmpty ? nil : $0.notes }.prefix(limit).map { $0 }
    }
}

extension AIProgramDraft {
    /// Convertit la proposition en brouillon du générateur, pour réutiliser
    /// l'écran d'aperçu et d'enregistrement déjà en place.
    ///
    /// Le nom affiché vient du CATALOGUE, jamais du modèle : c'est le
    /// catalogue qui fait autorité sur ce qu'est un exercice.
    func toDraftProgram(catalog: ExerciseCatalog?) -> DraftProgram {
        DraftProgram(
            name: name,
            notes: notes,
            sessions: sessions.map { session in
                DraftSession(
                    name: session.name,
                    warmupEnabled: true,
                    exercises: session.exercises.map { exercise in
                        DraftExercise(
                            exerciseId: exercise.exerciseId,
                            displayName: catalog?.exercise(id: exercise.exerciseId)?.nameFr ?? exercise.exerciseId,
                            sets: exercise.sets,
                            repsLower: exercise.repsLower,
                            repsUpper: exercise.repsUpper,
                            restSeconds: exercise.restSeconds
                        )
                    }
                )
            }
        )
    }
}
