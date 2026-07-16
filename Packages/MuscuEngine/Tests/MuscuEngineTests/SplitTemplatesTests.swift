import Testing
@testable import MuscuEngine

@Suite
struct SplitTemplatesTests {
    @Test
    func testRecommendedThreeDaysContainsFullBodyUpperLowerFullAndPPL() {
        let recs = SplitTemplates.recommended(daysPerWeek: 3)
        let prefs = recs.map(\.preference)
        #expect(prefs.contains(.fullBody))
        #expect(prefs.contains(.upperLower))
        #expect(prefs.contains(.ppl))
    }

    @Test
    func testRecommendedFiveDaysContainsPPLULULPPLAndArnold() {
        let recs = SplitTemplates.recommended(daysPerWeek: 5)
        let prefs = recs.map(\.preference)
        #expect(prefs.contains(.pplul))
        #expect(prefs.contains(.ulppl))
        #expect(prefs.contains(.arnold))
    }

    @Test
    func testRecommendedSevenDaysIsEmpty() {
        #expect(SplitTemplates.recommended(daysPerWeek: 7).isEmpty)
    }

    @Test
    func testEveryBlueprintHasExactlyDaysPerWeekSessions() {
        for days in 2...6 {
            let recs = SplitTemplates.recommended(daysPerWeek: days)
            #expect(!recs.isEmpty)
            for rec in recs {
                #expect(rec.sessions.count == days, "\(rec.name) for \(days)j should have \(days) sessions")
            }
        }
    }

    @Test
    func testEveryPushSessionContainsChestCompoundSlot() {
        for days in 2...6 {
            let recs = SplitTemplates.recommended(daysPerWeek: days)
            for rec in recs {
                for session in rec.sessions where session.name == "Push" {
                    let hasChestCompound = session.slots.contains { $0.muscle == "chest" && $0.compound }
                    #expect(hasChestCompound, "Push session in \(rec.name) should have a chest compound slot")
                }
            }
        }
    }

    @Test
    func testBlueprintForKnownPreferenceReturnsSessions() {
        let blueprint = SplitTemplates.blueprint(for: .ppl, daysPerWeek: 3)
        #expect(blueprint != nil)
        #expect(blueprint?.count == 3)
    }

    @Test
    func testBlueprintForUnknownCombinationReturnsNil() {
        #expect(SplitTemplates.blueprint(for: .arnold, daysPerWeek: 2) == nil)
    }
}
