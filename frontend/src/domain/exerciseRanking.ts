/**
 * Which lifts to float to the top of the exercise library.
 *
 * A 700-exercise catalog is mostly other people's exercises. The dozen a person
 * actually trains are the ones they came to find, so those get a section of
 * their own above the alphabet — the rest of the library stays exactly where it
 * was, because "I know it starts with B" is still how you find something new.
 *
 * Pure, so `node --test` covers it.
 */

const DAY = 86400000;

/**
 * Days after which a lift's history counts for half as much.
 *
 * Training changes. A programme you ran hard for three months and dropped in
 * spring shouldn't outrank what you did on Tuesday, and without decay it would
 * — it has far more sessions behind it.
 */
const HALF_LIFE_DAYS = 45;

export type ExerciseUsage = {
  /** Completed sessions containing this exercise. */
  sessions: number;
  /** Epoch ms of the most recent of them. */
  lastAt: number;
};

/**
 * How strongly a lift belongs at the top: how often, faded by how long ago.
 *
 * Zero for anything never trained, which is what keeps untrained exercises out
 * of the section entirely rather than filling it with arbitrary catalog entries.
 */
export function usageScore(usage: ExerciseUsage, now: number): number {
  if (!usage || usage.sessions <= 0 || !usage.lastAt) return 0;
  const days = Math.max(0, (now - usage.lastAt) / DAY);
  return usage.sessions * 2 ** (-days / HALF_LIFE_DAYS);
}

/**
 * The trained lifts, best first, capped at `limit`.
 *
 * Ties break by name so the order is stable: a section that reshuffles between
 * renders is worse than one that's slightly wrong.
 */
export function rankByUsage<T extends { id: string; name: string }>(
  exercises: readonly T[],
  usageById: ReadonlyMap<string, ExerciseUsage>,
  { now, limit }: { now: number; limit: number },
): T[] {
  return exercises
    .map((ex) => ({ ex, score: usageScore(usageById.get(ex.id) ?? { sessions: 0, lastAt: 0 }, now) }))
    .filter((r) => r.score > 0)
    .sort((a, b) => b.score - a.score || a.ex.name.localeCompare(b.ex.name))
    .slice(0, limit)
    .map((r) => r.ex);
}
