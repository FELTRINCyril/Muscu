import SwiftUI
import MuscuEngine

/// Libelle lisible d'un ecart de structure.
enum SessionStructureChangePresentation {
    static func text(for change: SessionStructureChange) -> String {
        switch change {
        case .added(let entry):
            if let sets = entry.setCount {
                return String(localized: "Ajouté : \(entry.displayName) (\(sets) séries)")
            }
            return String(localized: "Ajouté : \(entry.displayName)")
        case .removed(let entry):
            return String(localized: "Retiré : \(entry.displayName)")
        case .replaced(let from, let to):
            return String(localized: "Remplacé : \(from.displayName) → \(to.displayName)")
        case .setCount(let entry, let from, let to):
            return String(localized: "\(entry.displayName) : \(from) → \(to) séries")
        case .measure(let entry, let from, let to):
            return String(localized: "\(entry.displayName) : \(from.displayName) → \(to.displayName)")
        case .moved(let entry):
            return String(localized: "\(entry.displayName) : déplacé")
        }
    }

    static func systemImage(for change: SessionStructureChange) -> String {
        switch change {
        case .added: return "plus.circle"
        case .removed: return "minus.circle"
        case .replaced: return "arrow.left.arrow.right"
        case .setCount: return "number"
        case .measure: return "ruler"
        case .moved: return "arrow.up.arrow.down"
        }
    }
}

/// Fin d'une seance de programme dont la STRUCTURE a change : proposer de
/// reporter ces changements dans le programme, de le garder tel quel, ou
/// d'enregistrer la seance comme nouveau modele. Rien n'est modifie sans un
/// choix explicite. Inspire de l'ecran de resume d'Ischys (MIT).
struct ProgramUpdateCard: View {
    let changes: [SessionStructureChange]
    let onUpdateProgram: () -> Void
    let onKeepProgram: () -> Void
    let onSaveTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundStyle(Theme.accent)
                Text("La séance a changé")
                    .font(.subheadline.weight(.semibold))
            }
            Text("Reporter ces changements dans le programme ? Les charges réalisées ne sont jamais recopiées.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    Label(
                        SessionStructureChangePresentation.text(for: change),
                        systemImage: SessionStructureChangePresentation.systemImage(for: change)
                    )
                    .font(.caption)
                }
            }
            .accessibilityIdentifier("programUpdate.changes")

            VStack(spacing: 8) {
                Button(action: onUpdateProgram) {
                    Text("Mettre à jour la séance du programme")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .accessibilityIdentifier("programUpdate.update")

                Button(action: onSaveTemplate) {
                    Text("Enregistrer comme nouveau modèle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("programUpdate.template")

                Button(action: onKeepProgram) {
                    Text("Garder le programme")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("programUpdate.keep")
            }
            .font(.subheadline)
        }
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("programUpdate.card")
    }
}
