import Foundation
import SwiftData
import MuscuEngine

/// Modifications du programme demandees depuis l'execution d'une seance.
///
/// Isole ici, et non dans la vue, pour que la regle « le programme n'est
/// modifie qu'apres confirmation » soit verifiable par un test plutot que
/// seulement visible a l'ecran.
@MainActor
enum ProgramEditing {
    /// Applique durablement une substitution a la prescription du programme.
    ///
    /// Ne touche JAMAIS l'historique deja enregistre : les series realisees
    /// conservent l'exercice prevu au moment ou elles ont ete faites.
    @discardableResult
    static func applySubstitution(
        prescriptionId: UUID,
        exerciseId: String,
        displayName: String,
        in context: ModelContext,
        now: Date = .now
    ) -> Bool {
        guard let exercises = try? context.fetch(FetchDescriptor<PrescribedExercise>()),
              let prescription = exercises.first(where: { $0.id == prescriptionId }) else { return false }

        prescription.exerciseId = exerciseId
        prescription.displayName = displayName
        prescription.touch(now: now)
        return PersistenceSupport.save(context, action: "Remplacement dans le programme")
    }

    // MARK: - Structure apres une seance modifiee

    /// Nombre de series a prescrire : l'ecart realise en seance s'ajoute a
    /// la prescription. Comparer a la prescription brute serait faux pour
    /// une seance allegee (decharge, check-in) : ses series etaient deja
    /// reduites au demarrage, ce n'est pas l'utilisateur qui les a retirees.
    static func adjustedCount(prescribed: Int, baseline: Int?, final: Int?) -> Int {
        guard let baseline, let final else { return prescribed }
        return max(1, prescribed + (final - baseline))
    }

    /// Reporte dans la seance du programme la STRUCTURE de la seance faite :
    /// exercices ajoutes, retires, remplaces et ordre, nombre de series,
    /// mesure. Les charges et repetitions ne sont jamais touchees, ni
    /// prescrites ni realisees. Une seule sauvegarde, apres confirmation de
    /// l'utilisateur (`WorkoutSummaryView`).
    @discardableResult
    static func applyStructure(
        of plan: WorkoutPlan,
        baseline: [SessionStructureEntry],
        to session: ProgramSession,
        in context: ModelContext,
        now: Date = .now
    ) -> Bool {
        let baselineByID = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let finalEntries = SessionStructureDiff.entries(of: plan)
        let finalByID = Dictionary(finalEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let prescriptions = Dictionary(session.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = Dictionary(session.groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Retires : presents au depart, absents a la fin.
        for entry in baseline where finalByID[entry.id] == nil {
            guard let prescription = prescriptions[entry.id] else { continue }
            session.exercises.removeAll { $0.id == prescription.id }
            context.delete(prescription)
        }

        var order = 0
        for (nodeIndex, node) in plan.nodes.enumerated() {
            if node.isGroup, let group = groups[node.id] {
                group.orderIndex = nodeIndex
                let baselineRounds = node.exercises.compactMap { baselineByID[$0.id]?.setCount }.first
                group.rounds = adjustedCount(prescribed: group.rounds, baseline: baselineRounds, final: node.rounds)
                group.updatedAt = now
            }
            for (memberIndex, exercise) in node.exercises.enumerated() {
                defer { order += 1 }
                let entry = finalByID[exercise.id]
                if let prescription = prescriptions[exercise.id] {
                    update(prescription, from: exercise, entry: entry, baseline: baselineByID[exercise.id], isGroupMember: node.isGroup)
                    prescription.orderIndex = order
                    prescription.groupOrderIndex = node.isGroup ? memberIndex : 0
                    prescription.updatedAt = now
                } else if !node.isGroup {
                    let prescription = PrescribedExercise(
                        exerciseId: exercise.exerciseId,
                        displayName: exercise.displayName,
                        orderIndex: order,
                        formatRaw: SetFormat.classic.rawValue,
                        sets: max(1, exercise.setCount),
                        repsLower: exercise.repsLower,
                        repsUpper: exercise.repsUpper,
                        restSeconds: exercise.restSeconds
                    )
                    prescription.measure = exercise.effectiveMeasure
                    if let duration = exercise.targetDurationSeconds, duration > 0 { prescription.targetDurationSeconds = duration }
                    if let distance = exercise.targetDistanceMeters, distance > 0 { prescription.targetDistanceMeters = distance }
                    prescription.session = session
                    session.exercises.append(prescription)
                    context.insert(prescription)
                }
            }
        }

        session.touch(now: now)
        return PersistenceSupport.save(context, action: "Mise à jour de la séance du programme")
    }

    private static func update(
        _ prescription: PrescribedExercise,
        from exercise: WorkoutExercisePlan,
        entry: SessionStructureEntry?,
        baseline: SessionStructureEntry?,
        isGroupMember: Bool
    ) {
        if prescription.exerciseId != exercise.exerciseId {
            prescription.exerciseId = exercise.exerciseId
            prescription.displayName = exercise.displayName
            // Le type de charge prescrit decrivait l'ancien exercice.
            prescription.loadKindRaw = ""
        }
        if !isGroupMember {
            prescription.sets = adjustedCount(prescribed: prescription.sets, baseline: baseline?.setCount, final: entry?.setCount)
        }
        if let entry, let baseline, entry.measure != baseline.measure, prescription.format == .classic {
            prescription.measure = entry.measure
            if let duration = exercise.targetDurationSeconds, duration > 0, entry.measure.measuresDuration {
                prescription.targetDurationSeconds = duration
            }
            if let distance = exercise.targetDistanceMeters, distance > 0, entry.measure.measuresDistance {
                prescription.targetDistanceMeters = distance
            }
        }
    }
}
