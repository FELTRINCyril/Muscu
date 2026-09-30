/** Run with: npm test */
import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import {
  pickerIsSelected,
  pickerIsActive,
  pickerToggle,
  registerPicker,
  resetPicker,
} from './exercisePicker.ts';

const ex = (id: string) => ({ id, name: id }) as never;

/** A stand-in picker holding its own selection, as the library screen does. */
function fakePicker() {
  const sel = new Set<string>();
  return {
    sel,
    bridge: {
      isSelected: (id: string) => sel.has(id),
      toggle: (e: { id: string }) => {
        if (sel.has(e.id)) sel.delete(e.id);
        else sel.add(e.id);
      },
    },
  };
}

beforeEach(() => resetPicker());

test('no picker mounted means nothing is selected and nothing is toggled', () => {
  assert.equal(pickerIsActive(), false);
  assert.equal(pickerIsSelected('a'), false);
  assert.equal(pickerToggle(ex('a')), false);
});

test('a mounted picker answers for its own selection', () => {
  const p = fakePicker();
  registerPicker(p.bridge);
  assert.equal(pickerIsActive(), true);
  assert.equal(pickerIsSelected('a'), false);
  assert.equal(pickerToggle(ex('a')), true);
  assert.equal(pickerIsSelected('a'), true);
});

test('toggling twice returns to unselected', () => {
  const p = fakePicker();
  registerPicker(p.bridge);
  pickerToggle(ex('a'));
  pickerToggle(ex('a'));
  assert.equal(pickerIsSelected('a'), false);
});

test('an unmounted picker stops answering', () => {
  const p = fakePicker();
  const release = registerPicker(p.bridge);
  pickerToggle(ex('a'));
  release();
  assert.equal(pickerIsActive(), false);
  assert.equal(pickerIsSelected('a'), false, 'must not report a dead picker’s selection');
});

test('a stale release does not unregister a newer picker', () => {
  const first = fakePicker();
  const second = fakePicker();
  const staleRelease = registerPicker(first.bridge);
  registerPicker(second.bridge);
  staleRelease();
  assert.equal(pickerIsActive(), true);
  pickerToggle(ex('b'));
  assert.equal(second.sel.has('b'), true);
  assert.equal(first.sel.has('b'), false);
});
