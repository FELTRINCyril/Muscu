import Testing
@testable import MuscuEngine

@Suite
struct ExerciseClassificationTests {
    @Test
    func testBodyweightEquipment() {
        #expect(ExerciseClassification.loadKind(equipment: "body only") == .bodyweight)
    }

    @Test
    func testAssistedEquipment() {
        #expect(ExerciseClassification.loadKind(equipment: "bands") == .assisted)
    }

    @Test(arguments: ["barbell", "dumbbell", "machine", "cable", "kettlebells"])
    func testExternalEquipment(equipment: String) {
        #expect(ExerciseClassification.loadKind(equipment: equipment) == .external)
    }

    // Un materiel inconnu ne doit jamais etre suppose porte : `unknown` est
    // la seule reponse honnete, et elle n'autorise aucun record de charge.
    @Test
    func testMissingEquipmentIsUnknown() {
        #expect(ExerciseClassification.loadKind(equipment: nil) == .unknown)
        #expect(ExerciseClassification.loadKind(equipment: "") == .unknown)
        #expect(LoadKind.unknown.allowsLoadRecord == false)
    }

    @Test
    func testBodyweightBecomesWeightedOnceLoaded() {
        #expect(ExerciseClassification.resolvedLoadKind(base: .bodyweight, enteredWeight: 0) == .bodyweight)
        #expect(ExerciseClassification.resolvedLoadKind(base: .bodyweight, enteredWeight: 20) == .weighted)
        #expect(ExerciseClassification.resolvedLoadKind(base: .external, enteredWeight: 20) == .external)
        #expect(ExerciseClassification.resolvedLoadKind(base: .assisted, enteredWeight: 20) == .assisted)
    }
}
