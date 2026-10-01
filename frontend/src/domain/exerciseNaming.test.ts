/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { equipmentFromNameSuffix } from './exerciseNaming.ts';

test('reads equipment out of a trailing parenthetical', () => {
  assert.equal(equipmentFromNameSuffix('Deadlift (Barbell)'), 'barbell');
  assert.equal(equipmentFromNameSuffix('Lat Pulldown (Cable)'), 'cable');
  assert.equal(equipmentFromNameSuffix('Shoulder Press (Machine)'), 'machine');
  assert.equal(equipmentFromNameSuffix('Bench Press (Dumbbell)'), 'dumbbell');
  assert.equal(equipmentFromNameSuffix('Pull Up (Bodyweight)'), 'bodyweight');
  assert.equal(equipmentFromNameSuffix('Swing (Kettlebell)'), 'kettlebell');
  assert.equal(equipmentFromNameSuffix('Row (Smith Machine)'), 'machine');
});

test('tolerates casing and stray spacing', () => {
  assert.equal(equipmentFromNameSuffix('Deadlift ( BARBELL )'), 'barbell');
  assert.equal(equipmentFromNameSuffix('Curl (dumbbells)'), 'dumbbell');
});

test('leaves a name alone when the suffix is not equipment', () => {
  // Guessing here would mislabel the exercise, so we say nothing.
  assert.equal(equipmentFromNameSuffix('Barbell Deadlift'), null);
  assert.equal(equipmentFromNameSuffix('Bicep Curl (21s)'), null);
  assert.equal(equipmentFromNameSuffix('Squat (left leg)'), null);
  assert.equal(equipmentFromNameSuffix(''), null);
});

test('only a trailing parenthetical counts', () => {
  assert.equal(equipmentFromNameSuffix('(Barbell) Deadlift'), null);
});
