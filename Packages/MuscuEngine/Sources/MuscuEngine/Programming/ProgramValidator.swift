import Foundation

/// Gravite d'un constat de validation.
public enum ValidationSeverity: String, Codable, CaseIterable, Sendable {
    /// Le programme ne respecte pas une contrainte explicite de l'athlete
    /// (materiel, niveau, zone a menager, exclusion). Il ne doit pas etre
    /// applique tel quel.
    case blocking
    /// Le programme est applicable mais s'ecarte d'une recommandation.
    case warning
}

public struct ValidationIssue: Equatable, Sendable {
    public var severity: ValidationSeverity
    /// Identifiant stable de la regle, pour les tests et les journaux.
    public var code: String
    public var message: String
    /// Seance concernee, quand le constat est localise.
    public var sessionName: String?

    public init(severity: ValidationSeverity, code: String, message: String, sessionName: String? = nil) {
        self.severity = severity
        self.code = code
        self.message = message
        self.sessionName = sessionName
    }
}

public struct ValidationReport: Equatable, Sendable {
    public var issues: [ValidationIssue]

    public init(issues: [ValidationIssue]) {
        self.issues = issues
    }

    public var isAcceptable: Bool { !issues.contains { $0.severity == .blocking } }
    public var blockingIssues: [ValidationIssue] { issues.filter { $0.severity == .blocking } }
    public var warnings: [ValidationIssue] { issues.filter { $0.severity == .warning } }
}

/// Bornes de volume hebdomadaire par muscle, configurables.
public struct VolumeBounds: Equatable, Sendable {
    public var minimumWeeklySets: Int
    public var maximumWeeklySets: Int

    public init(minimumWeeklySets: Int = 6, maximumWeeklySets: Int = 24) {
        self.minimumWeeklySets = minimumWeeklySets
        self.maximumWeeklySets = maximumWeeklySets
    }

    /// Bornes usuelles par niveau. Volontairement larges : il s'agit de
    /// reperer l'aberrant, pas d'imposer une doctrine.
    public static func recommended(for experience: Experience) -> VolumeBounds {
        switch experience {
        case .beginner: return VolumeBounds(minimumWeeklySets: 4, maximumWeeklySets: 16)
        case .intermediate: return VolumeBounds(minimumWeeklySets: 6, maximumWeeklySets: 22)
        case .advanced: return VolumeBounds(minimumWeeklySets: 8, maximumWeeklySets: 28)
        }
    }
}

/// Verifie qu'un programme respecte les contraintes declarees par l'athlete.
///
/// C'est le point de controle commun au generateur local ET a toute
/// proposition externe (import, IA) : aucune prescription ne doit atteindre
/// le store sans etre passee par ici.
public struct ProgramValidator: Sendable {
    private let catalog: ExerciseCatalog

    public init(catalog: ExerciseCatalog) {
        self.catalog = catalog
    }

    public func validate(
        program: DraftProgram,
        input: GeneratorInput,
        bounds: VolumeBounds? = nil
    ) -> ValidationReport {
        var issues: [ValidationIssue] = []
        let bounds = bounds ?? VolumeBounds.recommended(for: input.experience)

        if program.sessions.isEmpty {
            issues.append(
                ValidationIssue(
                    severity: .blocking,
                    code: "program.empty",
                    message: "Le programme ne contient aucune séance."
                )
            )
            return ValidationReport(issues: issues)
        }

        if program.sessions.count != input.daysPerWeek {
            issues.append(
                ValidationIssue(
                    severity: .warning,
                    code: "program.dayCount",
                    message: "Le programme contient \(program.sessions.count) séances pour \(input.daysPerWeek) jours demandés."
                )
            )
        }

        for session in program.sessions {
            issues.append(contentsOf: validate(session: session, input: input))
        }

        issues.append(contentsOf: validateVolume(program: program, input: input, bounds: bounds))
        issues.append(contentsOf: validateRecovery(program: program))

        return ValidationReport(issues: issues)
    }

    // MARK: - Séance

    private func validate(session: DraftSession, input: GeneratorInput) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if session.exercises.isEmpty {
            issues.append(
                ValidationIssue(
                    severity: .blocking,
                    code: "session.empty",
                    message: "La séance « \(session.name) » ne contient aucun exercice.",
                    sessionName: session.name
                )
            )
            return issues
        }

        let identifiers = session.exercises.map(\.exerciseId)
        if Set(identifiers).count != identifiers.count {
            issues.append(
                ValidationIssue(
                    severity: .warning,
                    code: "session.duplicateExercise",
                    message: "La séance « \(session.name) » répète un même exercice.",
                    sessionName: session.name
                )
            )
        }

