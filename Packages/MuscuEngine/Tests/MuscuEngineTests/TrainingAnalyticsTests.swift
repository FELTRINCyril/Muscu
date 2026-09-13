import Foundation
import Testing
@testable import MuscuEngine

@Suite
struct TrainingAnalyticsTests {
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private var calendar: Calendar { TrainingAnalytics.calendar(timeZone: paris) }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private func set(
        _ exerciseId: String = "bench",
        weight: Double = 60,
        reps: Int = 10,
        loadKind: LoadKind = .external,
        muscles: [String] = ["chest"],
        effort: EffortRating? = nil,
        failure: Bool = false,
        warmup: Bool = false,
        bodyweight: Double? = nil
    ) -> AnalyticsSet {
        AnalyticsSet(
            exerciseId: exerciseId,
            displayName: exerciseId,
            metrics: SetMetricsInput(
                weightKilograms: weight,
                reps: reps,
                loadKind: loadKind,
                isWarmup: warmup,
                bodyweightKilograms: bodyweight
            ),
            primaryMuscles: muscles,
            effort: effort,
            reachedFailure: failure
        )
    }

    private func session(_ iso: String, duration: Int = 3_600, sets: [AnalyticsSet]) -> AnalyticsSession {
        AnalyticsSession(date: date(iso), durationSeconds: duration, sets: sets)
    }

    // MARK: - Semaines

    @Test
    func testWeeklySummaryAggregatesWorkingSetsOnly() {
        let summaries = TrainingAnalytics.weeklySummaries(
            sessions: [session("2026-01-07T18:00:00Z", sets: [set(), set(), set(warmup: true)])],
            calendar: calendar
        )
        #expect(summaries.count == 1)
        #expect(summaries[0].workingSetCount == 2)
        #expect(summaries[0].totalReps == 20)
        #expect(summaries[0].tonnage.value == 1_200)
        #expect(summaries[0].tonnage.isComplete)
    }

    // La semaine commence le lundi : deux séances de part et d'autre d'un
    // dimanche appartiennent à deux semaines différentes.
    @Test
    func testWeeksStartOnMonday() {
        let summaries = TrainingAnalytics.weeklySummaries(
            sessions: [
                session("2026-01-11T18:00:00Z", sets: [set()]), // dimanche
                session("2026-01-12T18:00:00Z", sets: [set()]), // lundi
            ],
            calendar: calendar
        )
        #expect(summaries.count == 2)
    }

    // Le passage à l'heure d'été ne doit ni perdre ni dupliquer une semaine.
    @Test
    func testDaylightSavingChangeKeepsWeeksContiguous() {
        // En France, l'heure d'été 2026 commence le 29 mars.
        let sessions = [
            session("2026-03-23T10:00:00Z", sets: [set()]),
            session("2026-03-30T10:00:00Z", sets: [set()]),
            session("2026-04-06T10:00:00Z", sets: [set()]),
        ]
        let weeks = TrainingAnalytics.weeklySummaries(sessions: sessions, calendar: calendar)
        #expect(weeks.count == 3)
        #expect(TrainingAnalytics.filled(weeks: weeks, calendar: calendar).count == 3)
    }

    @Test
    func testEmptyWeeksAreFilledWithoutInventingSessions() {
        let sessions = [
            session("2026-01-05T10:00:00Z", sets: [set()]),
            session("2026-01-26T10:00:00Z", sets: [set()]),
        ]
        let filled = TrainingAnalytics.filled(
            weeks: TrainingAnalytics.weeklySummaries(sessions: sessions, calendar: calendar),
            calendar: calendar
        )
        #expect(filled.count == 4)
        #expect(filled.filter { $0.sessionCount == 0 }.count == 2)
        #expect(filled.allSatisfy { $0.sessionCount == 0 ? $0.tonnage.value == 0 : true })
    }

