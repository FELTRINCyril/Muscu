/**
 * A warm-up ladder up to the first working set (#68).
 *
 * The scheme is the empty bar for reps, then roughly 40 / 60 / 80 / 90% with the
 * reps falling away as the weight climbs. How many rungs depends on how heavy
 * the working set is: 60 kg needs a couple, 200 kg needs the lot.
 *
 * Rounding is injected rather than decided here, because "the nearest weight you
 * can actually load" means something different per equipment — plate maths on a
 * barbell, fixed increments on dumbbells and machines. Pure, so `node --test`
 * covers it.
 */

/** `pct` is null for the bar-only rung, which is a weight rather than a share. */
export type RampRow = { pct: number | null; kg: number; reps: number };

type RampOptions = {
  /** Weight of the first working set, in the user's canonical unit. */
  workingKg: number;
  /** The empty bar, or null for equipment that has no bar to warm up with. */
  barKg?: number | null;
  /** Overrides `defaultWarmupSets`. */
  sets?: number;
  /** Snap a weight to something loadable. Identity is a valid choice. */
  round: (kg: number) => number;
};

/** The ladder, in order. The bar rung is prepended separately when there is one. */
const LADDER: { pct: number; reps: number }[] = [
  { pct: 40, reps: 5 },
  { pct: 60, reps: 3 },
  { pct: 80, reps: 2 },
  { pct: 90, reps: 1 },
];

const BAR_ROW: RampRow = { pct: null, kg: 0, reps: 10 };

/**
 * How many warm-up sets a working weight deserves by default.
 *
 * Light work needs no ramp beyond the bar; heavy work needs the full ladder, and
 * the jump from the last warm-up to the first working set is what these numbers
 * are really controlling.
 */
export function defaultWarmupSets(workingKg: number): number {
  if (workingKg < 40) return 1;
  if (workingKg < 80) return 2;
  if (workingKg < 140) return 4;
  return 5;
}

export function warmupRamp({ workingKg, barKg = null, sets, round }: RampOptions): RampRow[] {
  if (!Number.isFinite(workingKg) || workingKg <= 0) return [];
  // Nothing to ramp toward when the bar already is the working weight.
  if (barKg != null && workingKg <= barKg) return [];

  const wanted = Math.max(1, sets ?? defaultWarmupSets(workingKg));

  const rungs: RampRow[] = barKg != null ? [{ ...BAR_ROW, kg: barKg }] : [];
  for (const step of LADDER) {
    if (rungs.length >= wanted) break;
    rungs.push({ pct: step.pct, kg: round((workingKg * step.pct) / 100), reps: step.reps });
  }

  // A warm-up at or above the working set isn't a warm-up. Rounding can push a
  // rung there on light weights — 90% of 22.5 rounds to 20 against a 20 kg bar,
  // and on a coarser increment it can land on the work set itself.
  const usable = rungs.filter((r) => r.kg > 0 && r.kg < workingKg);

  // Rounding can also collapse two rungs onto one weight. Keep the later one:
  // it carries the lower rep count, which is what that weight is for by then.
  const byWeight = new Map<number, RampRow>();
  for (const r of usable) byWeight.set(r.kg, r);

  return [...byWeight.values()].sort((a, b) => a.kg - b.kg);
}
