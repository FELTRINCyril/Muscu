/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  groupDuplicates,
  nameSimilarity,
  normalizeName,
  pairReason,
  pickSurvivor,
  prMetricLabel,
  reconcilePrs,
  type MergeCandidate,
  type PrCell,
} from './mergeDuplicates.ts';

function cand(over: Partial<MergeCandidate> & { id: string; name: string }): MergeCandidate {
  return {
    equipment: 'barbell',
    primaryMuscleId: null,
    source: null,
    externalId: null,
    isCatalog: false,
    initials: '',
    setCount: 0,
    workoutCount: 0,
    firstWorkoutMs: null,
    ...over,
  };
}

// --- normalizeName ---------------------------------------------------------

test('normalizeName folds casing and collapses spacing/punctuation', () => {
  assert.equal(normalizeName('Incline Bench Press'), 'incline bench press');
  assert.equal(normalizeName('incline  bench   press'), 'incline bench press');
  assert.equal(normalizeName('Cable-Fly (Machine)'), 'cable fly machine');
});

// --- pairReason + guards ---------------------------------------------------

test('same normalized name + same equipment is SAME NAME', () => {
  const a = cand({ id: 'a', name: 'Incline Bench Press', equipment: 'dumbbell' });
  const b = cand({ id: 'b', name: 'incline bench press', equipment: 'dumbbell' });
  assert.equal(pairReason(a, b), 'same_name');
});

test('same name but DIFFERENT equipment is not a duplicate', () => {
  const a = cand({ id: 'a', name: 'Bench Press', equipment: 'barbell' });
  const b = cand({ id: 'b', name: 'Bench Press', equipment: 'dumbbell' });
  assert.equal(pairReason(a, b), null);
});

test('a shared import id is SAME IMPORT even when names differ', () => {
  const a = cand({ id: 'a', name: 'Romanian Deadlift', source: 'imp', externalId: 'RDL' });
  const b = cand({ id: 'b', name: 'RDL', source: 'imp', externalId: 'RDL' });
  assert.equal(pairReason(a, b), 'same_import');
});

test('matching source but different external_id does not pair on import', () => {
  const a = cand({ id: 'a', name: 'A', source: 'imp', externalId: 'x' });
  const b = cand({ id: 'b', name: 'B', source: 'imp', externalId: 'y', equipment: 'cable' });
  assert.equal(pairReason(a, b), null);
});

test('a subset name with matching equipment is SIMILAR NAME', () => {
  const a = cand({ id: 'a', name: 'Incline Bench Press', equipment: 'barbell' });
  const b = cand({ id: 'b', name: 'Incline Barbell Bench Press', equipment: 'barbell' });
  assert.equal(pairReason(a, b), 'similar_name');
});

test('SIMILAR NAME requires equipment to match', () => {
  const a = cand({ id: 'a', name: 'Incline Bench Press', equipment: 'barbell' });
  const b = cand({ id: 'b', name: 'Incline Barbell Bench Press', equipment: 'dumbbell' });
  assert.equal(pairReason(a, b), null);
});

test('a contradicting primary muscle blocks SIMILAR NAME', () => {
  const a = cand({ id: 'a', name: 'Cable Fly', equipment: 'cable', primaryMuscleId: 'chest' });
  const b = cand({ id: 'b', name: 'Cable Row', equipment: 'cable', primaryMuscleId: 'back' });
  assert.equal(pairReason(a, b), null);
});

test('two catalog rows never pair — a collision there is a catalog bug', () => {
  const a = cand({ id: 'a', name: 'Squat', isCatalog: true });
  const b = cand({ id: 'b', name: 'squat', isCatalog: true });
  assert.equal(pairReason(a, b), null);
});

test('nameSimilarity is 1 for identical, lower for edits', () => {
  assert.equal(nameSimilarity('bench press', 'bench press'), 1);
  assert.ok(nameSimilarity('bench press', 'bemch press') > 0.8);
  assert.ok(nameSimilarity('bench press', 'deadlift') < 0.4);
});

// --- pickSurvivor ----------------------------------------------------------

test('a catalog row is the survivor even with less history', () => {
  const catalog = cand({ id: 'cat', name: 'Bench Press', isCatalog: true, setCount: 2, workoutCount: 1 });
  const custom = cand({ id: 'cus', name: 'bench press', setCount: 40, workoutCount: 10 });
  const { survivorId, survivorReason } = pickSurvivor([custom, catalog]);
  assert.equal(survivorId, 'cat');
  assert.match(survivorReason, /images/i);
});

test('otherwise the row with more history survives', () => {
  const a = cand({ id: 'a', name: 'Bench', setCount: 47, workoutCount: 12 });
  const b = cand({ id: 'b', name: 'bench', setCount: 8, workoutCount: 3 });
  assert.equal(pickSurvivor([b, a]).survivorId, 'a');
});

