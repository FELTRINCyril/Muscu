/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  COLLAPSE_MIN_TITLES,
  RECENT_WINDOW_DAYS,
  createRoutinesLabel,
  groupImportedRoutines,
  isRecentlyTrained,
  lastTrainedLabel,
  partialFailureNote,
  routineCandidateMeta,
  seenOnceLabel,
  splitSeenOnce,
  titlesHeaderLabel,
  uniqueRoutineName,
} from './importedRoutines.ts';
import type { ImportedSession } from '../api/types.ts';

const DAY = 86_400_000;

/** A session on day `d` (days after 2026-01-01 UTC), `ex` exercises. */
function session(id: string, title: string, d: number, ex = 5): ImportedSession {
  return {
    workout_id: id,
    title,
    started_at: Date.UTC(2026, 0, 1) + d * DAY,
    exercise_count: ex,
  };
}

// --- groupImportedRoutines -------------------------------------------------

test('groups sessions by title and counts them', () => {
  const got = groupImportedRoutines([
    session('w1', 'Full Body A', 0, 6),
    session('w2', 'Full Body B', 1, 6),
    session('w3', 'Full Body B', 3, 6),
  ]);
  assert.deepEqual(
    got.map((c) => [c.name, c.sessions, c.workoutId]),
    [
      ['Full Body B', 2, 'w3'],
      ['Full Body A', 1, 'w1'],
    ],
  );
});

test('takes name, workout id and exercise count from the most recent session', () => {
  const got = groupImportedRoutines([
    session('old', 'upper', 0, 4),
    session('new', 'Upper', 9, 7),
    session('mid', 'UPPER', 5, 6),
  ]);
  assert.equal(got.length, 1);
  assert.equal(got[0].name, 'Upper');
  assert.equal(got[0].workoutId, 'new');
  assert.equal(got[0].exerciseCount, 7);
  assert.equal(got[0].sessions, 3);
  assert.equal(got[0].lastTrainedAt, Date.UTC(2026, 0, 1) + 9 * DAY);
});

test('matches titles ignoring case and repeated or surrounding whitespace', () => {
  const got = groupImportedRoutines([
    session('a', 'Temp lower', 0),
    session('b', '  Temp   Lower ', 1),
  ]);
  assert.equal(got.length, 1);
  assert.equal(got[0].sessions, 2);
  // The row shows the spelling of the most recent session, trimmed.
  assert.equal(got[0].name, 'Temp   Lower');
});

test('excludes untitled sessions', () => {
  const got = groupImportedRoutines([
    session('a', '', 0),
    session('b', '   ', 1),
    session('c', 'Push', 2),
  ]);
  assert.deepEqual(got.map((c) => c.name), ['Push']);
});

test('sorts by last trained newest first, ties broken by session count', () => {
  const got = groupImportedRoutines([
    session('a', 'Few', 5),
    session('b', 'Many', 5),
    session('c', 'Many', 1),
    session('d', 'Many', 2),
    session('e', 'Stale', 9999 - 9990), // day 9
  ]);
  assert.deepEqual(got.map((c) => c.name), ['Stale', 'Many', 'Few']);
});

test('breaks a full tie on name so the order is stable', () => {
  const got = groupImportedRoutines([session('a', 'Bravo', 3), session('b', 'Alpha', 3)]);
  assert.deepEqual(got.map((c) => c.name), ['Alpha', 'Bravo']);
});

test('returns nothing for an import that created no workouts', () => {
  assert.deepEqual(groupImportedRoutines([]), []);
});

// --- splitSeenOnce ---------------------------------------------------------

const many = (n: number, singles: number) => {
  const out: ImportedSession[] = [];
  for (let i = 0; i < n - singles; i++) {
    out.push(session(`m${i}a`, `Multi ${i}`, 100 - i, 5));
    out.push(session(`m${i}b`, `Multi ${i}`, 50 - i, 5));
  }
  for (let i = 0; i < singles; i++) out.push(session(`s${i}`, `Single ${i}`, 10 - i, 5));
  return groupImportedRoutines(out);
};

test('collapses titles seen once once there are enough titles', () => {
  const { rows, seenOnce } = splitSeenOnce(many(6, 2));
  assert.equal(rows.length, 4);
  assert.deepEqual(seenOnce.map((c) => c.name), ['Single 0', 'Single 1']);
});

test('collapses nothing below the title threshold', () => {
  const candidates = many(COLLAPSE_MIN_TITLES - 1, 2);
  const { rows, seenOnce } = splitSeenOnce(candidates);
  assert.equal(rows.length, candidates.length);
  assert.deepEqual(seenOnce, []);
});

test('never collapses every row away', () => {
  // Eight titles, all seen once: collapsing them would leave an empty list, which
  // reads as "no routines to offer" rather than as something to expand.
  const candidates = many(8, 8);
  const { rows, seenOnce } = splitSeenOnce(candidates);
  assert.equal(rows.length, 8);
  assert.deepEqual(seenOnce, []);
});

// --- Labels ----------------------------------------------------------------