        for exercise in session.exercises {
            guard let catalogExercise = catalog.exercise(id: exercise.exerciseId) else {
                // Un exercice inconnu du catalogue n'est pas forcement une
                // erreur (exercice personnalise), mais il ne peut pas etre
                // verifie : on le signale sans bloquer.
                issues.append(
                    ValidationIssue(
                        severity: .warning,
                        code: "exercise.unknown",
                        message: "« \(exercise.displayName) » n'est pas dans le catalogue : ses contraintes n'ont pas pu être vérifiées.",
                        sessionName: session.name
                    )
                )
                continue
            }

            if input.excludedExerciseIds.contains(catalogExercise.id) {
                issues.append(
                    ValidationIssue(
                        severity: .blocking,
                        code: "exercise.excluded",
                        message: "« \(catalogExercise.nameFr) » fait partie des exercices exclus.",
                        sessionName: session.name
                    )
                )
            }

            if !RuleBasedGenerator.isEquipmentAllowed(catalogExercise.equipment, for: equipment(for: input)) {
                issues.append(
                    ValidationIssue(
                        severity: .blocking,
                        code: "exercise.equipment",
                        message: "« \(catalogExercise.nameFr) » demande du matériel indisponible (\(catalogExercise.equipment ?? "inconnu")).",
                        sessionName: session.name
                    )
                )
            }

            if !RuleBasedGenerator.isLevelAllowed(catalogExercise.level, for: input.experience) {
                issues.append(
                    ValidationIssue(
                        severity: .warning,
                        code: "exercise.level",
                        message: "« \(catalogExercise.nameFr) » est classé \(catalogExercise.level), au-dessus du niveau déclaré.",
                        sessionName: session.name
                    )
                )
            }

            for area in input.avoidAreas where RuleBasedGenerator.exercise(catalogExercise, stresses: area) {
                issues.append(
                    ValidationIssue(
                        severity: .blocking,
                        code: "exercise.avoidArea",
                        message: "« \(catalogExercise.nameFr) » sollicite une zone à ménager (\(area)).",
                        sessionName: session.name
                    )
                )
            }

            if exercise.sets <= 0 || exercise.repsLower <= 0 || exercise.repsLower > exercise.repsUpper {
                issues.append(
                    ValidationIssue(
                        severity: .blocking,
                        code: "exercise.prescription",
                        message: "La prescription de « \(exercise.displayName) » est incohérente.",
                        sessionName: session.name
                    )
                )
            }

            if let percent = exercise.percentOneRepMax, !(30...100).contains(percent) {
                issues.append(
                    ValidationIssue(
                        severity: .blocking,
                        code: "exercise.percent",
                        message: "Le pourcentage de 1RM de « \(exercise.displayName) » est hors bornes.",
                        sessionName: session.name
                    )
                )
            }
        }

        // Duree estimee, echauffement compris.
        let plan = WorkoutPlan(nodes: session.exercises.map { draft in
            .single(
                WorkoutExercisePlan(
                    exerciseId: draft.exerciseId,
                    displayName: draft.displayName,
                    setCount: draft.sets,
                    repsLower: draft.repsLower,
                    repsUpper: draft.repsUpper,
                    restSeconds: draft.restSeconds
                )
            )
        })
        let estimated = SessionDuration.estimatedMinutes(for: plan)
        if estimated > input.sessionMinutes {
            issues.append(
                ValidationIssue(
                    severity: .warning,
                    code: "session.duration",
                    message: "La séance « \(session.name) » est estimée à \(estimated) min pour un budget de \(input.sessionMinutes) min.",
                    sessionName: session.name
                )
            )
        }

        return issues
    }

    // MARK: - Volume et récupération

    private func validateVolume(
        program: DraftProgram,
        input: GeneratorInput,
        bounds: VolumeBounds
    ) -> [ValidationIssue] {
        let volume = PlanGenerator.weeklySetsByMuscle(program: program, catalog: catalog)
        var issues: [ValidationIssue] = []
        for (muscle, sets) in volume.sorted(by: { $0.key < $1.key }) where sets > bounds.maximumWeeklySets {
            issues.append(
                ValidationIssue(
                    severity: .warning,
                    code: "volume.high",
                    message: "\(FrenchLabels.muscle(muscle)) : \(sets) séries hebdomadaires, au-dessus de la borne de \(bounds.maximumWeeklySets)."
                )
            )
        }
        // Les muscles prioritaires doivent recevoir un volume minimal :
        // les declarer sans les travailler serait incoherent.
        for muscle in input.priorityMuscles {
            let sets = volume[muscle] ?? 0
            if sets < bounds.minimumWeeklySets {
                issues.append(
                    ValidationIssue(
                        severity: .warning,
                        code: "volume.priorityLow",
                        message: "\(FrenchLabels.muscle(muscle)) est prioritaire mais ne reçoit que \(sets) séries hebdomadaires."
                    )
                )
            }
        }
        return issues
    }

    /// Recuperation : un meme muscle ne devrait pas etre sollicite lourdement
    /// deux jours consecutifs. Les seances etant reparties dans la semaine,
    /// on approxime en comparant des seances adjacentes du programme.
    private func validateRecovery(program: DraftProgram) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let musclesPerSession = program.sessions.map { session in
            Set(session.exercises.flatMap { catalog.exercise(id: $0.exerciseId)?.primaryMuscles ?? [] })
        }
        guard musclesPerSession.count > 1 else { return issues }

        for index in 0..<(musclesPerSession.count - 1) {
            let shared = musclesPerSession[index].intersection(musclesPerSession[index + 1])
            let large = shared.filter { Self.largeMuscles.contains($0) }
            guard !large.isEmpty else { continue }
            let names = large.sorted().map(FrenchLabels.muscle).joined(separator: ", ")
            issues.append(
                ValidationIssue(
                    severity: .warning,
                    code: "recovery.consecutive",
                    message: "\(names) sollicité(s) sur deux séances consécutives : prévoyez un jour de récupération entre les deux.",
                    sessionName: program.sessions[index + 1].name
                )
            )
        }
        return issues
    }

    /// Groupes musculaires assez volumineux pour que deux seances d'affilee
    /// posent un vrai probleme de recuperation.
    static let largeMuscles: Set<String> = ["quadriceps", "hamstrings", "glutes", "chest", "lats", "middle back"]

    private func equipment(for input: GeneratorInput) -> TrainingEquipment {
        // Le calisthenics impose le poids du corps, quel que soit le choix.
        input.goal == .calisthenics ? .bodyweight : input.equipment
    }
}
