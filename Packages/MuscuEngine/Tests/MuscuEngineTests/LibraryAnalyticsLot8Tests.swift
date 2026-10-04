import Foundation
import Testing
@testable import MuscuEngine

// MARK: - Fusion de doublons

@Suite("Doublons d'exercices")
struct DuplicateExercisesTests {
    private func custom(
        _ id: String,
        _ name: String,
        equipment: String = "",
        muscles: [String] = [],
        sessions: Int = 0,
        sets: Int = 0
    ) -> DuplicateCandidate {
        DuplicateCandidate(id: id, name: name, equipment: equipment, primaryMuscles: muscles, isCatalog: false, sessionCount: sessions, setCount: sets)
    }

    private func catalog(_ id: String, _ nameFr: String, english: String, equipment: String = "", muscles: [String] = []) -> DuplicateCandidate {
        DuplicateCandidate(id: id, name: nameFr, alternateName: english, equipment: equipment, primaryMuscles: muscles, isCatalog: true)
    }

    @Test("Même nom normalisé : le catalogue est conservé")
    func sameNameKeepsCatalog() throws {
        let pairs = DuplicateExercises.pairs(
            custom: [custom("u1", "developpe couche", equipment: "barbell")],
            catalog: [catalog("Barbell_Bench_Press", "Développé couché", english: "Barbell Bench Press", equipment: "barbell")]
        )
        let pair = try #require(pairs.first)
        #expect(pair.reason == .sameName)
        #expect(pair.survivor.id == "Barbell_Bench_Press")
        #expect(pair.duplicate.id == "u1")
        #expect(!pair.canSwap)
    }

    @Test("Le nom anglais du catalogue compte aussi")
    func englishNameMatches() {
        let pairs = DuplicateExercises.pairs(
            custom: [custom("u1", "Barbell bench press")],
            catalog: [catalog("bench", "Développé couché", english: "Barbell Bench Press", equipment: "barbell")]
        )
        #expect(pairs.first?.reason == .sameName)
    }

    @Test("Un matériel différent n'est jamais un doublon par le nom")
    func differentEquipmentIsNotADuplicate() {
        let pairs = DuplicateExercises.pairs(
            custom: [custom("u1", "Développé couché", equipment: "dumbbell")],
            catalog: [catalog("bench", "Développé couché", english: "Bench Press", equipment: "barbell")]
        )
        #expect(pairs.isEmpty)
    }

    @Test("Convention d'import : le matériel entre parenthèses désigne l'autre exercice")
    func importNamingConvention() throws {
        let pairs = DuplicateExercises.pairs(
            custom: [custom("u1", "Deadlift (Barbell)")],
            catalog: [catalog("deadlift", "Soulevé de terre", english: "Deadlift", equipment: "barbell")]
        )
        let pair = try #require(pairs.first)
        #expect(pair.reason == .sameImportName)
        #expect(pair.survivor.id == "deadlift")
    }

    @Test("Deux imports au même nom de base et au même matériel se rapprochent")
    func twoImportsShareBaseName() {
        let pairs = DuplicateExercises.pairs(
            custom: [custom("u1", "Row (Cable)"), custom("u2", "row", equipment: "cable")],
            catalog: []
        )
        #expect(pairs.count == 1)
        #expect(pairs.first?.reason == .sameImportName)
    }

    @Test("Faute de frappe : nom proche, à juger")
    func similarNameIsAJudgementCall() throws {
        let pairs = DuplicateExercises.pairs(
            custom: [
                custom("u1", "Tirage horizontl", muscles: ["middle back"], sessions: 2, sets: 6),
                custom("u2", "Tirage horizontal", muscles: ["middle back"], sessions: 9, sets: 27),
            ],
            catalog: []
        )
        let pair = try #require(pairs.first)
        #expect(pair.reason == .similarName)
        #expect(pair.survivor.id == "u2", "Le plus d'historique est conservé")
        #expect(pair.canSwap)
        #expect(pair.swapped().survivor.id == "u1")
    }

