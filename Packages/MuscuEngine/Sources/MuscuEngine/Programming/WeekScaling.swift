import Foundation

/// Applique à un déroulé de séance les multiplicateurs de volume et
/// d'intensité de la semaine de plan à laquelle elle appartient.
///
/// `Periodization` calculait déjà ces multiplicateurs — une semaine de
/// décharge vaut 50 % de volume et 90 % d'intensité — et le plan les
/// affichait. Mais **personne ne les appliquait** : une semaine de décharge
/// planifiée était une étiquette, pas une décharge. C'est ce que corrige ce
/// fichier.
///
/// La mise à l'échelle est délibérément conservatrice :
///
/// - le **volume** agit sur le nombre de séries de travail, jamais en dessous
///   d'une série : retirer entièrement un exercice n'est pas une décharge,
///   c'est une annulation ;
/// - l'**intensité** agit sur la charge cible et sur le pourcentage de 1RM ;
/// - les formats **chronométrés** (intervalles, EMOM, AMRAP, For Time) ne
///   sont pas touchés : raccourcir un EMOM change la nature de l'exercice,
///   pas sa dose. Les alléger relève d'une décision humaine.
public struct WeekScaling: Equatable, Sendable {
    public var volumeMultiplier: Double
    public var intensityMultiplier: Double
    /// Palier de charge réellement disponible, pour ne pas proposer 47,3 kg.
    /// `0` signifie « pas d'arrondi ».
    public var loadIncrementKilograms: Double

    public init(
        volumeMultiplier: Double,
        intensityMultiplier: Double,
        loadIncrementKilograms: Double = 0
    ) {
        self.volumeMultiplier = volumeMultiplier
        self.intensityMultiplier = intensityMultiplier
        self.loadIncrementKilograms = loadIncrementKilograms
    }

    public static let neutral = WeekScaling(volumeMultiplier: 1, intensityMultiplier: 1)

    /// Mise a l'echelle correspondant a une suggestion du check-in de forme.
    ///
    /// `ReadinessAdvisor` proposait « reduire le volume d'environ 30 % » et
    /// personne ne pouvait l'appliquer : la suggestion etait une phrase. Les
    /// deux ajustements chiffres se traduisent exactement dans le meme
    /// mecanisme que la semaine de decharge — il serait absurde d'en ecrire
    /// un second.
    ///
    /// Les ajustements NON chiffres (substitution, repos) renvoient `nil` :
    /// ils demandent une decision humaine, pas une multiplication.
    public init?(readiness adjustment: ReadinessAdjustment, loadIncrementKilograms: Double = 0) {
        switch adjustment {
        case .reduceVolume(let multiplier):
            self.init(
                volumeMultiplier: multiplier,
                intensityMultiplier: 1,
                loadIncrementKilograms: loadIncrementKilograms
            )
        case .reduceLoad(let multiplier):
            self.init(
                volumeMultiplier: 1,
                intensityMultiplier: multiplier,
                loadIncrementKilograms: loadIncrementKilograms
            )
        case .keepAsPlanned, .suggestSubstitution, .suggestRest:
            return nil
        }
    }

    /// Combine deux mises a l'echelle : une semaine de decharge ET un
    /// check-in prudent doivent se cumuler, pas s'annuler.
    public func combined(with other: WeekScaling) -> WeekScaling {
        WeekScaling(
            volumeMultiplier: volumeMultiplier * other.volumeMultiplier,
            intensityMultiplier: intensityMultiplier * other.intensityMultiplier,
            loadIncrementKilograms: max(loadIncrementKilograms, other.loadIncrementKilograms)
        )
    }

    /// Une semaine ordinaire ne doit rien changer du tout — et surtout pas
    /// faire subir un arrondi à une charge que l'utilisateur a saisie.
    public var isNeutral: Bool {
        volumeMultiplier == 1 && intensityMultiplier == 1
    }

    /// Les multiplicateurs venant d'un fichier importé sont des données :
    /// une valeur absurde ne doit pas produire une séance absurde.
    public var isUsable: Bool {
        volumeMultiplier.isFinite && intensityMultiplier.isFinite
            && volumeMultiplier > 0 && intensityMultiplier > 0
            && volumeMultiplier <= 5 && intensityMultiplier <= 5
    }

    // MARK: - Application

    public func applied(to plan: WorkoutPlan) -> WorkoutPlan {
        guard !isNeutral, isUsable else { return plan }
        var scaled = plan
        scaled.nodes = plan.nodes.map { node in
            var node = node
            node.exercises = node.exercises.map(applied(to:))
            return node
        }
        return scaled
    }

    public func applied(to exercise: WorkoutExercisePlan) -> WorkoutExercisePlan {
        guard !isNeutral, isUsable else { return exercise }
        var scaled = exercise

        if exercise.format.countsSetsOfWork {
            scaled.setCount = scaledSetCount(exercise.setCount)
        }
        if let weight = exercise.targetWeight {
            scaled.targetWeight = scaledWeight(weight)
        }
        if let percent = exercise.percentOneRepMax {
            scaled.percentOneRepMax = scaledPercent(percent)
        }
        if let percent = exercise.percentMaxReps {
            scaled.percentMaxReps = scaledPercent(percent)
        }
        return scaled
    }

    // MARK: - Regles unitaires

    public func scaledSetCount(_ setCount: Int) -> Int {
        guard setCount > 0 else { return setCount }
        let scaled = Int((Double(setCount) * volumeMultiplier).rounded())
        // Jamais zéro : un exercice qui disparaît n'est pas une décharge.
        return max(1, scaled)
    }

    public func scaledWeight(_ kilograms: Double) -> Double {
        guard kilograms > 0 else { return kilograms }
        let target = kilograms * intensityMultiplier
        let rounded = roundedToIncrement(target)
        guard intensityMultiplier < 1 else { return max(rounded, 0) }
        // Une décharge doit réellement alléger. Si l'arrondi ramène sur la
        // charge d'origine, on descend d'un palier — sans jamais passer sous
        // un palier.
        guard rounded >= kilograms, loadIncrementKilograms > 0 else {
            return max(rounded, 0)
        }
        return max(kilograms - loadIncrementKilograms, loadIncrementKilograms)
    }

    public func scaledPercent(_ percent: Double) -> Double {
        guard percent > 0 else { return percent }
        let scaled = (percent * intensityMultiplier).rounded()
        return min(max(scaled, 1), 100)
    }

    private func roundedToIncrement(_ value: Double) -> Double {
        guard loadIncrementKilograms > 0 else { return (value * 10).rounded() / 10 }
        return (value / loadIncrementKilograms).rounded() * loadIncrementKilograms
    }
}

extension WorkoutFormat {
    /// Les formats dont la dose se compte en SÉRIES. Les autres se comptent
    /// en temps, et leur nombre de séries n'a pas le même sens.
    var countsSetsOfWork: Bool {
        switch self {
        case .classic, .dropset, .restPause, .myoReps, .pyramid:
            return true
        case .intervals, .emom, .amrap, .forTime:
            return false
        }
    }
}
