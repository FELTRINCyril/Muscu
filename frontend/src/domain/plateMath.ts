/**
 * What to hang on the bar to make a target weight.
 *
 * Only barbell work has plate maths — dumbbells and machines come in whatever
 * increments they come in — so the caller decides whether to ask at all.
 *
 * Everything is computed in grams. Plate sets are full of quarters and halves
 * (1.25, 2.5, 37.5…), and in floating point 20 + 1.25 * 2 is not reliably 22.5;
 * a calculator that occasionally says a loadable weight isn't loadable is worse
 * than no calculator. Grams are exact for every plate anyone sells.
 */

/** `count` is how many PAIRS the gym has — plates are loaded symmetrically. */
export type PlatePair = { kg: number; count: number };
export type BarSetup = { barKg: number; pairs: PlatePair[] };

/** Plates for ONE side, heaviest first. `n` is how many of that plate per side. */
export type PlateStack = { kg: number; n: number }[];
export type PlateLoad = { totalKg: number; perSideKg: number; plates: PlateStack };

/**
 * `below`/`above` are the nearest loadable weights either side of a target that
 * can't be made. Either is null when the gym has nothing in that direction.
 */
export type PlateSolution =
  | { kind: 'exact'; load: PlateLoad }
  | { kind: 'rounded'; below: PlateLoad | null; above: PlateLoad | null; stepKg: number }
  | { kind: 'below-bar'; barKg: number };

/** A common commercial kg set. Counts are "enough that they never bind". */
export const DEFAULT_BAR_SETUP: BarSetup = {
  barKg: 20,
  pairs: [
    { kg: 25, count: 8 },
    { kg: 20, count: 8 },
    { kg: 15, count: 8 },
    { kg: 10, count: 8 },
    { kg: 5, count: 8 },
    { kg: 2.5, count: 8 },
    { kg: 1.25, count: 8 },
  ],
};

const g = (kg: number) => Math.round(kg * 1000);
const kg = (grams: number) => grams / 1000;

/**
 * The smallest amount the bar can move: the lightest available plate, doubled
 * because it goes on both ends. This is the number to quote when a target is
 * unloadable — "the smallest plate is 1.25 kg, so it goes up in 2.5 kg steps"
 * explains the gap in a way the rounded weights alone don't.
 */
export function smallestStepKg(setup: BarSetup): number {
  const usable = setup.pairs.filter((p) => p.count > 0 && p.kg > 0);
  if (usable.length === 0) return 0;
  return Math.min(...usable.map((p) => p.kg)) * 2;
}

/**
 * Every per-side weight this inventory can make, mapped to the plates that make
 * it — a bounded subset sum, keeping the heaviest-plates-first stack for each
 * reachable total.
 *
 * Not greedy. Greedy is right for a full commercial set and wrong the moment a
 * gym runs out: with one each of 20/15/10, greedy takes the 20 for a 25 kg side
 * and is stuck, while 15 + 10 sits right there.
 */
function reachable(setup: BarSetup): Map<number, PlateStack> {
  const pairs = setup.pairs
    .filter((p) => p.count > 0 && p.kg > 0)
    .slice()
    .sort((a, b) => b.kg - a.kg);

  let sums = new Map<number, PlateStack>([[0, []]]);
  for (const pair of pairs) {
    const next = new Map(sums);
    for (const [sum, stack] of sums) {
      for (let n = 1; n <= pair.count; n += 1) {
        const total = sum + g(pair.kg) * n;
        const rival = next.get(total);
        if (!rival || prefers([...stack, { kg: pair.kg, n }], rival)) {
          next.set(total, [...stack, { kg: pair.kg, n }]);
        }
      }
    }
    sums = next;
  }
  return sums;
}

/**
 * Which of two stacks making the same weight a lifter would rather load.
 *
 * Compare the plates in descending order and take the first that differs, so
 * 25 + 15 beats 20 + 20 and 25 + 25 + 10 beats 25 + 20 + 15. That is what people
 * actually do: reach for the biggest plate that still fits, because it's fewer
 * plates to handle and it's what the bar looks like in every gym.
 *
 * Arriving at the same weight with fewer plates wins ties, since a stack that
 * ran out of plates to compare has nothing left to add.
 */
function prefers(a: PlateStack, b: PlateStack): boolean {
  const expand = (s: PlateStack) => s.flatMap((p) => Array<number>(p.n).fill(p.kg));
  const x = expand(a);
  const y = expand(b);
  for (let i = 0; i < Math.min(x.length, y.length); i += 1) {
    if (x[i] !== y[i]) return x[i] > y[i];
  }
  return x.length < y.length;
}

const toLoad = (perSideG: number, stack: PlateStack, barG: number): PlateLoad => ({
  totalKg: kg(barG + perSideG * 2),
  perSideKg: kg(perSideG),
  plates: stack,
});

/**
 * How to make `targetKg` on this bar, or the loadable weights either side of it.
 *
 * A target under the bar isn't a rounding problem — no arrangement of plates
 * makes the bar lighter — so it gets its own answer for the caller to explain.
 */
export function solvePlates(targetKg: number, setup: BarSetup): PlateSolution {
  const barG = g(setup.barKg);
  const targetG = g(targetKg);
  if (targetG < barG) return { kind: 'below-bar', barKg: setup.barKg };

  // Plates are symmetric, so an odd number of grams over the bar is unloadable
  // whatever the inventory. Floor it; `above` picks up the other side.
  const overG = targetG - barG;
  const perSideTargetG = Math.floor(overG / 2);

  const sums = reachable(setup);
  if (overG % 2 === 0) {
    const hit = sums.get(perSideTargetG);
    if (hit) return { kind: 'exact', load: toLoad(perSideTargetG, hit, barG) };
  }

  let belowG: number | null = null;
  let aboveG: number | null = null;
  for (const sum of sums.keys()) {
    if (sum <= perSideTargetG && (belowG === null || sum > belowG)) belowG = sum;
    if (sum * 2 + barG > targetG && (aboveG === null || sum < aboveG)) aboveG = sum;
  }

  return {
    kind: 'rounded',
    below: belowG === null ? null : toLoad(belowG, sums.get(belowG)!, barG),
    above: aboveG === null ? null : toLoad(aboveG, sums.get(aboveG)!, barG),
    stepKg: smallestStepKg(setup),
  };
}