test('meta line names sessions and exercises, singular at one', () => {
  const [a, b] = groupImportedRoutines([
    session('a', 'Pull', 1, 6),
    session('b', 'Push', 2, 6),
    session('c', 'Push', 3, 6),
  ]);
  assert.equal(routineCandidateMeta(a), '2 SESSIONS · 6 EXERCISES');
  assert.equal(routineCandidateMeta(b), '1 SESSION · 6 EXERCISES');
  const [solo] = groupImportedRoutines([session('d', 'Deadlift day', 1, 1)]);
  assert.equal(routineCandidateMeta(solo), '1 SESSION · 1 EXERCISE');
});

test('last trained label is a padded day and an upper-case month', () => {
  assert.equal(lastTrainedLabel(new Date(2026, 8, 28, 12).getTime()), '28 SEP');
  assert.equal(lastTrainedLabel(new Date(2026, 2, 2, 12).getTime()), '02 MAR');
  assert.equal(lastTrainedLabel(new Date(2025, 11, 31, 12).getTime()), '31 DEC');
});

test('a session is recent when it is inside the window before the newest one', () => {
  const newest = Date.UTC(2026, 8, 29);
  assert.equal(isRecentlyTrained(newest, newest), true);
  assert.equal(isRecentlyTrained(newest - RECENT_WINDOW_DAYS * DAY, newest), true);
  assert.equal(isRecentlyTrained(newest - (RECENT_WINDOW_DAYS * DAY + 1), newest), false);
});

test('titles header pluralises', () => {
  assert.equal(titlesHeaderLabel(10), '10 TITLES');
  assert.equal(titlesHeaderLabel(1), '1 TITLE');
});

test('collapsed row names how many are hidden', () => {
  assert.equal(seenOnceLabel(2), '2 MORE · SEEN ONCE');
  assert.equal(seenOnceLabel(1), '1 MORE · SEEN ONCE');
});

test('the CTA is Done until something is picked', () => {
  assert.equal(createRoutinesLabel(0), 'Done');
  assert.equal(createRoutinesLabel(1), 'Create 1 routine');
  assert.equal(createRoutinesLabel(5), 'Create 5 routines');
});

// --- Partial failure -------------------------------------------------------

test('no note when every pick was created', () => {
  assert.equal(partialFailureNote(5, 5, []), null);
});

test('a note names the count created and what failed', () => {
  assert.equal(partialFailureNote(4, 5, ['Push']), 'Created 4 of 5 · Push failed');
  assert.equal(partialFailureNote(3, 5, ['Push', 'Pull']), 'Created 3 of 5 · Push, Pull failed');
  assert.equal(partialFailureNote(0, 1, ['Push']), 'Created 0 of 1 · Push failed');
});

// --- uniqueRoutineName -----------------------------------------------------

test('keeps the name when nothing else holds it', () => {
  assert.equal(uniqueRoutineName('Upper', ['Lower']), 'Upper');
  assert.equal(uniqueRoutineName('Upper', []), 'Upper');
});

test('suffixes rather than overwriting an existing routine', () => {
  assert.equal(uniqueRoutineName('Upper', ['Upper']), 'Upper (2)');
  assert.equal(uniqueRoutineName('Upper', ['Upper', 'Upper (2)']), 'Upper (3)');
});

test('a collision is judged the way titles are matched', () => {
  assert.equal(uniqueRoutineName('Upper', ['  upper ']), 'Upper (2)');
});

test('trims the name it returns', () => {
  assert.equal(uniqueRoutineName('  Upper  ', []), 'Upper');
});

// --- A recent one-off must not be collapsed -----------------------------------
// The list sorts on recency but the collapse rule counted sessions, so the two
// disagreed: someone who switched apps mid-programme had the thing they actually
// train now hidden behind the expander, under five stale titles.
const NOW = Date.UTC(2026, 9, 1);
const sess = (title: string, n: number, daysAgo: number) =>
  Array.from({ length: n }, (_, i) => ({
    workout_id: `${title}-${i}`,
    title,
    started_at: NOW - (daysAgo + i * 7) * DAY,
    exercise_count: 5,
  }));

test('a title trained once but trained recently stays visible', () => {
  const sessions = [
    ...sess('Old Push', 20, 200), ...sess('Old Pull', 18, 205), ...sess('Old Legs', 15, 210),
    ...sess('Temp A', 9, 220), ...sess('Temp B', 8, 230),
    ...sess('New Upper', 1, 2),
  ];
  const { rows, seenOnce } = splitSeenOnce(groupImportedRoutines(sessions));
  assert.ok(
    rows.some((c) => c.name === 'New Upper'),
    'the most recently trained title was hidden behind the expander',
  );
  assert.equal(seenOnce.length, 0);
});

test('a title trained once long ago still collapses', () => {
  const sessions = [
    ...sess('Old Push', 20, 200), ...sess('Old Pull', 18, 205), ...sess('Old Legs', 15, 210),
    ...sess('Temp A', 9, 220), ...sess('Temp B', 8, 230),
    ...sess('Abandoned', 1, 400),
  ];
  const { rows, seenOnce } = splitSeenOnce(groupImportedRoutines(sessions));
  assert.deepEqual(seenOnce.map((c) => c.name), ['Abandoned']);
  assert.ok(!rows.some((c) => c.name === 'Abandoned'));
});
