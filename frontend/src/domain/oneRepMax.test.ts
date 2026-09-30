/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { estimateTier, percentageTable, repsAtLoad } from './oneRepMax.ts';

const to2p5 = (kg: number) => Math.round(kg / 2.5) * 2.5;

test('how far the estimate can be trusted depends on the rep count', () => {
  assert.equal(estimateTier(1), 'close');
  assert.equal(estimateTier(5), 'close');
  assert.equal(estimateTier(6), 'reasonable');
  assert.equal(estimateTier(10), 'reasonable');
  assert.equal(estimateTier(11), 'rough');
  assert.equal(estimateTier(20), 'rough');
});

test('an impossible rep count has no tier', () => {
  assert.equal(estimateTier(0), null);
  assert.equal(estimateTier(-3), null);
  assert.equal(estimateTier(Number.NaN), null);
});

test('the table runs from 100% down to 50%', () => {
  const rows = percentageTable(100, { round: (n) => n });
  assert.equal(rows[0].pct, 100);
  assert.equal(rows[rows.length - 1].pct, 50);
  assert.ok(rows.every((r, i) => i === 0 || r.pct < rows[i - 1].pct));
});

test('each row is that share of the estimate', () => {
  const rows = percentageTable(200, { round: (n) => n });
  const ninety = rows.find((r) => r.pct === 90)!;
  assert.equal(ninety.kg, 180);
});

test('loads round to what can be put on the bar', () => {
  const rows = percentageTable(101, { round: to2p5 });
  for (const r of rows) assert.equal(r.kg % 2.5, 0, `${r.kg} is not loadable`);
});

test('reps are read back from the rounded load, not the exact share', () => {
  // 100% of a 100 kg estimate is one rep, whatever rounding did to it.
  const rows = percentageTable(100, { round: to2p5 });
  assert.equal(rows.find((r) => r.pct === 100)!.reps, 1);
});

test('a lighter load is worth more reps', () => {
  const rows = percentageTable(100, { round: (n) => n });
  const ninety = rows.find((r) => r.pct === 90)!.reps!;
  const eighty = rows.find((r) => r.pct === 80)!.reps!;
  assert.ok(eighty > ninety, `${eighty} should beat ${ninety}`);
});

test('the reps column stops below 75%, where turning a load back into reps stops meaning anything', () => {
  const rows = percentageTable(100, { round: (n) => n });
  for (const r of rows) {
    if (r.pct >= 75) assert.ok(r.reps !== null, `${r.pct}% should have reps`);
    else assert.equal(r.reps, null, `${r.pct}% should not`);
  }
});

test('no table without an estimate to build it from', () => {
  assert.deepEqual(percentageTable(0, { round: (n) => n }), []);
  assert.deepEqual(percentageTable(Number.NaN, { round: (n) => n }), []);
});

test('reads a rep count back out of a load', () => {
  // Epley: 100 kg for 3 estimates 110. Going back, 100 against a 110 estimate
  // must land on 3 again.
  assert.equal(repsAtLoad(110, 100), 3);
  assert.equal(repsAtLoad(110, 110), 1);
});
