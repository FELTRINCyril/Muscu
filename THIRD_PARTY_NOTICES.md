# Third-party notices

## free-exercise-db

Muscu uses exercise metadata and image paths derived from
[yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db), pinned
to revision `b0eed061e1c832b3ed815fbaa4b45b3cdc14df49`.

The upstream repository describes the dataset as public domain and publishes
it under [The Unlicense](https://github.com/yuhonas/free-exercise-db/blob/b0eed061e1c832b3ed815fbaa4b45b3cdc14df49/LICENSE.md).

French exercise names and instructions in Muscu are adaptations maintained by
this project. Before commercial distribution, the publisher should retain a
copy of the upstream licence and independently verify that every supplied image
is covered by the upstream public-domain declaration.

## Ischys (MIT)

Adapted from Ischys (`frontend/src/domain/plateMath.ts`, `domain/previous.ts`):
plate calculator algorithm (bounded subset sum in integer thousandths, heaviest-plate-first preference) and the per-set previous value idea. Used in
`Packages/MuscuEngine/Sources/MuscuEngine/Places/PlateMath.swift` and
`Packages/MuscuEngine/Sources/MuscuEngine/Runner/PreviousPerformance.swift`.

Adapted from Ischys (`frontend/src/domain/routineDiff.ts`, `domain/importedRoutines.ts`,
`domain/exerciseNaming.ts`, `components/ShareWorkoutSheet.tsx`, `app/summary/[id].tsx`):
structure-only routine diff with longest-common-subsequence move detection,
imported-title grouping (case/whitespace-insensitive, newest spelling, suffixed
unique names), equipment parsed from a trailing parenthetical, and the
share-as-text-or-card / update-the-routine prompts. Used in
`Packages/MuscuEngine/Sources/MuscuEngine/History/SessionStructureDiff.swift`,
`Packages/MuscuEngine/Sources/MuscuEngine/Interop/ImportedRoutines.swift`,
`Packages/MuscuEngine/Sources/MuscuEngine/Interop/ExerciseNaming.swift`,
`App/Sources/Services/SessionShareSummary.swift` and
`App/Sources/Features/Workout/ProgramUpdateCard.swift`.

Inspired by Ischys (`frontend/modules/live-activity/ios/WorkoutIntents.swift`,
`WorkoutAttributes.swift`, `targets/ischys-widget/WorkoutLiveActivity.swift`):
interactive Live Activity buttons as `LiveActivityIntent`s compiled into both
the app and the widget extension, guarded by the identifier of the set on
screen. Rewritten for Muscu (no code copied) in `Shared/LiveActivityIntents.swift`,
`Widgets/WorkoutLiveActivity.swift` and
`Packages/MuscuEngine/Sources/MuscuEngine/Runner/LiveActivityPlanning.swift`.

Adapted from Ischys (`frontend/targets/ischys-watch/WorkoutManager.swift`,
`PhoneLink.swift`, `ischysWatchApp.swift`, `RestView.swift`,
`ActiveSetView.swift`): the Watch workout session lifecycle
(`HKWorkoutSession` + `HKLiveWorkoutBuilder`, phone-launched workouts through
`WKApplicationDelegate.handle(_:)`, orphaned session recovery, discard instead
of save), the phone-owns-the-state mirror with commands sent back over
WatchConnectivity, live metrics pushed to the phone, and the rest banner /
Digital Crown set layout. Rewritten for Muscu (state ownership, set identity
guard, single Health host, set linking) in `Watch/WatchHealthSession.swift`,
`Watch/WatchConnectivityService.swift`, `Watch/WatchMirrorView.swift` and
`Shared/WatchMirror.swift`.

Adapted from Ischys (`frontend/src/lib/mergeDuplicates.ts`,
`app/merge-duplicates.tsx`, `src/domain/exerciseRanking.ts`): duplicate
exercise detection reasons (same normalized name, shared import identity,
similar name gated by equipment and muscles, token subset), survivor choice
(catalog first, then more history), best-of record reconciliation with ties
kept by the survivor, per-pair manual confirmation, and the frequency ×
recency "usual exercises" ranking with exponential half-life decay. Rewritten
for Muscu (catalog entries are never merged, only targets; merged exercises
are redirected rather than deleted; Damerau-Levenshtein and the existing
import naming convention; half-life of 30 days summed per session) in
`Packages/MuscuEngine/Sources/MuscuEngine/Library/DuplicateExercises.swift`,
`Library/ExerciseMerge.swift`, `Library/ExerciseRanking.swift`,
`App/Sources/Services/ExerciseMergeService.swift` and
`App/Sources/Features/Exercises/MergeDuplicatesView.swift`.

```
MIT License

Copyright (c) 2026 Ischys

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## UpLift / strength-training (MIT)

Adapted from UpLift (`Views/Workout/PrevSessionsStripData.swift`, `PrevSessionsStrip.swift`):
grouping of previous sessions by consecutive load and relative age buckets, in
`Packages/MuscuEngine/Sources/MuscuEngine/Runner/PreviousPerformance.swift` and
`App/Sources/Features/Workout/LiveSessionViews.swift`. Converted from pounds to the profile unit.

Adapted from UpLift (`Views/Workout/EffortRatingView.swift`, `Services/EffortScale.swift`):
session effort rating as ten bars of increasing height selected by tapping or
dragging, with green-to-red effort bands, in
`App/Sources/Features/Workout/EffortRatingView.swift` and
`Packages/MuscuEngine/Sources/MuscuEngine/Runner/SessionEffort.swift`. Bands
refined to six labels (very easy to maximal) and made optional and accessible.

Adapted from UpLift (`Services/HealthKitWorkoutService.swift`,
`Views/Workout/LiveHealthKitCard.swift`): live `HKWorkoutSession` /
`HKLiveWorkoutBuilder` on iPhone (start, pause, resume, end, discard), reading
heart rate and active energy from the builder statistics, relating the
workout effort score to the saved workout, and the compact live heart rate /
calories / elapsed card. Used in
`App/Sources/Services/Health/LiveHealthWorkoutController.swift`,
`App/Sources/Services/Health/HealthStore.swift` and
`App/Sources/Features/Health/HealthCardioViews.swift`. Reworked for iOS 18
deployment (iOS 26+ availability checks, Mac Catalyst excluded), crash
recovery (`recoverActiveWorkoutSession`), linking to the existing duplicate
protection, and hiding the heart rate instead of showing zero.

Inspired by UpLift (`ViewModels/ProgressDashboardViewModel.swift`,
`Views/Progress/PRsThisMonthCard.swift`, `progression-lab/Simulation/ReplayEngine.swift`):
the strength score as a sum of best estimated one-rep maxes with a trend
against the previous period, the "PRs this month" card, and replaying the
progression algorithm over a history with the history available before each
session. Rewritten for Muscu in kilograms (no code copied) with the existing
`SetMetrics` eligibility rules, a ±1 % neutral zone, explicit exclusion of
exercises without data, and a deterministic simulated athlete with safety
invariants, in
`Packages/MuscuEngine/Sources/MuscuEngine/Analytics/StrengthDashboard.swift`,
`Packages/MuscuEngine/Sources/MuscuEngine/Programming/ProgressionReplay.swift`
and `App/Sources/Features/Progress/ChartsView.swift`.

```
MIT License

Copyright (c) 2025 Daniel Kuhlwein

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Ideas only (GPL-3.0, no code)

Iron and Skulpt are GPL-3.0 licensed. Muscu reuses **ideas only** from them,
never code: automatic daily backups with rotation and restore (Iron), and
per-exercise relative strength, average intensity and average load
statistics (Skulpt). These features were written from scratch in
`Packages/MuscuEngine/Sources/MuscuEngine/Backup/AutoBackupPolicy.swift`,
`App/Sources/Services/AutoBackupService.swift`,
`Packages/MuscuEngine/Sources/MuscuEngine/Analytics/ExerciseStatistics.swift`
and `App/Sources/Features/Exercises/ExerciseInsightsViews.swift`.
