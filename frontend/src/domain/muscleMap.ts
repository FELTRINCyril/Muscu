/**
 * Weighted set counts per body-diagram region over a rolling window, for the
 * muscle map. Distinct from `volumeByMuscle`, which counts one session's
 * primary-muscle sets for the summary: this one spans days, counts secondary
 * work too, and exists to expose **neglect** — what has gone untrained.
 *
 * Pure; node --test runs it.
 */
import { countWorkingSets, type SetLike } from './stats.ts';

/**
 * Regions the diagram can draw. These are catalog muscle names minus the ones
 * that fold into another region (see ALIASES) — a diagram fine enough to
 * separate Soleus from Calves would be drawing detail nobody trains for.
 */
export const MUSCLE_REGIONS = [
  'Chest',
  'Upper Back',
  'Lats',
  'Lower Back',
  'Traps',
  'Front Delts',
  'Side Delts',
  'Rear Delts',
  'Biceps',
  'Triceps',
  'Forearms',
  'Quads',
  'Hamstrings',
  'Glutes',
  'Calves',
  'Adductors',
  'Abs',
  'Obliques',
  'Neck',
] as const;

export type MuscleRegion = (typeof MUSCLE_REGIONS)[number];

/** Catalog muscles with no region of their own, and the region they join. */
const ALIASES: Record<string, MuscleRegion[]> = {
  Soleus: ['Calves'],
  Brachialis: ['Biceps'],
  Serratus: ['Obliques'],
  Abductors: ['Glutes'],
  // The catalog keeps a generic "Shoulders" for exercises that never named a
  // head. Guessing one head would invent detail; splitting evenly keeps the
  // total honest and leaves no head looking neglected on shoulder work alone.
  Shoulders: ['Front Delts', 'Side Delts', 'Rear Delts'],
};

const REGIONS = new Set<string>(MUSCLE_REGIONS);

/** Secondary work is real work, but not a primary's worth of it. */
export const SECONDARY_WEIGHT = 0.5;

/** Weekly-set thresholds; a region below LOW_MAX is barely touched. */
const LOW_MAX = 5;
const MEDIUM_MAX = 10;

/** Below this much history there is no training pattern yet to have a hole in. */
export const NEGLECT_MIN_HISTORY_DAYS = 14;

/**
 * Regions a catalog muscle name lands on: one for most, three for the generic
 * "Shoulders", none for a name the diagram cannot draw (dropped rather than
 * guessed at).
 */
export function regionsFor(muscleName: string): MuscleRegion[] {
  if (REGIONS.has(muscleName)) return [muscleName as MuscleRegion];
  return ALIASES[muscleName] ?? [];
}

/** One workout-exercise: when it happened, what it worked, and its sets. */
export type MuscleWorkEntry = {
  /** Epoch ms of the session. */
  at: number;
  /** Catalog muscle name, or null when the exercise names none. */
  primary: string | null;
  /** Catalog muscle names worked indirectly. */
  secondary?: string[];
  sets: SetLike[];
};

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);

/**
 * Weighted working sets **per week** for each visible region.
 *
 * Dividing the 28-day total by four puts both windows on one scale, so
 * switching window changes the evidence behind a tint, never its meaning.
 * Every visible region is present — an untrained one reads 0, which is the
 * whole point of the map — and hidden ones are absent, not zeroed, so nothing
 * downstream can flag them as neglected.
 *
 * `hidden` takes catalog muscle names or region keys; both resolve through
 * `regionsFor`, so hiding Soleus hides Calves and hiding Shoulders hides all
 * three delts.
 */
export function aggregateMuscleWork(input: {
  entries: MuscleWorkEntry[];
  windowDays: 7 | 28;
  today: Date;
  hidden?: string[];
}): Map<MuscleRegion, number> {
  const { entries, windowDays, today, hidden = [] } = input;

  const hiddenRegions = new Set<MuscleRegion>(hidden.flatMap(regionsFor));
  const totals = new Map<MuscleRegion, number>();
  for (const r of MUSCLE_REGIONS) if (!hiddenRegions.has(r)) totals.set(r, 0);

  // The window is `windowDays` calendar days ending today, local time — the
  // same day-granular reading of "last 7 days" the history heatmap uses.
  const start = addDays(startOfDay(today), -(windowDays - 1)).getTime();

  const add = (muscleName: string, sets: number) => {
    const regions = regionsFor(muscleName);
    if (regions.length === 0) return;
    const share = sets / regions.length;
    for (const r of regions) {
      const current = totals.get(r);
      if (current !== undefined) totals.set(r, current + share);
    }
  };

  for (const e of entries) {
    if (startOfDay(new Date(e.at)).getTime() < start) continue;
    const sets = countWorkingSets(e.sets);
    if (sets === 0) continue;
    if (e.primary !== null) add(e.primary, sets);
    for (const m of e.secondary ?? []) add(m, sets * SECONDARY_WEIGHT);
  }

  const weeks = windowDays / 7;
  for (const [r, total] of totals) totals.set(r, total / weeks);
  return totals;
}

export type MuscleTint = 'none' | 'low' | 'medium' | 'high';

/** Tint band for a region, by weighted sets per week. */
export function tintFor(setsPerWeek: number): MuscleTint {
  if (setsPerWeek <= 0) return 'none';
  if (setsPerWeek < LOW_MAX) return 'low';
  if (setsPerWeek < MEDIUM_MAX) return 'medium';
  return 'high';
}

/**
 * Whether to outline a region as neglected.
 *
 * Only ever true for zero work: a thin week is a choice, an empty one on a
 * user with a real history is a hole. `historyDays` gates it so a brand-new
 * user is not told they have neglected their entire body, and `hidden` wins
 * outright — a muscle the user removed from the map cannot be nagged about.
 */
export function isNeglected(setsPerWeek: number, historyDays: number, hidden: boolean): boolean {
  if (hidden) return false;
  return setsPerWeek <= 0 && historyDays >= NEGLECT_MIN_HISTORY_DAYS;
}
