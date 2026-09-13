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
}
