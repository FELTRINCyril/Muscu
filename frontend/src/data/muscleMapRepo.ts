/**
 * Feeds the body diagram (#66).
 *
 * `volumeByMuscle` already counts primaries for a single workout's summary;
 * this reads a window across workouts and carries secondaries too, because the
 * diagram is answering "what have I neglected", and a muscle worked hard as a
 * secondary all month has not been neglected.
 */
import { and, eq, gte, inArray } from 'drizzle-orm';

import { db } from '../db/client';
import * as schema from '../db/schema';
import type { MuscleWorkEntry } from '../domain/muscleMap';

const DAY = 86400000;

/**
 * One entry per (workout, exercise) in the window, with the muscles it worked.
 *
 * Five queries regardless of how much history there is — the joins are done in
 * memory rather than per row, since the diagram is rendered on the Profile tab
 * and must not stall it.
 */
export async function muscleWorkEntries(windowDays: number, now = Date.now()): Promise<{
  entries: MuscleWorkEntry[];
  historyDays: number;
}> {
  const since = now - windowDays * DAY;

  const workouts = (await db
    .select({ id: schema.workouts.id, startedAt: schema.workouts.startedAt })
    .from(schema.workouts)
    .where(and(eq(schema.workouts.status, 'completed'), gte(schema.workouts.startedAt, since)))) as {
    id: string;
    startedAt: number;
  }[];

  // History length decides whether an untouched muscle counts as neglected: a
  // brand-new user has not neglected anything.
  const firstRow = (await db
    .select({ startedAt: schema.workouts.startedAt })
    .from(schema.workouts)
    .where(eq(schema.workouts.status, 'completed'))) as { startedAt: number }[];
  const earliest = firstRow.reduce<number | null>(
    (min, w) => (min === null || w.startedAt < min ? w.startedAt : min),
    null,
  );
  const historyDays = earliest === null ? 0 : Math.floor((now - earliest) / DAY);

  if (workouts.length === 0) return { entries: [], historyDays };
  const startedById = new Map(workouts.map((w) => [w.id, w.startedAt]));

  const wes = await db
    .select()
    .from(schema.workoutExercises)
    .where(inArray(schema.workoutExercises.workoutId, [...startedById.keys()]));
  if (wes.length === 0) return { entries: [], historyDays };

  const sets = await db
    .select()
    .from(schema.workoutSets)
    .where(inArray(schema.workoutSets.workoutExerciseId, wes.map((w) => w.id)));
  const setsByWe = new Map<string, typeof sets>();
  for (const s of sets) {
    const list = setsByWe.get(s.workoutExerciseId) ?? [];
    list.push(s);
    setsByWe.set(s.workoutExerciseId, list);
  }

  const exerciseIds = [...new Set(wes.map((w) => w.exerciseId))];
  const exRows = await db
    .select()
    .from(schema.exercises)
    .where(inArray(schema.exercises.id, exerciseIds));
  const exById = new Map(exRows.map((e) => [e.id, e]));

  const muscleRows = await db.select().from(schema.muscles);
  const muscleName = new Map(muscleRows.map((m) => [m.id, m.name]));

  const links = await db
    .select()
    .from(schema.exerciseSecondaryMuscles)
    .where(inArray(schema.exerciseSecondaryMuscles.exerciseId, exerciseIds));
  const secondaryByExercise = new Map<string, string[]>();
  for (const l of links) {
    const name = muscleName.get(l.muscleId);
    if (!name) continue;
    const list = secondaryByExercise.get(l.exerciseId) ?? [];
    list.push(name);
    secondaryByExercise.set(l.exerciseId, list);
  }

  const entries: MuscleWorkEntry[] = [];
  for (const we of wes) {
    const at = startedById.get(we.workoutId);
    const ex = exById.get(we.exerciseId);
    if (at == null || !ex) continue;
    entries.push({
      at,
      primary: ex.primaryMuscleId ? (muscleName.get(ex.primaryMuscleId) ?? null) : null,
      secondary: secondaryByExercise.get(we.exerciseId) ?? [],
      sets: (setsByWe.get(we.id) ?? []).map((s) => ({
        type: s.type,
        weight: s.weight,
        reps: s.reps,
        done: s.done !== 0,
      })),
    });
  }

  return { entries, historyDays };
}