    @Test("Un mot seul n'est pas un indice ; deux mots inclus le sont")
    func tokenSubsetNeedsTwoWords() {
        let generic = DuplicateExercises.pairs(
            custom: [custom("u1", "Curl")],
            catalog: [catalog("hammer", "Curl marteau", english: "Hammer Curl", equipment: "dumbbell")]
        )
        #expect(generic.isEmpty)

        let specific = DuplicateExercises.pairs(
            custom: [custom("u1", "Curl marteau", equipment: "dumbbell")],
            catalog: [catalog("hammer", "Curl marteau incliné", english: "Incline Hammer Curls", equipment: "dumbbell")]
        )
        #expect(specific.first?.reason == .similarName)
    }

    @Test("Des muscles sans point commun écartent un nom proche")
    func incompatibleMuscles() {
        let pairs = DuplicateExercises.pairs(
            custom: [custom("u1", "Extension mollets", muscles: ["calves"])],
            catalog: [catalog("x", "Extension lombaires", english: "Back extension", muscles: ["lower back"])]
        )
        #expect(pairs.isEmpty)
    }

    @Test("Deux exercices du catalogue ne forment jamais une paire, une paire écartée disparaît")
    func catalogPairsAndDismissal() {
        let first = catalog("a", "Squat", english: "Squat")
        let second = catalog("b", "Squat", english: "Squat")
        #expect(DuplicateExercises.reason(first, second) == nil)

        let candidate = custom("u1", "Squat")
        let pairs = DuplicateExercises.pairs(custom: [candidate], catalog: [first])
        #expect(pairs.count == 1)
        let dismissed = DuplicateExercises.pairs(custom: [candidate], catalog: [first], dismissed: [DuplicatePair.key("a", "u1")])
        #expect(dismissed.isEmpty)
    }

    @Test("Les paires sûres passent avant les paires à juger")
    func ordering() {
        let pairs = DuplicateExercises.pairs(
            custom: [custom("u1", "Tirage horizontl"), custom("u2", "Squat")],
            catalog: [
                catalog("row", "Tirage horizontal", english: "Seated Row"),
                catalog("squat", "Squat", english: "Squat"),
            ]
        )
        #expect(pairs.map(\.reason) == [.sameName, .similarName])
    }
}

@Suite("Règles de fusion")
struct ExerciseMergeTests {
    @Test("Une redirection se suit jusqu'au bout, un cycle ne boucle pas")
    func redirectChains() {
        #expect(ExerciseMerge.resolve("a", redirects: ["a": "b", "b": "c"]) == "c")
        #expect(ExerciseMerge.resolve("x", redirects: ["a": "b"]) == "x")
        #expect(ExerciseMerge.resolve("a", redirects: ["a": "b", "b": "a"]) == "a")
        #expect(ExerciseMerge.wouldCreateCycle(duplicate: "b", survivor: "a", redirects: ["a": "b"]))
        #expect(!ExerciseMerge.wouldCreateCycle(duplicate: "b", survivor: "c", redirects: ["a": "b"]))
        #expect(ExerciseMerge.wouldCreateCycle(duplicate: "a", survivor: "a", redirects: [:]))
    }

