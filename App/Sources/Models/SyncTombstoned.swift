import Foundation

/// Conformités à `SyncTombstoned`, une par modèle portant une suppression
/// logique.
///
/// Elles sont déclarées ici plutôt que sur chaque modèle pour que la liste
/// soit lisible d'un coup d'œil : si un nouveau modèle synchronisé n'y
/// figure pas, `TombstonePurge` ne pourra pas l'oublier silencieusement —
/// il ne compilera pas dans la liste de purge. Un test vérifie en plus que
/// la couverture est complète.

extension ActiveWorkout: SyncTombstoned {}
extension AdaptationEntry: SyncTombstoned {}
extension AthleteProfile: SyncTombstoned {}
extension BodyMeasurement: SyncTombstoned {}
extension CalendarLink: SyncTombstoned {}
extension CompletedSession: SyncTombstoned {}
extension CompletedSet: SyncTombstoned {}
extension CustomExercise: SyncTombstoned {}
extension ExerciseCollection: SyncTombstoned {}
extension ExerciseGroup: SyncTombstoned {}
extension ExerciseLibraryEntry: SyncTombstoned {}
extension ExerciseRecord: SyncTombstoned {}
extension HealthWorkoutLink: SyncTombstoned {}
extension PersonalBest: SyncTombstoned {}
extension PlaceProfile: SyncTombstoned {}
extension PlanningSchedule: SyncTombstoned {}
extension PrescribedExercise: SyncTombstoned {}
extension Program: SyncTombstoned {}
extension ProgramSession: SyncTombstoned {}
extension ProgressPhoto: SyncTombstoned {}
extension ReadinessEntry: SyncTombstoned {}
extension ScheduledWorkout: SyncTombstoned {}
extension SessionTemplate: SyncTombstoned {}
extension TrainingBlock: SyncTombstoned {}
extension TrainingGoal: SyncTombstoned {}
extension TrainingPlan: SyncTombstoned {}
extension TrainingWeek: SyncTombstoned {}
