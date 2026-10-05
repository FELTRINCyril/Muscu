import SwiftUI

/// Police de taille choisie, mais qui SUIT Dynamic Type.
///
/// `Font.system(size:)` fige la taille : un compteur de séance reste minuscule
/// pour qui a agrandi le texte de son iPhone. `@ScaledMetric` fait varier la
/// valeur avec le réglage système, en gardant la proportion voulue.
///
/// À utiliser pour les chiffres volontairement grands (chronos, compteurs de
/// répétitions). Partout ailleurs, les styles de texte (`.headline`,
/// `.caption`…) suffisent et sont préférables.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight, design: design))
    }
}

extension View {
    func scaledSystemFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo style: Font.TextStyle = .largeTitle
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: style))
    }

    /// Chrono de repos et compteurs plein écran : grande taille monospacée,
    /// qui suit Dynamic Type et se réduit plutôt que de se tronquer.
    func timerFont(size: CGFloat = Theme.timerReferenceSize) -> some View {
        scaledSystemFont(size: size, weight: .bold, design: .monospaced)
            .minimumScaleFactor(0.4)
            .lineLimit(1)
    }
}
