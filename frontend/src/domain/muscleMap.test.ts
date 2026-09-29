/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  MUSCLE_REGIONS,
  aggregateMuscleWork,
  isNeglected,
  regionsFor,
  tintFor,
  type MuscleRegion,
  type MuscleWorkEntry,
} from './muscleMap.ts';

const TODAY = new Date(2026, 8, 29); // 2026-09-29
const at = (y: number, m: number, d: number) => new Date(y, m - 1, d, 9).getTime();
const working = (n: number) =>
  Array.from({ length: n }, () => ({ type: 'normal', weight: 60, reps: 8, done: true }));

const entry = (e: Partial<MuscleWorkEntry> & { primary: string | null }): MuscleWorkEntry => ({
  at: at(2026, 9, 28),
  sets: working(1),
  ...e,
});

const agg = (entries: MuscleWorkEntry[], windowDays: 7 | 28 = 7, hidden: string[] = []) =>
  aggregateMuscleWork({ entries, windowDays, today: TODAY, hidden });

/** Thirds are not exact in binary floating point. */
const near = (actual: number | undefined, expected: number) =>
  assert.ok(
    actual !== undefined && Math.abs(actual - expected) < 1e-9,
    `expected ~${expected}, got ${actual}`,
  );

test('counts a primary muscle one set per working set, ignoring warmups and undone sets', () => {
  const m = agg([
    entry({
      primary: 'Lats',
      sets: [
        { type: 'normal', weight: 60, reps: 8, done: true },
        { type: 'warmup', weight: 30, reps: 10, done: true },
        { type: 'normal', weight: 60, reps: 8, done: false },
        { type: 'normal', weight: 65, reps: 6, done: true },
      ],
    }),
  ]);
  assert.equal(m.get('Lats'), 2);
});

test('a secondary muscle counts half of a primary', () => {
  const m = agg([entry({ primary: 'Chest', secondary: ['Triceps'], sets: working(4) })]);
  assert.equal(m.get('Chest'), 4);
  assert.equal(m.get('Triceps'), 2);
});

test('a muscle that is primary in one exercise and secondary in another sums both weightings', () => {
  const m = agg([
    entry({ primary: 'Triceps', sets: working(3) }),
    entry({ primary: 'Chest', secondary: ['Triceps'], sets: working(5) }),
  ]);
  assert.equal(m.get('Triceps'), 5.5);
});

test('a 28-day window reports a weekly average so both windows share one scale', () => {
  const entries = [
    entry({ at: at(2026, 9, 28), primary: 'Quads', sets: working(4) }),
    entry({ at: at(2026, 9, 20), primary: 'Quads', sets: working(4) }),
    entry({ at: at(2026, 9, 12), primary: 'Quads', sets: working(4) }),
    entry({ at: at(2026, 9, 5), primary: 'Quads', sets: working(4) }),
  ];
  assert.equal(agg(entries, 28).get('Quads'), 4); // 16 sets over 4 weeks
  assert.equal(agg(entries, 7).get('Quads'), 4); // only the newest is in a 7-day window
});

test('work older than the window is excluded', () => {
  const m = agg([entry({ at: at(2026, 9, 20), primary: 'Quads', sets: working(6) })]);
  assert.equal(m.get('Quads'), 0);
});

test('work on the oldest day of the window still counts', () => {
  const m = agg([entry({ at: at(2026, 9, 23), primary: 'Quads', sets: working(6) })]);
  assert.equal(m.get('Quads'), 6); // 2026-09-23 is day 1 of the 7 days ending today
});

test('Soleus counts as Calves', () => {
  assert.deepEqual(regionsFor('Soleus'), ['Calves']);
  assert.equal(agg([entry({ primary: 'Soleus', sets: working(3) })]).get('Calves'), 3);
});

test('Brachialis counts as Biceps', () => {
  assert.deepEqual(regionsFor('Brachialis'), ['Biceps']);
  assert.equal(agg([entry({ primary: 'Brachialis', sets: working(3) })]).get('Biceps'), 3);
});

