import Foundation

/// Mapping statique EN -> FR pour l'affichage des valeurs du catalogue.
/// Cle inconnue -> cle capitalisee telle quelle.
public enum FrenchLabels {
    public static func muscle(_ key: String) -> String {
        label(for: key, in: muscles)
    }

    public static func equipment(_ key: String) -> String {
        label(for: key, in: equipments)
    }

    public static func category(_ key: String) -> String {
        label(for: key, in: categories)
    }

    public static func level(_ key: String) -> String {
        label(for: key, in: levels)
    }

    private static func label(for key: String, in table: [String: String]) -> String {
        table[key] ?? capitalizedFirstLetterOnly(key)
    }

    private static func capitalizedFirstLetterOnly(_ key: String) -> String {
        guard let first = key.first else { return key }
        return first.uppercased() + key.dropFirst()
    }

    private static let muscles: [String: String] = [
        "abdominals": "Abdominaux",
        "abductors": "Abducteurs",
        "adductors": "Adducteurs",
        "biceps": "Biceps",
        "calves": "Mollets",
        "chest": "Pectoraux",
        "forearms": "Avant-bras",
        "glutes": "Fessiers",
        "hamstrings": "Ischio-jambiers",
        "lats": "Dorsaux",
        "lower back": "Bas du dos",
        "middle back": "Milieu du dos",
        "neck": "Nuque",
        "quadriceps": "Quadriceps",
        "shoulders": "Épaules",
        "traps": "Trapèzes",
        "triceps": "Triceps",
    ]

    private static let equipments: [String: String] = [
        "bands": "Élastiques",
        "barbell": "Barre",
        "body only": "Poids du corps",
        "cable": "Poulie",
        "dumbbell": "Haltères",
        "e-z curl bar": "Barre EZ",
        "exercise ball": "Swiss ball",
        "foam roll": "Rouleau de massage",
        "kettlebells": "Kettlebells",
        "machine": "Machine",
        "medicine ball": "Médecine ball",
        "other": "Autre",
    ]

    private static let categories: [String: String] = [
        "cardio": "Cardio",
        "olympic weightlifting": "Haltérophilie",
        "plyometrics": "Pliométrie",
        "powerlifting": "Force athlétique",
        "strength": "Renforcement",
        "stretching": "Étirements",
        "strongman": "Strongman",
    ]

    private static let levels: [String: String] = [
        "beginner": "Débutant",
        "expert": "Expert",
        "intermediate": "Intermédiaire",
    ]
}
