import SwiftUI

// Palette de theme sombre pour l'app Muscu.
enum Theme {
    // Vert energique, couleur d'accent principale.
    static let accent = Color(red: 0.20, green: 0.84, blue: 0.29)

    // Noir profond, fond principal des ecrans.
    static let background = Color(red: 0.063, green: 0.063, blue: 0.078)

    // Gris fonce, fond des cartes/panneaux.
    static let card = Color(red: 0.13, green: 0.13, blue: 0.15)

    // Police geante monospace pour le decompte du chrono de repos. Reduite
    // de 88 a 72 : a 88, "MM:SS" (ex: "12:34") depassait la largeur
    // disponible dans l'anneau de 260 pt et retombait sur deux lignes
    // malgre minimumScaleFactor (le texte n'avait jamais l'occasion de se
    // reduire suffisamment avant d'etre tronque).
    static let timerFont = Font.system(size: 72, weight: .bold, design: .monospaced)
}