    /// Un fuseau différent peut faire basculer une séance de nuit dans une
    /// autre semaine : l'agrégation doit suivre le calendrier fourni.
    @Test
    func testAggregationFollowsTheProvidedTimeZone() {
        let lateSunday = session("2026-01-11T23:30:00Z", sets: [set()])
        let parisWeeks = TrainingAnalytics.weeklySummaries(sessions: [lateSunday], calendar: calendar)
        let tokyo = TrainingAnalytics.calendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let tokyoWeeks = TrainingAnalytics.weeklySummaries(sessions: [lateSunday], calendar: tokyo)
        // 23h30 UTC dimanche = lundi 8h30 à Tokyo : semaine suivante.
        #expect(parisWeeks[0].weekStart != tokyoWeeks[0].weekStart)
    }

    // MARK: - Données manquantes

    /// Un tonnage de 0 avec des séries inconnues ne veut pas dire « aucun
    /// travail » : il faut pouvoir distinguer les deux.
    @Test
    func testUnknownBodyweightIsCountedSeparatelyNotAsZero() {
        let summaries = TrainingAnalytics.weeklySummaries(
            sessions: [session("2026-01-07T18:00:00Z", sets: [set(weight: 0, reps: 20, loadKind: .bodyweight)])],
            calendar: calendar
        )
        #expect(summaries[0].tonnage.value == 0)
        #expect(summaries[0].tonnage.unknownSets == 1)
        #expect(summaries[0].tonnage.isComplete == false)
        #expect(summaries[0].workDensity == nil, "La densité n'a pas de sens sur un tonnage incomplet")
    }

    @Test
    func testWorkDensityNeedsBothDurationAndCompleteTonnage() {
        let complete = TrainingAnalytics.weeklySummaries(
            sessions: [session("2026-01-07T18:00:00Z", duration: 3_600, sets: [set()])],
            calendar: calendar
        )
        // 600 kg de tonnage sur 60 minutes = 10 kg par minute.
        #expect(complete[0].workDensity == 10)

        let noDuration = TrainingAnalytics.weeklySummaries(
            sessions: [session("2026-01-07T18:00:00Z", duration: 0, sets: [set()])],
            calendar: calendar
        )
        #expect(noDuration[0].workDensity == nil)
    }

    // MARK: - Séries difficiles

    /// Une série sans effort saisi n'est jamais supposée difficile : ce
    /// serait confondre « pas de donnée » et « facile ».
    @Test
    func testHardSetsRequireAnExplicitSignal() {
        let summaries = TrainingAnalytics.weeklySummaries(
            sessions: [
                session("2026-01-07T18:00:00Z", sets: [
                    set(effort: .rir(1)),
                    set(effort: .rir(4)),
                    set(failure: true),
                    set(),
                ])
            ],
            calendar: calendar
        )
        #expect(summaries[0].hardSetCount == 2)
        #expect(summaries[0].setsWithoutDeclaredEffort == 1)
        #expect(summaries[0].hardSetsByMuscle["chest"] == 2)
    }

    @Test
    func testSetsAreCountedPerPrimaryMuscle() {
        let summaries = TrainingAnalytics.weeklySummaries(
            sessions: [
                session("2026-01-07T18:00:00Z", sets: [
                    set(muscles: ["chest", "triceps"]),
                    set(muscles: ["chest"]),
                    set(muscles: []),
                ])
            ],
            calendar: calendar
        )
        #expect(summaries[0].setsByMuscle["chest"] == 2)
        #expect(summaries[0].setsByMuscle["triceps"] == 1)
        #expect(summaries[0].workingSetCount == 3, "Une série sans muscle connu compte quand même dans le total")
    }

    // MARK: - Séries par exercice

