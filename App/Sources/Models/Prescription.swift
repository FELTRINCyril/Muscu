import Foundation

enum SetFormat: String, Codable {
    case classic
    case pyramid
    case intervals
    case amrap
}

extension PrescribedExercise {
    var format: SetFormat {
        get { SetFormat(rawValue: formatRaw) ?? .classic }
        set { formatRaw = newValue.rawValue }
    }
}