test('history ties break by earliest start then id, deterministically', () => {
  const a = cand({ id: 'a', name: 'X', setCount: 5, workoutCount: 2, firstWorkoutMs: 200 });
  const b = cand({ id: 'b', name: 'x', setCount: 5, workoutCount: 2, firstWorkoutMs: 100 });
  assert.equal(pickSurvivor([a, b]).survivorId, 'b'); // earlier start = more history
});

// --- groupDuplicates -------------------------------------------------------

test('groups the same lift saved twice, survivor first', () => {
  const groups = groupDuplicates([
    cand({ id: 'a', name: 'Incline Bench Press', equipment: 'dumbbell', setCount: 47, workoutCount: 12 }),
    cand({ id: 'b', name: 'incline bench press', equipment: 'dumbbell', setCount: 8, workoutCount: 3 }),
  ]);
  assert.equal(groups.length, 1);
  assert.equal(groups[0].reason, 'same_name');
  assert.equal(groups[0].members[0].id, 'a');
  assert.equal(groups[0].survivorId, 'a');
});

test('three-or-more chain into one group merged in a single pass', () => {
  const groups = groupDuplicates([
    cand({ id: 'a', name: 'Deadlift', setCount: 30, workoutCount: 9 }),
    cand({ id: 'b', name: 'deadlift', setCount: 5, workoutCount: 2 }),
    cand({ id: 'c', name: 'DEADLIFT', setCount: 1, workoutCount: 1 }),
  ]);
  assert.equal(groups.length, 1);
  assert.equal(groups[0].members.length, 3);
  assert.equal(groups[0].survivorId, 'a');
});

test('unrelated exercises never group', () => {
  const groups = groupDuplicates([
    cand({ id: 'a', name: 'Bench Press' }),
    cand({ id: 'b', name: 'Squat', equipment: 'barbell' }),
  ]);
  assert.equal(groups.length, 0);
});

test('a group with two catalog rows is dropped', () => {
  const groups = groupDuplicates([
    cand({ id: 'a', name: 'Squat', isCatalog: true }),
    cand({ id: 'b', name: 'squat', isCatalog: true }),
    cand({ id: 'c', name: 'Squat', setCount: 3, workoutCount: 1 }),
  ]);
  assert.equal(groups.length, 0);
});

test('groups order strongest reason first, then bigger merge', () => {
  const groups = groupDuplicates([
    // similar (amber, judgement call)
    cand({ id: 's1', name: 'Cable Fly', equipment: 'cable', primaryMuscleId: 'chest', setCount: 21 }),
    cand({ id: 's2', name: 'Cable Flye', equipment: 'cable', primaryMuscleId: 'chest', setCount: 9 }),
    // same name (safe)
    cand({ id: 'n1', name: 'Row', equipment: 'barbell', setCount: 4 }),
    cand({ id: 'n2', name: 'row', equipment: 'barbell', setCount: 2 }),
  ]);
  assert.equal(groups.length, 2);
  assert.equal(groups[0].reason, 'same_name');
  assert.equal(groups[1].reason, 'similar_name');
});

// --- reconcilePrs ----------------------------------------------------------

function pr(metric: PrCell['metric'], value: number, display: string): PrCell {
  return { metric, value, display };
}

test('keeps the higher value per metric; a discarded PR can win', () => {
  const survivor = [pr('est_1rm', 78, '78 kg'), pr('best_set', 60, '60 kg × 10'), pr('max_reps', 10, '60 × 10')];
  const loser = [pr('max_reps', 14, 'BW × 14')];
  const rows = reconcilePrs(survivor, [loser]);
  const byMetric = new Map(rows.map((r) => [r.metric, r]));
  assert.equal(byMetric.get('est_1rm')!.fromDup, false);
  assert.equal(byMetric.get('best_set')!.fromDup, false);
  assert.equal(byMetric.get('max_reps')!.value, 14);
  assert.equal(byMetric.get('max_reps')!.fromDup, true);
});

test('the survivor wins ties — an equal record is never "from dup"', () => {
  const rows = reconcilePrs([pr('est_1rm', 100, '100 kg')], [[pr('est_1rm', 100, '100 kg')]]);
  assert.equal(rows[0].fromDup, false);
});

test('a metric only the loser has is carried over from the dup', () => {
  const rows = reconcilePrs([], [[pr('best_volume', 5000, '5,000 kg')]]);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].fromDup, true);
});

test('PR rows come out in table order (1RM, best set, most reps)', () => {
  const rows = reconcilePrs(
    [pr('max_reps', 10, 'x'), pr('best_set', 60, 'y'), pr('est_1rm', 78, 'z')],
    [],
  );
  assert.deepEqual(rows.map((r) => r.metric), ['est_1rm', 'best_set', 'max_reps']);
});

test('prMetricLabel maps slugs to the mock labels', () => {
  assert.equal(prMetricLabel('est_1rm'), '1RM');
  assert.equal(prMetricLabel('best_set'), 'Best set');
  assert.equal(prMetricLabel('max_reps'), 'Most reps');
});
