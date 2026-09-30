/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  detectStall,
  detectVolumeRamp,
  shouldShowAdvisory,
  stallSpanDays,
  type AdvisoryInput,
  type ExerciseHistory,
} from './deload.ts';

const DAY = 86400000;
const NOW = Date.UTC(2026, 8, 29, 12);

/** An est-1RM series, oldest first, `gapDays` apart, ending today. */
const history = (best1rms: number[], gapDays = 8, endAt = NOW) =>
  best1rms.map((best1rm, i) => ({
    at: endAt - (best1rms.length - 1 - i) * gapDays * DAY,
    best1rm,
  }));

/** Six sessions whose last three never beat the 75 set in session three. */
const FLAT = [70, 72, 75, 75, 74, 75];

const stalledLift = (over: Partial<ExerciseHistory> = {}): ExerciseHistory => ({
  exerciseId: 'bench',
  sessions: history(FLAT),
  weeklyVolumes: [],
  dismissedAt: null,
  ...over,
});

const rampingLift = (over: Partial<ExerciseHistory> = {}): ExerciseHistory => ({
  exerciseId: 'squat',
  sessions: history([70, 75, 80, 85]),
  weeklyVolumes: [10, 10, 10, 10, 15, 16],
  dismissedAt: null,
  ...over,
});

const advisory = (over: Partial<AdvisoryInput> = {}) =>
  shouldShowAdvisory({
    enabled: true,
    now: NOW,
    historyStartedAt: NOW - 200 * DAY,
    lastShownAt: null,
    prThisSession: false,
    exercises: [stalledLift()],
    ...over,
  });

// --- the stall itself ---

test('three sessions with no new best, spread over weeks, is a stall', () => {
  assert.equal(detectStall(history(FLAT), NOW), true);
});

test('matching the old best is not beating it', () => {
  assert.equal(detectStall(history([70, 75, 75, 75, 75]), NOW), true);
});

test('a new best anywhere in the last three sessions clears the stall', () => {
  assert.equal(detectStall(history([70, 72, 74, 76, 78]), NOW), false);
  assert.equal(detectStall(history([70, 72, 75, 75, 76, 75]), NOW), false);
});

test('a lift with too few sessions is never a stall', () => {
  assert.equal(detectStall(history([75, 75, 75]), NOW), false);
  assert.equal(detectStall([], NOW), false);
});

test('three sessions crammed into one week are too close together to be a stall', () => {
  assert.equal(detectStall(history(FLAT, 3), NOW), false);
});

test('a flat run of exactly fourteen days counts', () => {
  assert.equal(detectStall(history(FLAT, 7), NOW), true);
});

test('the stall span is counted from the first flat session to now', () => {
  assert.equal(stallSpanDays(history(FLAT), NOW), 16);
  assert.equal(stallSpanDays(history([70, 72, 74, 76, 78]), NOW), null);
});

// --- the volume ramp ---

test('two weeks at least 40% above the four-week average is a ramp', () => {
  assert.equal(detectVolumeRamp([10, 10, 10, 10, 15, 16]), true);
});

test('exactly 40% above the average counts', () => {
  assert.equal(detectVolumeRamp([10, 10, 10, 10, 14, 14]), true);
});

test('one big week on its own is not a ramp', () => {
  assert.equal(detectVolumeRamp([10, 10, 10, 10, 10, 20]), false);
  assert.equal(detectVolumeRamp([10, 10, 10, 10, 20, 10]), false);
});

test('fewer than six weeks of volume is never a ramp', () => {
  assert.equal(detectVolumeRamp([10, 10, 10, 15, 16]), false);
  assert.equal(detectVolumeRamp([]), false);
});

test('a muscle group starting from nothing is not ramping', () => {
  assert.equal(detectVolumeRamp([0, 0, 0, 0, 6, 8]), false);
});

test('only the six most recent weeks are read', () => {
  assert.equal(detectVolumeRamp([100, 100, 100, 10, 10, 10, 10, 15, 16]), true);
});

// --- the cadence caps ---

test('a stall prescribes 90% of working weight for seven days', () => {
  assert.deepEqual(advisory(), {
    reason: 'stall',
    exerciseId: 'bench',
    factor: 0.9,
    days: 7,
  });
});

test('the master toggle silences everything', () => {
  assert.equal(advisory({ enabled: false }), null);
});

test('a lift that set a PR this session is never flagged', () => {
  assert.equal(advisory({ prThisSession: true }), null);
});

test('nothing shows inside the first 28 days of history', () => {
  assert.equal(advisory({ historyStartedAt: NOW - 10 * DAY }), null);
  assert.equal(advisory({ historyStartedAt: NOW - 27 * DAY }), null);
  assert.ok(advisory({ historyStartedAt: NOW - 28 * DAY }) !== null);
});

test('a user with no history at all is never flagged', () => {
  assert.equal(advisory({ historyStartedAt: null }), null);
});

test('a card shown three days ago holds the next one back', () => {
  assert.equal(advisory({ lastShownAt: NOW - 3 * DAY }), null);
});

test('a card shown exactly fourteen days ago lets the next one through', () => {
  assert.ok(advisory({ lastShownAt: NOW - 14 * DAY }) !== null);
});

test('a lift dismissed two weeks ago stays silent', () => {
  assert.equal(advisory({ exercises: [stalledLift({ dismissedAt: NOW - 14 * DAY })] }), null);
});

test('a lift dismissed seven weeks ago can be flagged again', () => {
  assert.ok(advisory({ exercises: [stalledLift({ dismissedAt: NOW - 49 * DAY })] }) !== null);
});

test('dismissing one lift does not silence another', () => {
  const advice = advisory({
    exercises: [
      stalledLift({ dismissedAt: NOW - 3 * DAY }),
      stalledLift({ exerciseId: 'ohp' }),
    ],
  });
  assert.equal(advice?.exerciseId, 'ohp');
});

test('a lift needs six sessions of history before its stall can show', () => {
  const thin = history([70, 75, 75, 75, 75]);
  assert.equal(detectStall(thin, NOW), true);
  assert.equal(advisory({ exercises: [stalledLift({ sessions: thin })] }), null);
});

// --- choosing the one card ---

test('a volume ramp asks to hold the weight rather than to go lighter', () => {
  assert.deepEqual(advisory({ exercises: [rampingLift()] }), {
    reason: 'volume-ramp',
    exerciseId: 'squat',
    factor: 1,
    days: 7,
  });
});

test('a stall outranks a volume ramp', () => {
  const advice = advisory({ exercises: [rampingLift(), stalledLift()] });
  assert.equal(advice?.reason, 'stall');
  assert.equal(advice?.exerciseId, 'bench');
});

test('when several lifts have stalled, the one flat longest wins', () => {
  const advice = advisory({
    exercises: [stalledLift(), stalledLift({ exerciseId: 'row', sessions: history(FLAT, 20) })],
  });
  assert.equal(advice?.exerciseId, 'row');
});

test('a lift that is progressing normally says nothing', () => {
  assert.equal(advisory({ exercises: [rampingLift({ weeklyVolumes: [10, 10, 10, 10, 10, 11] })] }), null);
});

test('no exercises at all says nothing', () => {
  assert.equal(advisory({ exercises: [] }), null);
});
