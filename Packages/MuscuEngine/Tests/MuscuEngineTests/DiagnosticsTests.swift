import Foundation
import Testing
@testable import MuscuEngine

@Suite("Journal de diagnostic")
struct DiagnosticsTests {
    private let reference = Date(timeIntervalSince1970: 1_760_000_000)

    @Test("Une adresse e-mail n'apparait jamais dans un journal")
    func redactsEmail() {
        let text = DiagnosticRedactor.redact("Echec pour cyril@gemaddis.com lors de l'envoi")
        #expect(!text.contains("@gemaddis.com"))
        #expect(!text.contains("cyril"))
        #expect(text.contains(DiagnosticRedactor.placeholder))
    }

    @Test("Une cle d'API recopiee dans une erreur est masquee")
    func redactsToken() {
        // Jeton entierement fabrique. Volontairement sans le prefixe d'un
        // vrai fournisseur : une chaine qui RESSEMBLE a une cle bloquerait
        // la publication du depot par les analyseurs de secrets, alors que
        // le test porte sur la forme (long, lettres ET chiffres), pas sur
        // le prefixe.
        let fake = "jeton0A1b2C3d4E5f6G7h8I9j0K1l2M3n4"
        let text = DiagnosticRedactor.redact("401 refuse avec \(fake)")
        #expect(!text.contains(fake))
        #expect(text.contains("401"))
    }

    @Test("Le nom de compte d'un chemin est masque, pas le chemin")
    func redactsHomePath() {
        let text = DiagnosticRedactor.redact("Fichier absent : /Users/cyrilfeltrin/Documents/export.json")
        #expect(!text.contains("cyrilfeltrin"))
        #expect(text.contains("/Documents/export.json"))
    }

    @Test("Un identifiant interne reste lisible : il sert au diagnostic")
    func keepsUUID() {
        let identifier = "3E2C1A44-6E44-4B1E-9C2A-2E7C4B2A1D55"
        let text = DiagnosticRedactor.redact("Conflit sur \(identifier)")
        #expect(text.contains(identifier))
    }

    @Test("Une suite de chiffres assez longue est masquee")
    func redactsLongNumber() {
        let text = DiagnosticRedactor.redact("Rappel vers 0612345678 impossible")
        #expect(!text.contains("0612345678"))
        // Une valeur courte reste visible : un code d'erreur est utile.
        #expect(DiagnosticRedactor.redact("Code 4023").contains("4023"))
    }

    @Test("L'expurgation s'applique a la construction de l'evenement")
    func eventRedactsOnInit() {
        let event = DiagnosticEvent(
            date: reference,
            category: .sync,
            level: .failure,
            code: "sync.push.failed",
            detail: "refuse pour cyril@gemaddis.com"
        )
        #expect(!event.detail.contains("@"))
    }

    @Test("Le journal est borne et garde le plus recent")
    func bufferIsBounded() {
        var buffer = DiagnosticsBuffer(capacity: 3)
        for index in 0..<10 {
            buffer.append(
                DiagnosticEvent(
                    date: reference.addingTimeInterval(Double(index)),
                    category: .store,
                    level: .info,
                    code: "evenement.\(index)"
                )
            )
        }
        #expect(buffer.events.count == 3)
        #expect(buffer.events.first?.code == "evenement.9")
        #expect(buffer.events.last?.code == "evenement.7")
    }

    @Test("Le journal compte les echecs et filtre par categorie")
    func bufferCounts() {
        var buffer = DiagnosticsBuffer()
        buffer.append(DiagnosticEvent(date: reference, category: .sync, level: .failure, code: "a"))
        buffer.append(DiagnosticEvent(date: reference, category: .store, level: .info, code: "b"))
        buffer.append(DiagnosticEvent(date: reference, category: .sync, level: .warning, code: "c"))
        #expect(buffer.failureCount == 1)
        #expect(buffer.events(in: .sync).count == 2)
        buffer.removeAll()
        #expect(buffer.events.isEmpty)
    }

    @Test("Un journal vide reste exportable")
    func emptyReport() {
        let text = DiagnosticReportBuilder.text(
            environment: environment,
            health: health,
            events: [],
            generatedAt: reference
        )
        #expect(text.contains("Aucun événement enregistré."))
    }

    @Test("Le rapport porte versions, compteurs et dates, jamais de donnee metier")
    func reportHasNoBusinessData() {
        let events = [
            DiagnosticEvent(
                date: reference,
                category: .transfer,
                level: .failure,
                code: "import.csv.rejected",
                // Un appelant distrait recopie une ligne du fichier importe.
                detail: "ligne 12 refusee pour cyril@gemaddis.com"
            )
        ]
        let text = DiagnosticReportBuilder.text(
            environment: environment,
            health: health,
            events: events,
            generatedAt: reference
        )

        #expect(text.contains("0.1.0"))
        #expect(text.contains("Opérations en attente : 4"))
        #expect(text.contains("import.csv.rejected"))
        #expect(!text.contains("cyril@gemaddis.com"))
        // Aucun nom d'exercice, de programme ou de mesure n'est jamais
        // transmis au constructeur : le rapport ne peut pas en contenir.
        #expect(!text.lowercased().contains("squat"))
    }

    private var environment: DiagnosticEnvironment {
        DiagnosticEnvironment(
            applicationVersion: "0.1.0",
            buildNumber: "1",
            systemName: "iOS",
            systemVersion: "18.0",
            deviceModel: "iPhone17,1",
            localeIdentifier: "fr_FR"
        )
    }

    private var health: DiagnosticStoreHealth {
        DiagnosticStoreHealth(
            schemaVersion: 5,
            migrationSucceeded: true,
            entityCounts: ["CompletedSession": 128],
            pendingSyncOperations: 4,
            unresolvedConflicts: 1,
            lastSyncSuccess: reference,
            lastBackup: reference
        )
    }
}
