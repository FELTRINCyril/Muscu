/**
 * Pure volume & strength math — ported from the original server implementation.
 *
 * Rules (from the Ischys Design System):
 * - Warmup sets are **excluded** from volume and working-set counts.
 * - Volume is measured in kilograms. A weighted set contributes `weight × reps`.
 *   A bodyweight set contributes `(bodyweight + added) × reps` when a bodyweight
 *   is known, else 0 — so nothing changes until the user sets their bodyweight.
 * - Only **completed** (`done`) sets count toward a finished workout's stats.
 *
 * No imports beyond `import type` so `node --test` type-stripping can run it.
 */

/**
 * A set's shape for stats. `type` is the set-type string (e.g. 'normal',
 * 'warmup'). `kind` is the movement kind: for `'bodyweight'`, `weight` is the
 * *added* load (null = none, negative = assisted) and the mover's bodyweight is
 * added on top; absent/`'weighted'` uses `weight` directly.
 */
export type SetLike = {
  type: string;
  weight: number | null;
  reps: number | null;
  done: boolean;
  kind?: 'weighted' | 'bodyweight';
};

// The original used banker's rounding, but these values never land on a .5
// tie, so half-away-from-zero matches its numeric outputs exactly.
const round2 = (x: number): number => Math.round(x * 100) / 100;
const round1 = (x: number): number => Math.round(x * 10) / 10;

/**
 * Epley one-rep-max estimate: `weight * (1 + reps/30)`.
 *
 * Returns `null` when weight or reps are missing/non-positive.
 */
export function estimated1rm(weight: number | null, reps: number | null): number | null {
  if (weight === null || reps === null || reps <= 0) return null;
  if (reps === 1) return round2(weight);
  return round2(weight * (1 + reps / 30));
}

/**
 * Kilograms of volume for a single set. `bodyweightKg` is the mover's mass used
 * for bodyweight movements (0 = unknown → they contribute nothing).
 *
 * Zero for warmups, incomplete sets, or sets missing reps (or, for weighted
 * sets, missing weight).
 */
export function setVolume(s: SetLike, bodyweightKg = 0): number {
  if (!s.done || s.type === 'warmup' || s.reps === null) return 0;
  if (s.kind === 'bodyweight') {
    // (bodyweight + added) × reps. A non-positive total load — no bodyweight set
    // and/or an assist that cancels it — contributes nothing.
    const load = bodyweightKg + (s.weight ?? 0);
    return load > 0 ? load * s.reps : 0;
  }
  if (s.weight === null) return 0;
  return s.weight * s.reps;
}

const isWorking = (s: SetLike): boolean => s.done && s.type !== 'warmup';

/** Total kg volume across completed, non-warmup sets. */
export function workoutVolume(sets: SetLike[], bodyweightKg = 0): number {
  return sets.reduce((total, s) => total + setVolume(s, bodyweightKg), 0);
}

/** Number of completed, non-warmup sets (the 'SETS' stat). */
export function countWorkingSets(sets: SetLike[]): number {
  return sets.reduce((n, s) => (isWorking(s) ? n + 1 : n), 0);
}

/**
 * One data point for a per-exercise chart: a session's value for `metric`.
 *
 * Working sets only (warmups excluded), matching the PR definitions so the
 * chart and the record cards agree:
 * - `best_set`    — heaviest working set's weight
 * - `est_1rm`     — max Epley 1RM across working sets
 * - `best_volume` — total working volume for the session
 * - `max_reps`    — most reps in a working set (bodyweight allowed)
 *
 * Returns `null` when the session has nothing to plot for that metric
 * (e.g. bodyweight-only sets for a weight metric), so the caller drops it.
 * An unknown metric falls back to `est_1rm`.
 */
export function sessionMetric(sets: SetLike[], metric: string, bodyweightKg = 0): number | null {
  const working = sets.filter(isWorking);
  if (working.length === 0) return null;

  if (metric === 'best_volume') {
    const vol = working.reduce((total, s) => total + setVolume(s, bodyweightKg), 0);
    return vol > 0 ? round1(vol) : null;
  }

  if (metric === 'max_reps') {
    const reps = working.map((s) => s.reps).filter((r): r is number => r !== null);
    return reps.length ? Math.max(...reps) : null;
  }

  const weighted = working.filter((s) => s.weight !== null && s.reps !== null);
  if (weighted.length === 0) return null;
  if (metric === 'best_set') {
    return round1(Math.max(...weighted.map((s) => s.weight as number)));
  }
  // est_1rm and any unknown metric
  const ones = weighted
    .map((s) => estimated1rm(s.weight, s.reps))
    .filter((o): o is number => o !== null);
  return ones.length ? round1(Math.max(...ones)) : null;
}
