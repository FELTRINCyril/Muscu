/** Run with: npm test */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  PALETTES,
  DEFAULT_THEME_ID,
  accentAlpha,
  contrastRatio,
  hueDistance,
  paletteById,
  passesHueRule,
  saturationOf,
  STATUS_HUES,
} from './palettes.ts';

const BG = '#0A0A0B';
const SURFACE3 = '#212127';
const BLACK = '#000000';

test('ships the palettes the design settled on', () => {
  assert.deepEqual(PALETTES.map((p) => p.id), ['ember', 'volt', 'ion', 'chalk']);
  assert.equal(DEFAULT_THEME_ID, 'ember');
  assert.equal(paletteById('ember').accent, '#FF4A1C');
});

test('an unknown stored theme falls back rather than blanking the accent', () => {
  assert.equal(paletteById('tide').id, DEFAULT_THEME_ID);
  assert.equal(paletteById('').id, DEFAULT_THEME_ID);
});

// --- the checks the board requires of any palette ---

test('text on the accent stays readable', () => {
  for (const p of PALETTES) {
    assert.ok(
      contrastRatio(p.accentFg, p.accent) >= 4.5,
      `${p.id}: ${contrastRatio(p.accentFg, p.accent).toFixed(2)} on its own fill`,
    );
  }
});

test('the accent reads against every surface it sits on', () => {
  for (const p of PALETTES) {
    for (const [name, surface] of [['bg', BG], ['surface3', SURFACE3], ['black', BLACK]] as const) {
      assert.ok(
        contrastRatio(p.accent, surface) >= 3,
        `${p.id} on ${name}: ${contrastRatio(p.accent, surface).toFixed(2)}`,
      );
    }
  }
});

test('an accent is far enough in hue from every status colour', () => {
  for (const p of PALETTES) {
    if (p.hueExempt) continue;
    assert.ok(passesHueRule(p.accent), `${p.id} collides with a status colour`);
  }
});

test('a near-grey accent is not judged on hue, because it has none to speak of', () => {
  // Chalk computes as 21° from the drop-set blue on two RGB steps of noise.
  assert.ok(saturationOf('#F4F4F5') < 0.15);
  assert.ok(passesHueRule('#F4F4F5'));
  // A genuinely blue accent is still refused.
  assert.equal(passesHueRule('#4C8DFF'), false);
});

test('ember is the only palette exempt from the hue rule, and knowingly so', () => {
  const exempt = PALETTES.filter((p) => p.hueExempt).map((p) => p.id);
  assert.deepEqual(exempt, ['ember']);
  // Documented reason: it is close to error, which never fills a button.
  assert.ok(hueDistance(paletteById('ember').accent, STATUS_HUES.error) < 30);
});

// --- accentAlpha ---

test('tints the current accent rather than a baked-in orange', () => {
  assert.equal(accentAlpha('#FF4A1C', 0.12), 'rgba(255, 74, 28, 0.12)');
  assert.equal(accentAlpha('#C6F135', 0.4), 'rgba(198, 241, 53, 0.4)');
});

test('a malformed accent still yields a usable colour', () => {
  assert.match(accentAlpha('nonsense', 0.2), /^rgba\(/);
});
