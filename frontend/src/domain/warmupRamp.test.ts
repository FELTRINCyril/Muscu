/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { defaultWarmupSets, warmupRamp } from './warmupRamp.ts';

/** Barbell-ish rounding: 2.5 kg steps. */
const to2p5 = (kg: number) => Math.round(kg / 2.5) * 2.5;
const exact = (kg: number) => kg;

const ramp = (workingKg: number, over: Partial<Parameters<typeof warmupRamp>[0]> = {}) =>
  warmupRamp({ workingKg, barKg: 20, round: to2p5, ...over });

test('the set count defaults by how heavy the working set is', () => {
  assert.equal(defaultWarmupSets(30), 1);
  assert.equal(defaultWarmupSets(40), 2);
  assert.equal(defaultWarmupSets(79), 2);
  assert.equal(defaultWarmupSets(80), 4);
  assert.equal(defaultWarmupSets(139), 4);
  assert.equal(defaultWarmupSets(140), 5);
});

test('a light working set warms up with the bar alone', () => {
  const rows = ramp(30);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].kg, 20);
  assert.equal(rows[0].reps, 10);
  assert.equal(rows[0].pct, null);
});

test('a heavy working set ramps bar, 40, 60, 80, 90', () => {
  const rows = ramp(200, { round: exact });
  assert.deepEqual(
    rows.map((r) => [r.pct, r.kg, r.reps]),
    [
      [null, 20, 10],
      [40, 80, 5],
      [60, 120, 3],
      [80, 160, 2],
      [90, 180, 1],
    ],
  );
});

test('a mid-weight working set stops before 90%', () => {
  const rows = ramp(100, { round: exact });
  assert.deepEqual(
    rows.map((r) => r.pct),
    [null, 40, 60, 80],
  );
});

test('the requested set count overrides the default', () => {
  assert.equal(ramp(200, { sets: 2 }).length, 2);
  assert.equal(ramp(40, { sets: 5, round: exact }).length, 5);
});

test('rows round to weights the gym can actually load', () => {
  // 40% of 102 is 40.8, which no 2.5 kg step makes.
  const rows = ramp(102);
  for (const r of rows) assert.equal(r.kg % 2.5, 0, `${r.kg} is not loadable`);
});

test('two rows that round together keep only the heavier', () => {
  // 40% and 60% of 45 are 18 and 27; against the 20 kg bar the first rounds
  // back onto the bar itself.
  const rows = ramp(45, { sets: 4 });
  const weights = rows.map((r) => r.kg);
  assert.equal(new Set(weights).size, weights.length, `duplicate weights: ${weights}`);
});

test('never proposes a warm-up at or above the working weight', () => {
  for (const working of [22.5, 25, 30, 42.5, 60]) {
    for (const r of ramp(working, { sets: 5 })) {
      assert.ok(r.kg < working, `${r.kg} is not below ${working}`);
    }
  }
});

test('rows climb in weight and fall in reps', () => {
  const rows = ramp(160);
  for (let i = 1; i < rows.length; i += 1) {
    assert.ok(rows[i].kg > rows[i - 1].kg, 'weight must climb');
    assert.ok(rows[i].reps <= rows[i - 1].reps, 'reps must not climb');
  }
});

test('without a bar the ramp starts at the first percentage', () => {
  // Dumbbells and machines have no empty bar to warm up with.
  const rows = warmupRamp({ workingKg: 100, barKg: null, sets: 4, round: exact });
  assert.equal(rows[0].pct, 40);
  assert.ok(rows.every((r) => r.pct !== null));
});

test('a working weight at or under the bar has nothing to ramp', () => {
  assert.deepEqual(ramp(20), []);
  assert.deepEqual(ramp(0), []);
});
