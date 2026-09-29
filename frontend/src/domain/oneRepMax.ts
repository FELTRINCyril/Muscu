/**
 * The training table behind the 1RM calculator (#71).
 *
 * The estimate itself comes from `estimated1rm` in domain/stats, deliberately —
 * a calculator that disagreed with the EST. 1RM record would make one of them a
 * lie. This adds the two things the record doesn't need: what share of the
 * estimate to load for a given percentage, and how much to trust the whole
 * thing.
 */
import { EST_1RM_MAX_REPS } from './stats.ts';

/**
 * How much the estimate is worth, by the rep count it came from.
 *
 * Epley is fitted to low-rep sets. Past about ten reps the result says more
 * about someone's tolerance for discomfort than their one-rep max, so the UI
 * marks it rather than quietly presenting the same confident number.
 */
export type EstimateTier = 'close' | 'reasonable' | 'rough';

export function estimateTier(reps: number): EstimateTier | null {
  if (!Number.isFinite(reps) || reps < 1) return null;
  if (reps <= 5) return 'close';
  if (reps <= EST_1RM_MAX_REPS) return 'reasonable';
  return 'rough';
}

/**
 * Below this share, reading a load back as a rep count stops meaning anything —
 * the same weakness as estimating upward from high reps, in reverse.
 */
const REPS_SHOWN_ABOVE_PCT = 75;

const PERCENTAGES = [100, 95, 90, 85, 80, 75, 70, 65, 60, 55, 50];

/** Epley rearranged: how many reps a load is worth against an estimate. */
export function repsAtLoad(oneRmKg: number, loadKg: number): number | null {
  if (!(oneRmKg > 0) || !(loadKg > 0)) return null;
  return Math.max(1, Math.round(30 * (oneRmKg / loadKg - 1) + 1e-9));
}

export type PercentageRow = { pct: number; kg: number; reps: number | null };

/**
 * Loads for each training percentage of an estimate.
 *
 * `round` snaps a load to something the user can actually put on the bar; reps
 * are then read back from the ROUNDED load, so the row is self-consistent — a
 * table that says "97.5 kg ≈ 3 reps" when 3 reps belongs to 100 kg is worse
 * than no reps column.
 */
export function percentageTable(
  oneRmKg: number,
  { round }: { round: (kg: number) => number },
): PercentageRow[] {
  if (!Number.isFinite(oneRmKg) || oneRmKg <= 0) return [];
  return PERCENTAGES.map((pct) => {
    const kg = round((oneRmKg * pct) / 100);
    return {
      pct,
      kg,
      reps: pct >= REPS_SHOWN_ABOVE_PCT ? repsAtLoad(oneRmKg, kg) : null,
    };
  });
}