    @Test("Le meilleur record survit, jamais de régression ; égalité = celui du survivant")
    func recordReconciliation() throws {
        let kept = RecordValue(value: 100, sessionId: UUID())
        let moved = RecordValue(value: 105, sessionId: UUID())

        let higher = try #require(ExerciseMerge.reconcile(survivor: kept, duplicate: moved, lowerIsBetter: false))
        #expect(higher.value == moved)
        #expect(higher.fromDuplicate)

        let tie = try #require(ExerciseMerge.reconcile(survivor: kept, duplicate: RecordValue(value: 100), lowerIsBetter: false))
        #expect(tie.value == kept)
        #expect(!tie.fromDuplicate)

        let time = try #require(ExerciseMerge.reconcile(survivor: RecordValue(value: 300), duplicate: RecordValue(value: 280), lowerIsBetter: true))
        #expect(time.value.value == 280, "Un temps plus court est meilleur")

        #expect(ExerciseMerge.reconcile(survivor: nil, duplicate: nil, lowerIsBetter: false) == nil)
        #expect(ExerciseMerge.reconcile(survivor: nil, duplicate: moved, lowerIsBetter: false)?.fromDuplicate == true)
    }

    @Test("Listes et objectifs : l'identifiant du doublon devient celui du survivant")
    func referencesAreRewritten() {
        #expect(ExerciseMerge.replacing("dup", with: "keep", in: ["a", "dup", "keep", "b"]) == ["a", "keep", "b"])
        #expect(ExerciseMerge.replacing("dup", with: "keep", in: ["dup"]) == ["keep"])

        let goal = GoalTarget.exerciseOneRepMax(exerciseId: "dup", kilograms: 120)
        #expect(goal.replacingExercise("dup", with: "keep") == .exerciseOneRepMax(exerciseId: "keep", kilograms: 120))
        let reps = GoalTarget.exerciseReps(exerciseId: "other", reps: 20)
        #expect(reps.replacingExercise("dup", with: "keep") == reps)
        #expect(GoalTarget.sessionsPerWeek(count: 3).replacingExercise("dup", with: "keep") == .sessionsPerWeek(count: 3))
    }
}

// MARK: - Exercices habituels

