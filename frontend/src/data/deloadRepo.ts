/**
 * Gathers the history the deload advisory reasons over (#70).
 *
 * The rules live in `domain/deload`; this only feeds them. It reads a bounded
 * window rather than the whole archive, because the advisory's longest question
 * ("has this lift been flat for three sessions?") never needs more than a few
 * months, and the summary screen runs this the moment a workout ends.
 */
import { and, eq, inArray } from 'drizzle-orm';

import { db } from '../db/client';
import * as schema from '../db/schema';
import { estimated1rm, EST_1RM_MAX_REPS } from '../domain/stats';
import type { ExerciseHistory } from '../domain/deload';

const DAY = 86400000;
/** Enough for a 3-session stall and a 6-week volume baseline, and no more. */
const LOOKBACK_DAYS = 120;
const WEEK = 7 * DAY;

type SetRow = { type: string; weight: number | null; reps: number | null; done: number };

/** Best estimated 1RM in a session, ignoring reps the estimate can't carry. */
function bestOneRm(sets: SetRow[]): number {
  let best = 0;
  for (const s of sets) {
    if (!s.done || s.type === 'warmup') continue;
    if ((s.reps ?? 0) > EST_1RM_MAX_REPS) continue;
    best = Math.max(best, estimated1rm(s.weight, s.reps) ?? 0);
  }
  return best;
}

/**
 * Per-exercise history for the lifts in one workout.
 *
 * Only those lifts: the advisory speaks about the session just finished, so
 * scanning the entire catalog would be work thrown away.
 */
export async function deloadHistoryFor(
  workoutId: string,
  now = Date.now(),
): Promise<{ exercises: ExerciseHistory[]; historyStartedAt: number | null }> {
  const since = now - LOOKBACK_DAYS * DAY;

  const wes = await db
    .select({ exerciseId: schema.workoutExercises.exerciseId })
    .from(schema.workoutExercises)
    .where(eq(schema.workoutExercises.workoutId, workoutId));
  const exerciseIds = [...new Set(wes.map((w) => w.exerciseId))];
  if (exerciseIds.length === 0) return { exercises: [], historyStartedAt: null };

  const rows = await db
    .select({
      exerciseId: schema.workoutExercises.exerciseId,
      workoutId: schema.workouts.id,
      startedAt: schema.workouts.startedAt,
      set: schema.workoutSets,
    })
    .from(schema.workouts)
    .innerJoin(schema.workoutExercises, eq(schema.workoutExercises.workoutId, schema.workouts.id))
    .innerJoin(schema.workoutSets, eq(schema.workoutSets.workoutExerciseId, schema.workoutExercises.id))
    .where(
      and(
        eq(schema.workouts.status, 'completed'),
        inArray(schema.workoutExercises.exerciseId, exerciseIds),
      ),
    );

  // Group into (exercise, session) buckets. One pass; the query above is the
  // only round trip.
  const byExercise = new Map<string, Map<string, { at: number; sets: SetRow[] }>>();
  let earliest: number | null = null;
  for (const r of rows) {
    earliest = earliest === null || r.startedAt < earliest ? r.startedAt : earliest;
    if (r.startedAt < since) continue;
    let sessions = byExercise.get(r.exerciseId);
    if (!sessions) {
      sessions = new Map();
      byExercise.set(r.exerciseId, sessions);
    }
    const found = sessions.get(r.workoutId) ?? { at: r.startedAt, sets: [] };
    found.sets.push(r.set as unknown as SetRow);
    sessions.set(r.workoutId, found);
  }

  const exercises: ExerciseHistory[] = [];
  for (const id of exerciseIds) {
    const sessions = [...(byExercise.get(id)?.values() ?? [])].sort((a, b) => a.at - b.at);
    if (sessions.length === 0) continue;

    // Weekly working-set volume for this lift, oldest first. The advisory reads
    // a ramp off this; whole weeks only, so a part-week at the edge can't read
    // as a collapse in training.
    const weeks: number[] = [];
    const firstWeekStart = now - 8 * WEEK;
    for (let w = 0; w < 8; w += 1) {
      const from = firstWeekStart + w * WEEK;
      const to = from + WEEK;
      let volume = 0;
      for (const s of sessions) {
        if (s.at < from || s.at >= to) continue;
        for (const set of s.sets) {
          if (!set.done || set.type === 'warmup') continue;
          volume += (set.weight ?? 0) * (set.reps ?? 0);
        }
      }
      weeks.push(volume);
    }

    exercises.push({
      exerciseId: id,
      sessions: sessions.map((s) => ({ at: s.at, best1rm: bestOneRm(s.sets) })),
      weeklyVolumes: weeks,
      dismissedAt: null, // filled by the caller from device state
    });
  }

  return { exercises, historyStartedAt: earliest };
}
