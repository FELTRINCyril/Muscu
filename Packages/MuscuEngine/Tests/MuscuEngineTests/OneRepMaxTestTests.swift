import Foundation
import Testing
@testable import MuscuEngine

@Suite("Protocole de test de 1RM")
struct OneRepMaxTestTests {
    @Test("Sans référence, aucun protocole n'est inventé")
    func withoutReferenceNothingIsProposed() {
        #expect(OneRepMaxTest.protocolSteps(referenceOneRepMax: nil).isEmpty)
        #expect(OneRepMaxTest.protocolSteps(referenceOneRepMax: 0).isEmpty)
    }

    @Test("Une référence trop faible ne justifie pas un test maximal")
    func lowReferenceIsRefused() {
        #expect(OneRepMaxTest.protocolSteps(referenceOneRepMax: 25).isEmpty)
        #expect(!OneRepMaxTest.protocolSteps(referenceOneRepMax: 30).isEmpty)
    }

    @Test("Le protocole monte en charge puis propose des tentatives à une répétition")
    func protocolRampsThenAttempts() {
        let steps = OneRepMaxTest.protocolSteps(referenceOneRepMax: 100)

        let warmups = steps.filter { $0.kind == .warmup }
        let attempts = steps.filter { $0.kind == .attempt }

        #expect(warmups.count == 3)
        #expect(attempts.count == OneRepMaxTest.maximumAttempts)
        #expect(attempts.allSatisfy { $0.reps == 1 })
        #expect(warmups.allSatisfy { $0.reps > 1 })
        // La montée précède toujours les tentatives.
        #expect(steps.prefix(3).allSatisfy { $0.kind == .warmup })
    }

    @Test("Les charges sont alignées sur l'incrément disponible")
    func weightsFollowTheIncrement() {
        let steps = OneRepMaxTest.protocolSteps(referenceOneRepMax: 100, increment: 2.5)
        #expect(steps.allSatisfy { ($0.weightKilograms / 2.5).rounded() * 2.5 == $0.weightKilograms })
    }

    @Test("Chaque tentative pèse strictement plus que la précédente")
    func attemptsStrictlyIncrease() {
        // Avec un increment grossier, deux fractions voisines s'arrondiraient
        // sur la meme charge : le protocole doit l'empecher.
        let steps = OneRepMaxTest.protocolSteps(referenceOneRepMax: 40, increment: 5)
        let attempts = steps.filter { $0.kind == .attempt }.map(\.weightKilograms)

        #expect(attempts.count == OneRepMaxTest.maximumAttempts)
        for (previous, next) in zip(attempts, attempts.dropFirst()) {
            #expect(next > previous)
        }
    }

    @Test("Le repos entre tentatives est plus long qu'à l'échauffement")
    func attemptsRestLonger() {
        let steps = OneRepMaxTest.protocolSteps(referenceOneRepMax: 100)
        let warmupRest = steps.filter { $0.kind == .warmup }.map(\.restSeconds).max() ?? 0
        let attemptRest = steps.filter { $0.kind == .attempt }.map(\.restSeconds).min() ?? 0
        #expect(attemptRest > warmupRest)
    }

    @Test("Le résultat est la meilleure tentative validée")
    func resultIsTheBestValidatedAttempt() {
        #expect(OneRepMaxTest.result(validatedWeights: [95, 100]) == 100)
        #expect(OneRepMaxTest.result(validatedWeights: []) == nil)
        #expect(OneRepMaxTest.result(validatedWeights: [0]) == nil)
    }

    @Test("L'avertissement de sécurité est explicite et non vide")
    func safetyWarningIsPresent() {
        #expect(OneRepMaxTest.safetyWarning.contains("pareur"))
        #expect(OneRepMaxTest.safetyWarning.contains("facultatif"))
        #expect(OneRepMaxTest.safetyWarning.contains("douleur"))
    }

    @Test("Le protocole est déterministe")
    func protocolIsDeterministic() {
        #expect(
            OneRepMaxTest.protocolSteps(referenceOneRepMax: 120)
                == OneRepMaxTest.protocolSteps(referenceOneRepMax: 120)
        )
    }
}
