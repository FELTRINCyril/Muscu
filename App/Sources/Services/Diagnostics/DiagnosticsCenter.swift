import Foundation
import SwiftData
import UIKit
import MuscuEngine

/// Point d'entrée unique du journal de diagnostic local.
///
/// Trois garanties, exigées par la roadmap :
/// 1. **Borné** — `DiagnosticsBuffer` ne dépasse jamais sa capacité.
/// 2. **Expurgé** — chaque détail traverse `DiagnosticRedactor`.
/// 3. **Désactivable** — quand le journal est éteint, `record` ne fait rien
///    ET les lignes déjà écrites sont effacées : couper le journal doit
///    aussi effacer ce qu'il a retenu, sinon la désactivation ne veut rien
///    dire.
///
/// Rien ne part sur le réseau : l'export est un partage volontaire.
@MainActor
enum DiagnosticsCenter {
    private static let bufferKey = "diagnostics.buffer"
    private static let enabledKey = "diagnostics.enabled"

    /// Le journal est actif par défaut : sans lui, un échec vécu par
    /// l'utilisateur ne laisse aucune trace exploitable. Il ne contient
    /// aucune donnée d'entraînement, et se coupe en un geste.
    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { clear() }
        }
    }

    static var buffer: DiagnosticsBuffer {
        guard let data = UserDefaults.standard.data(forKey: bufferKey),
              let value = try? JSONDecoder().decode(DiagnosticsBuffer.self, from: data) else {
            return DiagnosticsBuffer()
        }
        return value
    }

    static var events: [DiagnosticEvent] { buffer.events }

    static func record(
        _ category: DiagnosticCategory,
        _ level: DiagnosticLevel,
        code: String,
        detail: String = "",
        now: Date = .now
    ) {
        guard isEnabled else { return }
        var current = buffer
        current.append(
            DiagnosticEvent(date: now, category: category, level: level, code: code, detail: detail)
        )
        save(current)
    }

    /// Raccourci pour les `catch` : l'erreur système est journalisée telle
    /// quelle, l'expurgation se charge de ce qu'elle pourrait contenir.
    static func record(_ category: DiagnosticCategory, code: String, error: Error, now: Date = .now) {
        record(category, .failure, code: code, detail: error.localizedDescription, now: now)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bufferKey)
    }

    /// Remet le journal dans son état d'origine (utilisé par `--uitest-reset`).
    static func reset() {
        UserDefaults.standard.removeObject(forKey: bufferKey)
        UserDefaults.standard.removeObject(forKey: enabledKey)
    }

    private static func save(_ buffer: DiagnosticsBuffer) {
        guard let data = try? JSONEncoder().encode(buffer) else { return }
        UserDefaults.standard.set(data, forKey: bufferKey)
    }

    // MARK: - Environnement

    static var environment: DiagnosticEnvironment {
        let info = Bundle.main.infoDictionary
        return DiagnosticEnvironment(
            applicationVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: info?["CFBundleVersion"] as? String ?? "?",
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: hardwareIdentifier,
            localeIdentifier: Locale.current.identifier
        )
    }

    /// Modèle matériel générique (`iPhone17,1`). Surtout pas
    /// `UIDevice.current.name` : ce nom contient très souvent un prénom.
    private static var hardwareIdentifier: String {
        var system = utsname()
        uname(&system)
        let mirror = Mirror(reflecting: system.machine)
        let characters = mirror.children.compactMap { child -> Character? in
            guard let value = child.value as? Int8, value != 0 else { return nil }
            return Character(UnicodeScalar(UInt8(bitPattern: value)))
        }
        let identifier = String(characters)
        return identifier.isEmpty ? "inconnu" : identifier
    }
}