@Suite("Exercices habituels")
struct ExerciseRankingTests {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func occurrence(_ id: String, daysAgo: Double, session: UUID = UUID()) -> ExerciseOccurrence {
        ExerciseOccurrence(exerciseId: id, sessionId: session, date: now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test("Une séance d'il y a 30 jours compte pour moitié")
    func halfLife() {
        #expect(abs(ExerciseRanking.weight(of: now.addingTimeInterval(-30 * 86_400), now: now) - 0.5) < 1e-9)
        #expect(ExerciseRanking.weight(of: now, now: now) == 1)
        #expect(ExerciseRanking.weight(of: now.addingTimeInterval(86_400), now: now) == 1, "Une date future ne compte pas double")
    }

    @Test("La récence l'emporte sur un vieux volume")
    func recencyBeatsOldVolume() {
        var occurrences = (0..<10).map { _ in occurrence("old", daysAgo: 200) }
        occurrences += (0..<3).map { _ in occurrence("recent", daysAgo: 3) }
        #expect(ExerciseRanking.habitual(occurrences: occurrences, now: now) == ["recent", "old"])
    }

    @Test("À ancienneté égale, la fréquence départage")
    func frequencyBreaksTies() {
        let occurrences = [
            occurrence("a", daysAgo: 2), occurrence("a", daysAgo: 9),
            occurrence("b", daysAgo: 2),
        ]
        #expect(ExerciseRanking.habitual(occurrences: occurrences, now: now) == ["a", "b"])
    }

    @Test("Plusieurs séries d'une même séance comptent une fois")
    func oneSessionCountsOnce() {
        let session = UUID()
        let occurrences = (0..<5).map { _ in occurrence("a", daysAgo: 1, session: session) } + [
            occurrence("b", daysAgo: 1), occurrence("b", daysAgo: 1),
        ]
        let scores = ExerciseRanking.scores(occurrences: occurrences, now: now)
        #expect(scores["b"]! > scores["a"]!)
    }

    @Test("Limite, filtre des exercices proposables et ordre stable par nom")
    func limitFilterAndStableOrder() {
        let session = UUID()
        let occurrences = ["c", "a", "b", "hidden"].map { occurrence($0, daysAgo: 1, session: session) }
        let ranked = ExerciseRanking.habitual(
            occurrences: occurrences,
            now: now,
            limit: 2,
            among: ["a", "b", "c"],
            names: ["a": "Alpha", "b": "Bravo", "c": "Charlie"]
        )
        #expect(ranked == ["a", "b"])
        #expect(ExerciseRanking.habitual(occurrences: [], now: now).isEmpty, "Jamais pratiqué = absent, pas classé à zéro")
    }
}

// MARK: - Tableau de bord

@Suite("Indice de force et records du mois")
struct StrengthDashboardTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func date(_ day: Int, month: Int = 3) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 18))!
    }

    private func set(_ id: String, _ weight: Double, _ reps: Int, loadKind: LoadKind = .external, bodyweight: Double? = nil, warmup: Bool = false) -> AnalyticsSet {
        AnalyticsSet(
            exerciseId: id,
            displayName: id.capitalized,
            metrics: SetMetricsInput(weightKilograms: weight, reps: reps, loadKind: loadKind, isWarmup: warmup, bodyweightKilograms: bodyweight)
        )
    }

    private func interval(_ start: Date, _ end: Date) -> DateInterval { DateInterval(start: start, end: end) }

    @Test("Indice = somme des meilleurs 1RM estimés, tendance sur les exercices communs")
    func strengthIndexSumsBestEstimates() throws {
        let sessions = [
            AnalyticsSession(date: date(2, month: 2), sets: [set("squat", 100, 5), set("bench", 80, 5)]),
            AnalyticsSession(date: date(3), sets: [set("squat", 105, 5), set("bench", 80, 5), set("row", 60, 8)]),
            AnalyticsSession(date: date(10), sets: [set("squat", 100, 3), set("bench", 82.5, 5)]),
        ]
        let main = StrengthDashboard.mainExercises(sessions: sessions)
        #expect(main.map(\.exerciseId) == ["bench", "squat", "row"])

        let index = StrengthDashboard.strengthIndex(
            main: main,
            sessions: sessions,
            period: interval(date(1), date(1, month: 4)),
            previousPeriod: interval(date(1, month: 2), date(1))
        )
        let squat = OneRepMax.epley(weight: 105, reps: 5)
        let bench = OneRepMax.epley(weight: 82.5, reps: 5)
        let row = OneRepMax.epley(weight: 60, reps: 8)
        let value = try #require(index.value)
        #expect(abs(value - (squat + bench + row)) < 1e-9)
        #expect(index.excluded.isEmpty)
        // Le rowing n'existait pas avant : exclu de la comparaison.
        let previous = OneRepMax.epley(weight: 100, reps: 5) + OneRepMax.epley(weight: 80, reps: 5)
        #expect(abs((index.previousComparableValue ?? 0) - previous) < 1e-9)
        #expect(index.trend == .up)
    }

    @Test("Exercice principal sans donnée : exclu et annoncé, jamais compté à zéro")
    func missingDataIsExcludedNotZero() {
        let sessions = [
            AnalyticsSession(date: date(3), sets: [set("dips", 0, 10, loadKind: .weighted)]),
            AnalyticsSession(date: date(4, month: 2), sets: [set("dips", 10, 8, loadKind: .weighted, bodyweight: 80)]),
        ]
        let main = StrengthDashboard.mainExercises(sessions: sessions)
        let index = StrengthDashboard.strengthIndex(
            main: main,
            sessions: sessions,
            period: interval(date(1), date(1, month: 4)),
            previousPeriod: interval(date(1, month: 2), date(1))
        )
        #expect(index.value == nil)
        #expect(index.excluded.map(\.exerciseId) == ["dips"])
        #expect(index.trend == nil)
    }

    @Test("Zone neutre de ±1 %")
    func trendThreshold() {
        #expect(StrengthDashboard.trend(for: 0.009) == .stable)
        #expect(StrengthDashboard.trend(for: -0.009) == .stable)
        #expect(StrengthDashboard.trend(for: 0.01) == .up)
        #expect(StrengthDashboard.trend(for: -0.02) == .down)
    }

    @Test("Records du mois : record battu, premier essai, charge sous le record")
    func periodRecords() throws {
        let sessions = [
            AnalyticsSession(date: date(10, month: 2), sets: [set("squat", 100, 5), set("bench", 90, 3)]),
            AnalyticsSession(date: date(5), sets: [set("squat", 110, 3), set("bench", 80, 5), set("press", 40, 8)]),
            AnalyticsSession(date: date(12), sets: [set("squat", 120, 1, warmup: true)]),
        ]
        let entries = StrengthDashboard.periodRecords(
            sessions: sessions,
            period: StrengthDashboard.month(containing: date(15), calendar: calendar)
        )
        #expect(entries.map(\.exerciseId) == ["squat", "press", "bench"])
        let squat = try #require(entries.first)
        #expect(squat.isNewRecord)
        #expect(squat.periodBest == 110, "L'échauffement ne compte pas")
        #expect(squat.ratioToRecord == 1)

        let press = entries[1]
        #expect(!press.isNewRecord, "Un premier essai n'a rien battu")
        #expect(press.previousBest == nil)

        let bench = entries[2]
        #expect(!bench.isNewRecord)
        #expect(abs(bench.ratioToRecord - 80.0 / 90.0) < 1e-9)
    }

    @Test("Une séance à minuit pile appartient à une seule période")
    func halfOpenIntervals() {
        let boundary = date(1)
        let sessions = [AnalyticsSession(date: boundary, sets: [set("squat", 100, 5)])]
        let before = StrengthDashboard.bestEstimatedOneRepMax(sessions: sessions, in: interval(date(1, month: 2), boundary))
        let after = StrengthDashboard.bestEstimatedOneRepMax(sessions: sessions, in: interval(boundary, date(1, month: 4)))
        #expect(before.isEmpty)
        #expect(after["squat"] != nil)
    }
}

