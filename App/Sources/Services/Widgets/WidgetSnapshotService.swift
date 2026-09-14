import Foundation
import SwiftData
import WidgetKit
import MuscuEngine

/// Construit et publie l'instantané que lisent les widgets.
///
/// Les indicateurs viennent de `TrainingAnalytics`, comme les graphiques :
/// un widget ne doit jamais contredire l'écran Progression parce qu'il aurait
/// refait le calcul autrement.
@MainActor
enum WidgetSnapshotService {
    /// Fenêtre affichée par le widget « Semaine ».
    static let windowDays = 7

    /// Recalcule et écrit l'instantané, puis demande au système de
    /// rafraîchir les widgets.
    static func refresh(
        in context: ModelContext,
        catalogStore: CatalogStore? = nil,
        now: Date = .now
    ) {
        let snapshot = makeSnapshot(in: context, catalogStore: catalogStore, now: now)
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func makeSnapshot(
        in context: ModelContext,
        catalogStore: CatalogStore? = nil,
        now: Date = .now
    ) -> WidgetSnapshot {
        let since = Calendar.current.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let recent = AnalyticsBridge.sessions(context: context, catalogStore: catalogStore, since: since)
        let all = AnalyticsBridge.sessions(context: context, catalogStore: catalogStore)

        let programs = ((try? context.fetch(FetchDescriptor<Program>())) ?? []).filter { $0.deletedAt == nil }
        let activeProgram = programs.first(where: \.isActive) ?? programs.first

        let next = nextSession(in: context, program: activeProgram, now: now)

        return WidgetSnapshot(
            generatedAt: now,
            nextSessionName: next.name,
            nextSessionDate: next.date,
            programName: activeProgram?.name,
            sessionsThisWeek: recent.count,
            workingSetsThisWeek: recent.reduce(0) { $0 + $1.sets.filter(\.isWorkingSet).count },
            weeklyStreak: TrainingAnalytics.currentWeeklyStreak(sessions: all, now: now)
        )
    }

    /// Prochaine séance : d'abord le planning daté, à défaut la rotation du
    /// programme actif. On n'invente jamais de date pour cette dernière.
    private static func nextSession(
        in context: ModelContext,
        program: Program?,
        now: Date
    ) -> (name: String?, date: Date?) {
        let planned = PlanningService.scheduledWorkouts(in: context)
            .filter { $0.plannedDate >= now && !$0.state.isSettled }
            .sorted { $0.plannedDate < $1.plannedDate }

        if let first = planned.first {
            return (first.displayName.isEmpty ? "Séance" : first.displayName, first.plannedDate)
        }

        guard let program else { return (nil, nil) }
        let completed = (try? context.fetch(FetchDescriptor<CompletedSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []
        return (HomeView.nextSession(for: program, completedSessions: completed)?.name, nil)
    }

    /// Efface l'instantané : plus rien ne doit s'afficher après une
    /// suppression de données.
    static func clear() {
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