    @Test
    func testSeriesSkipsSessionsWithoutAnExploitableValue() {
        let sessions = [
            session("2026-01-05T10:00:00Z", sets: [set(weight: 100, reps: 5)]),
            session("2026-01-07T10:00:00Z", sets: [set(weight: 0, reps: 20, loadKind: .bodyweight)]),
            session("2026-01-09T10:00:00Z", sets: [set(weight: 105, reps: 5)]),
        ]
        let points = TrainingAnalytics.series(metric: .estimatedOneRepMax, exerciseId: "bench", sessions: sessions)
        #expect(points.count == 2, "Une séance sans charge exploitable ne doit pas apparaître comme un zéro")
        #expect(points[0].date < points[1].date)
    }

    @Test
    func testAvailableMetricsDependOnTheData() {
        let bodyweightOnly = [session("2026-01-05T10:00:00Z", sets: [set(weight: 0, reps: 20, loadKind: .bodyweight)])]
        let metrics = TrainingAnalytics.availableMetrics(exerciseId: "bench", sessions: bodyweightOnly)
        #expect(metrics.contains(.maxReps))
        #expect(metrics.contains(.estimatedOneRepMax) == false)
        #expect(metrics.contains(.maxLoad) == false)
    }

    /// Une traction assistée ne doit jamais alimenter une courbe de charge.
    @Test
    func testAssistedWorkNeverFeedsALoadSeries() {
        let sessions = [
            session("2026-01-05T10:00:00Z", sets: [
                set("pullup", weight: 30, reps: 8, loadKind: .assisted, bodyweight: 80)
            ])
        ]
        #expect(TrainingAnalytics.series(metric: .maxLoad, exerciseId: "pullup", sessions: sessions).isEmpty)
        #expect(TrainingAnalytics.series(metric: .estimatedOneRepMax, exerciseId: "pullup", sessions: sessions).isEmpty)
        #expect(TrainingAnalytics.series(metric: .maxReps, exerciseId: "pullup", sessions: sessions).count == 1)
    }

    @Test
    func testEveryMetricDocumentsItsFormulaAndUnit() {
        for metric in ExerciseMetric.allCases {
            #expect(metric.formulaDescription.isEmpty == false)
        }
        #expect(ExerciseMetric.estimatedOneRepMax.formulaDescription.contains("estimé"))
        #expect(ExerciseMetric.maxReps.unitSymbol.isEmpty)
    }

    // MARK: - Fréquence

    @Test
    func testStreakCountsConsecutiveWeeks() {
        let sessions = [
            session("2026-01-05T10:00:00Z", sets: [set()]),
            session("2026-01-12T10:00:00Z", sets: [set()]),
            session("2026-01-19T10:00:00Z", sets: [set()]),
        ]
        let now = date("2026-01-21T10:00:00Z")
        #expect(TrainingAnalytics.currentWeeklyStreak(sessions: sessions, now: now, calendar: calendar) == 3)
    }

    /// La semaine en cours, encore vide, ne casse pas une série : elle n'est
    /// pas terminée.
    @Test
    func testEmptyCurrentWeekDoesNotBreakTheStreak() {
        let sessions = [
            session("2026-01-05T10:00:00Z", sets: [set()]),
            session("2026-01-12T10:00:00Z", sets: [set()]),
        ]
        let now = date("2026-01-20T10:00:00Z")
        #expect(TrainingAnalytics.currentWeeklyStreak(sessions: sessions, now: now, calendar: calendar) == 2)
    }

    @Test
    func testStreakIsZeroWithoutSessions() {
        #expect(TrainingAnalytics.currentWeeklyStreak(sessions: [], now: date("2026-01-20T10:00:00Z"), calendar: calendar) == 0)
    }

    /// Sans séance planifiée, l'adhérence n'est pas 0 % : elle n'existe pas.
    @Test
    func testAdherenceIsUndefinedWithoutAPlan() {
        #expect(TrainingAnalytics.adherence(plannedCount: 0, completedCount: 0).ratio == nil)
        #expect(TrainingAnalytics.adherence(plannedCount: 4, completedCount: 3).ratio == 0.75)
    }

    // MARK: - Déséquilibres