@Suite("Statistiques par exercice")
struct ExerciseStatisticsTests {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func day(_ offset: Int) -> Date { start.addingTimeInterval(Double(offset) * 86_400) }

    private func session(_ offset: Int, _ sets: [(Double, Int)], loadKind: LoadKind = .external, bodyweight: Double? = nil) -> AnalyticsSession {
        AnalyticsSession(date: day(offset), sets: sets.map { weight, reps in
            AnalyticsSet(
                exerciseId: "squat",
                displayName: "Squat",
                metrics: SetMetricsInput(weightKilograms: weight, reps: reps, loadKind: loadKind, bodyweightKilograms: bodyweight)
            )
        })
    }

    @Test("Force relative : 1RM estimé / poids de corps connu à la date")
    func relativeStrength() throws {
        let history = [session(0, [(100, 5)]), session(10, [(110, 3)])]
        let stats = ExerciseStatistics.compute(
            exerciseId: "squat",
            history: history,
            period: DateInterval(start: day(-1), end: day(30)),
            bodyweights: [AnalyticsPoint(date: day(-5), value: 80), AnalyticsPoint(date: day(20), value: 90)]
        )
        let best = try #require(stats.bestEstimatedOneRepMax)
        #expect(best.date == day(10))
        #expect(stats.bodyweightAtBest == 80, "Jamais une pesée postérieure")
        #expect(abs((stats.relativeStrength ?? 0) - OneRepMax.epley(weight: 110, reps: 3) / 80) < 1e-9)
    }

    @Test("Sans poids de corps connu à la date, pas de force relative")
    func relativeStrengthNeedsBodyweight() {
        let stats = ExerciseStatistics.compute(
            exerciseId: "squat",
            history: [session(0, [(100, 5)])],
            period: DateInterval(start: day(-1), end: day(30)),
            bodyweights: [AnalyticsPoint(date: day(5), value: 80)]
        )
        #expect(stats.bestEstimatedOneRepMax != nil)
        #expect(stats.relativeStrength == nil)
    }