test('Serratus counts as Obliques', () => {
  assert.deepEqual(regionsFor('Serratus'), ['Obliques']);
  assert.equal(agg([entry({ primary: 'Serratus', sets: working(3) })]).get('Obliques'), 3);
});

test('Abductors count as Glutes', () => {
  assert.deepEqual(regionsFor('Abductors'), ['Glutes']);
  assert.equal(agg([entry({ primary: 'Abductors', sets: working(3) })]).get('Glutes'), 3);
});

test('a generic Shoulders entry splits one third to each of the three delts', () => {
  const m = agg([entry({ primary: 'Shoulders', sets: working(6) })]);
  assert.equal(m.get('Front Delts'), 2);
  assert.equal(m.get('Side Delts'), 2);
  assert.equal(m.get('Rear Delts'), 2);
});

test('a generic Shoulders secondary splits a half set three ways', () => {
  const m = agg([entry({ primary: 'Chest', secondary: ['Shoulders'], sets: working(1) })]);
  near(m.get('Front Delts'), 1 / 6);
  near(m.get('Side Delts'), 1 / 6);
  near(m.get('Rear Delts'), 1 / 6);
});

test('a muscle name outside the catalog is dropped rather than invented as a region', () => {
  assert.deepEqual(regionsFor('Gills'), []);
  const m = agg([entry({ primary: 'Gills', sets: working(5) })]);
  assert.equal(m.size, MUSCLE_REGIONS.length);
  assert.ok([...m.values()].every((v) => v === 0));
});

test('an exercise with no primary muscle contributes nothing', () => {
  const m = agg([entry({ primary: null, sets: working(5) })]);
  assert.ok([...m.values()].every((v) => v === 0));
});

test('every region is present and zeroed so the diagram can draw untrained ones', () => {
  const m = agg([]);
  assert.equal(m.size, MUSCLE_REGIONS.length);
  for (const r of MUSCLE_REGIONS) assert.equal(m.get(r), 0);
});

test('a hidden muscle is left out of the aggregate entirely', () => {
  const m = agg([entry({ primary: 'Calves', sets: working(8) })], 7, ['Calves']);
  assert.equal(m.has('Calves'), false);
  assert.equal(m.size, MUSCLE_REGIONS.length - 1);
});

test('hiding an aliased muscle hides the region it maps onto', () => {
  const m = agg([], 7, ['Soleus']);
  assert.equal(m.has('Calves'), false);
});

test('hiding the generic Shoulders hides all three delts', () => {
  const m = agg([], 7, ['Shoulders']);
  assert.equal(m.size, MUSCLE_REGIONS.length - 3);
  for (const r of ['Front Delts', 'Side Delts', 'Rear Delts'] as MuscleRegion[]) {
    assert.equal(m.has(r), false);
  }
});

test('no work at all tints as none', () => {
  assert.equal(tintFor(0), 'none');
});

test('just under five weekly sets tints as low', () => {
  assert.equal(tintFor(4.9), 'low');
});

test('exactly five weekly sets tints as medium', () => {
  assert.equal(tintFor(5), 'medium');
});

test('nine weekly sets tints as medium', () => {
  assert.equal(tintFor(9), 'medium');
});

test('just over nine weekly sets is still medium, since high starts at ten', () => {
  assert.equal(tintFor(9.1), 'medium');
});

test('ten weekly sets tints as high', () => {
  assert.equal(tintFor(10), 'high');
});

test('an untrained region is neglected once the user has fourteen days of history', () => {
  assert.equal(isNeglected(0, 14, false), true);
  assert.equal(isNeglected(0, 60, false), true);
});

test('a new user with ten days of history has neglected nothing', () => {
  assert.equal(isNeglected(0, 10, false), false);
});

test('a region with any work at all is not neglected', () => {
  assert.equal(isNeglected(0.5, 60, false), false);
});

test('a hidden region is never flagged as neglected', () => {
  assert.equal(isNeglected(0, 60, true), false);
});