    @Test
    func testUnderworkedMusclesAreReportedWithTheirGap() {
        let findings = TrainingAnalytics.imbalances(
            weeklySetsByMuscle: ["chest": 12, "lats": 12, "quadriceps": 10, "hamstrings": 2]
        )
        #expect(findings.map(\.muscle) == ["hamstrings"])
        #expect(findings[0].relativeGap < 0)
        #expect(findings[0].medianWeeklySets > 0)
    }

    @Test
    func testNoImbalanceReportedOnTooFewMuscles() {
        #expect(TrainingAnalytics.imbalances(weeklySetsByMuscle: ["chest": 12, "lats": 1]).isEmpty)
    }

    // MARK: - Comparaison

    @Test
    func testComparisonStatesFactsWithoutCausality() {
        let previous = WeeklySummary(weekStart: date("2026-01-05T00:00:00Z"), sessionCount: 3, hardSetCount: 10, tonnage: MeasuredTotal(value: 10_000))
        let current = WeeklySummary(weekStart: date("2026-01-12T00:00:00Z"), sessionCount: 4, hardSetCount: 12, tonnage: MeasuredTotal(value: 11_000))
        let comparison = TrainingAnalytics.compare(previous: previous, current: current)

        #expect(comparison.tonnageChange == 0.1)
        #expect(comparison.summaryText.contains("+10 %"))
        #expect(comparison.summaryText.contains("grâce") == false)
    }

    @Test
    func testComparisonRefusesToComputeOnIncompleteData() {
        let previous = WeeklySummary(weekStart: date("2026-01-05T00:00:00Z"), tonnage: MeasuredTotal(value: 0, unknownSets: 3))
        let current = WeeklySummary(weekStart: date("2026-01-12T00:00:00Z"), tonnage: MeasuredTotal(value: 5_000))
        let comparison = TrainingAnalytics.compare(previous: previous, current: current)
        #expect(comparison.tonnageChange == nil)
        #expect(comparison.summaryText.contains("non comparable"))
    }

    @Test
    func testMergingWeeksSumsEverything() {
        let weeks = TrainingAnalytics.weeklySummaries(
            sessions: [
                session("2026-01-05T10:00:00Z", sets: [set(), set()]),
                session("2026-01-12T10:00:00Z", sets: [set()]),
            ],
            calendar: calendar
        )
        let merged = TrainingAnalytics.merged(weeks)
        #expect(merged.sessionCount == 2)
        #expect(merged.workingSetCount == 3)
        #expect(merged.tonnage.value == 1_800)
    }

    // MARK: - Propriétés

    /// Propriété : le tonnage hebdomadaire agrégé égale toujours la somme des
    /// tonnages de séance calculés par `SetMetrics`.
    @Test
    func testWeeklyTonnageMatchesPerSetComputation() {
        let sessions = (0..<12).map { index in
            session(
                "2026-01-05T10:00:00Z",
                sets: [set(weight: Double(40 + index), reps: 5 + index % 4)]
            )
        }
        let expected = sessions
            .flatMap(\.workingSets)
            .compactMap { SetMetrics.tonnage($0.metrics) }
            .reduce(0, +)
        let weeks = TrainingAnalytics.weeklySummaries(sessions: sessions, calendar: calendar)
        #expect(TrainingAnalytics.merged(weeks).tonnage.value == expected)
    }

    /// Propriété : les mêmes séances donnent toujours les mêmes agrégats.
    @Test
    func testAggregationIsDeterministic() {
        let sessions = [
            session("2026-01-05T10:00:00Z", sets: [set(effort: .rir(1)), set()]),
            session("2026-01-08T10:00:00Z", sets: [set(weight: 0, reps: 15, loadKind: .bodyweight)]),
        ]
        let reference = TrainingAnalytics.weeklySummaries(sessions: sessions, calendar: calendar)
        for _ in 0..<10 {
            #expect(TrainingAnalytics.weeklySummaries(sessions: sessions, calendar: calendar) == reference)
        }
    }
}