    @Test("Intensité : charge / meilleur 1RM connu jusqu'à la séance, jamais un 1RM futur")
    func intensityUsesRunningBest() throws {
        let history = [session(0, [(100, 5), (90, 5)]), session(7, [(120, 1)])]
        let stats = ExerciseStatistics.compute(
            exerciseId: "squat",
            history: history,
            period: DateInterval(start: day(-1), end: day(1)),
            bodyweights: []
        )
        let reference = OneRepMax.epley(weight: 100, reps: 5)
        let expected = (100 / reference + 90 / reference) / 2
        #expect(abs((stats.averageIntensity ?? 0) - expected) < 1e-9)
        #expect(stats.intensitySetCount == 2)
        #expect(stats.averageLoad == 95)
        #expect(stats.loadSetCount == 2)
    }

    @Test("Charge inconnue : exclue des moyennes et comptée à part ; aucune série = nil")
    func unknownLoadsAreAnnounced() {
        let stats = ExerciseStatistics.compute(
            exerciseId: "squat",
            history: [session(0, [(10, 8)], loadKind: .weighted)],
            period: DateInterval(start: day(-1), end: day(1)),
            bodyweights: []
        )
        #expect(stats.unknownLoadSets == 1)
        #expect(stats.averageLoad == nil)
        #expect(stats.averageIntensity == nil)

        let empty = ExerciseStatistics.compute(exerciseId: "bench", history: [session(0, [(100, 5)])], period: DateInterval(start: day(-1), end: day(1)), bodyweights: [])
        #expect(empty == ExerciseStatistics())
    }
}

// MARK: - Sauvegardes automatiques

@Suite("Sauvegardes automatiques")
struct AutoBackupPolicyTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    @Test("Au plus une sauvegarde par jour calendaire")
    func oncePerDay() {
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 8))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 22))!
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 0, minute: 5))!
        #expect(AutoBackupPolicy.isDue(lastBackupAt: nil, now: morning, calendar: calendar))
        #expect(!AutoBackupPolicy.isDue(lastBackupAt: morning, now: evening, calendar: calendar))
        #expect(AutoBackupPolicy.isDue(lastBackupAt: evening, now: nextDay, calendar: calendar))
        #expect(AutoBackupPolicy.isDue(lastBackupAt: nextDay, now: morning, calendar: calendar), "Horloge reculée : on sauvegarde")
    }

    @Test("Rotation : seules les sauvegardes automatiques les plus anciennes partent")
    func rotation() {
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        var files = (0..<9).map { index in
            (name: AutoBackupPolicy.fileName(for: base.addingTimeInterval(Double(index) * 86_400), timeZone: TimeZone(identifier: "UTC")!),
             date: base.addingTimeInterval(Double(index) * 86_400))
        }
        files.append((name: "mon-fichier.json", date: base.addingTimeInterval(-86_400)))
        let pruned = AutoBackupPolicy.filesToPrune(files, retained: 7)
        #expect(pruned.count == 2)
        #expect(pruned.allSatisfy { $0.hasPrefix(AutoBackupPolicy.filePrefix) })
        #expect(pruned.contains(files[0].name) && pruned.contains(files[1].name))
        #expect(AutoBackupPolicy.filesToPrune(files, retained: 0).count == 8, "Au moins une sauvegarde est toujours gardée")
    }

    @Test("Nom de fichier triable et reconnaissable")
    func fileName() {
        let name = AutoBackupPolicy.fileName(for: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "muscu-sauvegarde-1970-01-01-000000.json")
        #expect(AutoBackupPolicy.isAutomaticBackup(fileName: name))
        #expect(!AutoBackupPolicy.isAutomaticBackup(fileName: "muscu-export-2026-10-04.json"))
    }
}
