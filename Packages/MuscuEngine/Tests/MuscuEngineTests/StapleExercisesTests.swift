import Testing
@testable import MuscuEngine

struct StapleExercisesTests {
    @Test func allCatalogIdsExistInCatalog() throws {
        let catalog = try ExerciseCatalog.load()
        let knownIds = Set(catalog.all.map(\.id))
        for staple in StapleExercises.all {
            #expect(knownIds.contains(staple.catalogId), "id inconnu du catalogue: \(staple.catalogId)")
        }
    }

    @Test func noDuplicateCatalogIds() {
        let ids = StapleExercises.all.map(\.catalogId)
        #expect(ids.count == Set(ids).count)
    }

    @Test func ranksAreUniqueAndContiguousWithinEachGroup() {
        for group in MovementGroup.allCases {
            let ranks = StapleExercises.members(of: group).map(\.rank)
            #expect(ranks == Array(1...ranks.count), "rangs invalides pour \(group)")
        }
    }

    @Test func lookupByIdWorks() {
        let staple = StapleExercises.staple(for: "Barbell_Bench_Press_-_Medium_Grip")
        #expect(staple?.group == .chestPressHorizontal)
        #expect(staple?.rank == 1)
        #expect(StapleExercises.staple(for: "Alternating_Floor_Press") == nil)
    }

    @Test func membersAreSortedByRank() {
        let members = StapleExercises.members(of: .squat)
        #expect(members.first?.catalogId == "Barbell_Squat")
        #expect(members.map(\.rank) == members.map(\.rank).sorted())
    }
}
