/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildRoutineDiff } from './routineDiff.ts';

type T = 'normal' | 'warmup' | 'drop' | 'failure';

/** A routine exercise: `id` doubles as the catalog exercise id and the name. */
const rEx = (id: string, types: T[], rest = 120) => ({
  id: `r-${id}`,
  position: 0,
  rest_seconds: rest,
  exercise: { id, name: id } as never,
  sets: types.map((type, i) => ({ id: `rs-${id}-${i}`, position: i, type })),
});

const wEx = (id: string, types: T[], rest = 120) => ({
  id: `w-${id}`,
  position: 0,
  rest_seconds: rest,
  exercise: { id, name: id } as never,
  sets: types.map((type, i) => ({ id: `ws-${id}-${i}`, position: i, type, done: true })),
});

const routine = (...exercises: ReturnType<typeof rEx>[]) =>
  ({ id: 'r1', name: 'Push', initials: 'P', position: 0, exercises }) as never;
const workout = (...exercises: ReturnType<typeof wEx>[]) =>
  ({ id: 'w1', name: 'Push', exercises }) as never;

const details = (rows: { detail: string }[]) => rows.map((r) => r.detail);

// --- existing behaviour, pinned before changing it ------------------------

test('no rows when the workout matches its routine', () => {
  const diff = buildRoutineDiff(routine(rEx('bench', ['normal', 'normal'])), workout(wEx('bench', ['normal', 'normal'])));
  assert.deepEqual(diff, []);
});

test('reports an added exercise', () => {
  const diff = buildRoutineDiff(
    routine(rEx('bench', ['normal'])),
    workout(wEx('bench', ['normal']), wEx('fly', ['normal', 'normal'])),
  );
  assert.equal(diff.length, 1);
  assert.equal(diff[0].marker, 'added');
  assert.equal(diff[0].detail, '2 sets');
});

test('reports a removed exercise', () => {
  const diff = buildRoutineDiff(
    routine(rEx('bench', ['normal']), rEx('fly', ['normal'])),
    workout(wEx('bench', ['normal'])),
  );
  assert.equal(diff.length, 1);
  assert.equal(diff[0].marker, 'removed');
  assert.equal(diff[0].detail, 'removed');
});

test('reports a changed working-set count', () => {
  const diff = buildRoutineDiff(
    routine(rEx('bench', ['normal', 'normal'])),
    workout(wEx('bench', ['normal', 'normal', 'normal'])),
  );
  assert.deepEqual(details(diff), ['2 → 3 sets']);
});

test('reports a changed rest timer', () => {
  const diff = buildRoutineDiff(
    routine(rEx('bench', ['normal'], 120)),
    workout(wEx('bench', ['normal'], 90)),
  );
  assert.deepEqual(details(diff), ['rest 2:00 → 1:30']);
});

test('reports a reordered exercise', () => {
  const diff = buildRoutineDiff(
    routine(rEx('bench', ['normal']), rEx('fly', ['normal'])),
    workout(wEx('fly', ['normal']), wEx('bench', ['normal'])),
  );
  assert.deepEqual(details(diff), ['moved']);
});

// --- set types (the gap this change closes) -------------------------------

test('reports a set marked to failure', () => {
  const diff = buildRoutineDiff(
    routine(rEx('bench', ['normal', 'normal', 'normal'])),
    workout(wEx('bench', ['normal', 'normal', 'failure'])),
  );
  assert.equal(diff.length, 1);
  assert.equal(diff[0].marker, 'changed');
  assert.match(diff[0].detail, /set 3/);
  assert.match(diff[0].detail, /failure/);
});

test('reports a set marked as a drop set', () => {
  const diff = buildRoutineDiff(
    routine(rEx('bench', ['normal', 'normal'])),
    workout(wEx('bench', ['normal', 'drop'])),
  );
  assert.equal(diff.length, 1);
  assert.match(diff[0].detail, /set 2/);
  assert.match(diff[0].detail, /drop/);
});

test('reports a warm-up added alongside the same working sets', () => {
  // Working count is 2 on both sides, so only the type sequence reveals this.
  const diff = buildRoutineDiff(
    routine(rEx('bench', ['normal', 'normal'])),
    workout(wEx('bench', ['warmup', 'normal', 'normal'])),
  );
  assert.equal(diff.length, 1);
  assert.match(diff[0].detail, /set 1/);
});

test('a set-type change wins over a rest change, being the more specific', () => {
  const diff = buildRoutineDiff(
    routine(rEx('bench', ['normal', 'normal'], 120)),
    workout(wEx('bench', ['normal', 'failure'], 90)),
  );
  assert.equal(diff.length, 1);
  assert.match(diff[0].detail, /failure/);
});

test('set types are compared per exercise, not across them', () => {
  const diff = buildRoutineDiff(
    routine(rEx('bench', ['normal']), rEx('fly', ['normal'])),
    workout(wEx('bench', ['normal']), wEx('fly', ['failure'])),
  );
  assert.equal(diff.length, 1);
  assert.equal(diff[0].name, 'fly');
});
