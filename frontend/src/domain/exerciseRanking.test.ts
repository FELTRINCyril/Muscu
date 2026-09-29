/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { rankByUsage, usageScore } from './exerciseRanking.ts';

const DAY = 86400000;
const NOW = Date.UTC(2026, 8, 29, 12);
const daysAgo = (d: number) => NOW - d * DAY;

test('a lift trained more often scores higher', () => {
  const often = usageScore({ sessions: 20, lastAt: daysAgo(3) }, NOW);
  const rarely = usageScore({ sessions: 2, lastAt: daysAgo(3) }, NOW);
  assert.ok(often > rarely);
});

test('the same history scores lower as it ages', () => {
  const fresh = usageScore({ sessions: 10, lastAt: daysAgo(2) }, NOW);
  const stale = usageScore({ sessions: 10, lastAt: daysAgo(200) }, NOW);
  assert.ok(fresh > stale);
});

test('a current lift beats a bigger one abandoned months ago', () => {
  // What you're training now matters more than what you used to train.
  const current = usageScore({ sessions: 4, lastAt: daysAgo(4) }, NOW);
  const abandoned = usageScore({ sessions: 40, lastAt: daysAgo(300) }, NOW);
  assert.ok(current > abandoned, `${current} should beat ${abandoned}`);
});

test('never trained scores nothing', () => {
  assert.equal(usageScore({ sessions: 0, lastAt: 0 }, NOW), 0);
});

// --- rankByUsage ---

const ex = (id: string, name: string) => ({ id, name });

test('ranks trained lifts by score, highest first', () => {
  const ranked = rankByUsage(
    [ex('a', 'Squat'), ex('b', 'Curl'), ex('c', 'Bench')],
    new Map([
      ['a', { sessions: 5, lastAt: daysAgo(2) }],
      ['b', { sessions: 1, lastAt: daysAgo(60) }],
      ['c', { sessions: 20, lastAt: daysAgo(1) }],
    ]),
    { now: NOW, limit: 10 },
  );
  assert.deepEqual(ranked.map((e) => e.id), ['c', 'a', 'b']);
});

test('leaves out anything never trained', () => {
  const ranked = rankByUsage(
    [ex('a', 'Squat'), ex('b', 'Never Done')],
    new Map([['a', { sessions: 3, lastAt: daysAgo(5) }]]),
    { now: NOW, limit: 10 },
  );
  assert.deepEqual(ranked.map((e) => e.id), ['a']);
});

test('caps the list so the shortcut stays a shortcut', () => {
  const many = Array.from({ length: 40 }, (_, i) => ex(`e${i}`, `Ex ${i}`));
  const usage = new Map(many.map((e, i) => [e.id, { sessions: i + 1, lastAt: daysAgo(1) }]));
  assert.equal(rankByUsage(many, usage, { now: NOW, limit: 12 }).length, 12);
});

test('no trained lifts means no section at all', () => {
  assert.deepEqual(rankByUsage([ex('a', 'Squat')], new Map(), { now: NOW, limit: 10 }), []);
});

test('ties break by name, so the order never jitters between renders', () => {
  const usage = new Map([
    ['a', { sessions: 5, lastAt: daysAgo(3) }],
    ['b', { sessions: 5, lastAt: daysAgo(3) }],
  ]);
  const ranked = rankByUsage([ex('b', 'Bench'), ex('a', 'Squat')], usage, { now: NOW, limit: 10 });
  assert.deepEqual(ranked.map((e) => e.name), ['Bench', 'Squat']);
});
