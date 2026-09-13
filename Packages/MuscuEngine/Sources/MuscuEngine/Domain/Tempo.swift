import Foundation

/// Tempo en quatre phases, note « excentrique-pause basse-concentrique-pause
/// haute », par exemple `3-1-1-0`. Une phase a `0` seconde est valide.
public struct Tempo: Codable, Equatable, Hashable, Sendable {
    public var eccentric: Int
    public var bottomPause: Int
    public var concentric: Int
    public var topPause: Int

    public init(eccentric: Int, bottomPause: Int, concentric: Int, topPause: Int) {
        self.eccentric = max(0, eccentric)
        self.bottomPause = max(0, bottomPause)
        self.concentric = max(0, concentric)
        self.topPause = max(0, topPause)
    }

    public var secondsPerRep: Int { eccentric + bottomPause + concentric + topPause }

    public var isZero: Bool { secondsPerRep == 0 }

    public var notation: String { "\(eccentric)-\(bottomPause)-\(concentric)-\(topPause)" }

    /// Decode une notation `a-b-c-d`. Retourne `nil` si la notation est
    /// invalide : aucune valeur n'est devinee.
    public init?(notation: String) {
        let parts = notation.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var values: [Int] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            // « X » signifie explosif dans la notation usuelle : 0 seconde.
            if trimmed.uppercased() == "X" {
                values.append(0)
                continue
            }
            guard let value = Int(trimmed), (0...60).contains(value) else { return nil }
            values.append(value)
        }
        self.init(eccentric: values[0], bottomPause: values[1], concentric: values[2], topPause: values[3])
    }
}

/// Effort declare sur une serie. RPE et RIR decrivent la meme realite : on
/// stocke ce que l'utilisateur a saisi, sans convertir silencieusement.
public enum EffortRating: Codable, Equatable, Hashable, Sendable {
    case rpe(Double)
    case rir(Int)

    /// RIR equivalent (RPE 10 = 0 RIR). Borne a 0...10.
    public var repsInReserve: Int? {
        switch self {
        case .rir(let value): return max(0, min(10, value))
        case .rpe(let value):
            guard value.isFinite, (1...10).contains(value) else { return nil }
            return max(0, min(10, Int((10 - value).rounded())))
        }
    }

    public var displayText: String {
        switch self {
        case .rpe(let value):
            let rounded = (value * 2).rounded() / 2
            return rounded == rounded.rounded()
                ? "RPE \(Int(rounded))"
                : "RPE \(String(format: "%.1f", rounded))"
        case .rir(let value):
            return "RIR \(value)"
        }
    }

    public var isValid: Bool {
        switch self {
        case .rpe(let value): return value.isFinite && (1...10).contains(value)
        case .rir(let value): return (0...10).contains(value)
        }
    }
}

/// Role d'une serie dans l'exercice.
public enum SetRole: String, Codable, CaseIterable, Sendable {
    case warmup
    case approach
    case working
    case backoff

    public var countsAsWorkingSet: Bool {
        switch self {
        case .working, .backoff: return true
        case .warmup, .approach: return false
        }
    }
}
