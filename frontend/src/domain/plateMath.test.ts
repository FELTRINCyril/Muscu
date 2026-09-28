/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { DEFAULT_BAR_SETUP, smallestStepKg, solvePlates } from './plateMath.ts';

/** Plenty of every plate, so counts never bind unless a test says so. */
const gym = DEFAULT_BAR_SETUP;

const exact = (target: number, setup = gym) => {
  const s = solvePlates(target, setup);
  assert.equal(s.kind, 'exact', `expected ${target} to be loadable exactly`);
  return s.kind === 'exact' ? s.load : null!;
};

test('the bar alone is an exact load with no plates', () => {
  const load = exact(20);
  assert.deepEqual(load.plates, []);
  assert.equal(load.perSideKg, 0);
});

test('loads the heaviest plates first', () => {
  // 100 kg = 20 bar + 40 a side = 25 + 15.
  assert.deepEqual(exact(100).plates, [
    { kg: 25, n: 1 },
    { kg: 15, n: 1 },
  ]);
});

test('repeats a plate rather than reaching for smaller ones', () => {
  // 140 kg = 20 bar + 60 a side = 25 + 25 + 10.
  assert.deepEqual(exact(140).plates, [
    { kg: 25, n: 2 },
    { kg: 10, n: 1 },
  ]);
});

test('per-side weight excludes the bar', () => {
  assert.equal(exact(102.5).perSideKg, 41.25);
});

test('works back from a different bar', () => {
  const load = exact(85, { barKg: 15, pairs: gym.pairs });
  assert.equal(load.perSideKg, 35);
});

test('a target below the bar reports the bar, not a load', () => {
  const s = solvePlates(15, gym);
  assert.equal(s.kind, 'below-bar');
});

test('a target that is not loadable offers the neighbour on each side', () => {
  // The smallest pair is 1.25, so loads move in 2.5 kg steps: 101 sits between.
  const s = solvePlates(101, gym);
  assert.equal(s.kind, 'rounded');
  if (s.kind !== 'rounded') return;
  assert.equal(s.below?.totalKg, 100);
  assert.equal(s.above?.totalKg, 102.5);
});

test('the step named on a rounded result is the smallest pair, doubled', () => {
  assert.equal(smallestStepKg(gym), 2.5);
  assert.equal(smallestStepKg({ barKg: 20, pairs: [{ kg: 5, count: 4 }] }), 10);
});

test('a plate set to zero is not used', () => {
  // Without the 1.25 pair the bar can only move in 5 kg steps, so 102.5 is out.
  const setup = { barKg: 20, pairs: gym.pairs.map((p) => (p.kg === 1.25 ? { ...p, count: 0 } : p)) };
  const s = solvePlates(102.5, setup);
  assert.equal(s.kind, 'rounded');
  if (s.kind !== 'rounded') return;
  assert.equal(s.below?.totalKg, 100);
  assert.equal(s.above?.totalKg, 105);
});

test('respects how many pairs the gym actually has', () => {
  // One 25 pair only: 60 a side must be 25 + 20 + 15, not 25 + 25 + 10.
  const setup = {
    barKg: 20,
    pairs: gym.pairs.map((p) => (p.kg === 25 ? { ...p, count: 1 } : p)),
  };
  assert.deepEqual(exact(140, setup).plates, [
    { kg: 25, n: 1 },
    { kg: 20, n: 1 },
    { kg: 15, n: 1 },
  ]);
});

test('finds a load a greedy fill would miss', () => {
  // Greedy takes 20 and is then stuck (no 5s left); 15 + 10 is the only answer.
  const setup = {
    barKg: 20,
    pairs: [
      { kg: 20, count: 1 },
      { kg: 15, count: 1 },
      { kg: 10, count: 1 },
    ],
  };
  assert.deepEqual(exact(70, setup).plates, [
    { kg: 15, n: 1 },
    { kg: 10, n: 1 },
  ]);
});

test('offers no heavier neighbour when the gym runs out of plates', () => {
  const setup = { barKg: 20, pairs: [{ kg: 10, count: 1 }] };
  const s = solvePlates(45, setup);
  assert.equal(s.kind, 'rounded');
  if (s.kind !== 'rounded') return;
  assert.equal(s.below?.totalKg, 40);
  assert.equal(s.above, null);
});

test('a half-kilo target does not drift on floating point', () => {
  const setup = { barKg: 20, pairs: [{ kg: 1.25, count: 8 }] };
  assert.equal(exact(22.5, setup).perSideKg, 1.25);
  assert.equal(exact(25, setup).perSideKg, 2.5);
});
