#!/usr/bin/env node
/**
 * build-widget-art.mjs
 *
 * Rasterises the bundled exercise line-art into an asset catalog the Live
 * Activity widget can read.
 *
 * The widget extension is a separate process with no JS runtime, so it cannot
 * reach `src/data/exerciseArt.generated.ts` — the vector data the app draws
 * from. It needs real images inside its own bundle. This script produces them:
 * one imageset per slug, white silhouette on transparent, @2x and @3x for the
 * card's 46pt thumbnail slot.
 *
 * Only ONE frame is emitted. The card is a still at thumbnail size, and the
 * mid-movement pose (frame 2 of 3) reads as the exercise far better than the
 * start pose, which for most lifts is just a figure standing.
 *
 * Source of truth stays `exerciseArt.generated.ts` — this script imports it, so
 * it can never disagree with what the app draws. Re-run it after
 * `build-exercise-art.mjs`.
 *
 * Usage:
 *   node scripts/build-widget-art.mjs [--dry-run] [--frame=<1|2|3>]
 *
 * No dependencies: plain Node ESM plus `sips`, which ships with macOS and reads
 * SVG. (Rasterising in-process would mean a vector library; a shell-out to a
 * system tool that is already there is cheaper than a new dependency.)
 */

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { ART_FRAMES, ART_VIEWBOX } from '../src/data/exerciseArt.generated.ts';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const FRONTEND_DIR = path.resolve(SCRIPT_DIR, '..');

/** The widget target folder is a synchronized root group in the Xcode project
 *  (see @bacons/apple-targets), so anything dropped in here is compiled into the
 *  extension automatically and survives `expo prebuild`. */
const CATALOG_DIR = path.join(FRONTEND_DIR, 'targets', 'ischys-widget', 'Assets.xcassets');
/** Namespaced, so a slug can never collide with another asset name. */
const GROUP = 'ExerciseArt';
const GROUP_DIR = path.join(CATALOG_DIR, GROUP);

/** The card's thumbnail slot is 46pt; the art is inset inside it. */
const SLOT_PT = 46;
const SCALES = [2, 3];

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const argv = process.argv.slice(2);
const DRY_RUN = argv.includes('--dry-run');
const frameArg = (argv.find((a) => a.startsWith('--frame=')) || '').slice('--frame='.length);

for (const arg of argv) {
  if (arg !== '--dry-run' && !arg.startsWith('--frame=')) fail(`unknown argument: ${arg}`);
}

/** 1-based, to match the upstream `frame-N.svg` naming. Frame 2 is mid-movement. */
const FRAME = frameArg ? Number(frameArg) : 2;
if (!Number.isInteger(FRAME) || FRAME < 1 || FRAME > 3) {
  fail(`--frame must be 1, 2 or 3, got: ${frameArg}`);
}

function fail(message, cause) {
  process.stderr.write(`\nbuild-widget-art: ${message}\n`);
  if (cause) process.stderr.write(`${cause.stack || cause}\n`);
  process.exit(1);
}

const log = (...args) => console.log(...args);

// ---------------------------------------------------------------------------
// Rasterising
// ---------------------------------------------------------------------------

/**
 * A standalone SVG for one frame.
 *
 * `fill-rule="evenodd"` and the white fill mirror `ExerciseArt.tsx` exactly —
 * the frames are silhouettes with cut-out detail, and the non-zero default would
 * fill the cut-outs in. White (rather than the card's tint) because the imageset
 * is a template: iOS keeps only the alpha and recolours the rest.
 */
const svgFor = (d, px) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${ART_VIEWBOX}" width="${px}" height="${px}">` +
  `<path fill="#FFFFFF" fill-rule="evenodd" d="${d}"/></svg>`;

function rasterise(d, px, tmpDir, name) {
  const svgPath = path.join(tmpDir, `${name}.svg`);
  const pngPath = path.join(tmpDir, `${name}.png`);
  fs.writeFileSync(svgPath, svgFor(d, px), 'utf8');
  try {
    execFileSync('sips', ['-s', 'format', 'png', svgPath, '--out', pngPath], { stdio: 'pipe' });
  } catch (err) {
    throw new Error(`sips failed on ${name}: ${err.stderr?.toString().trim() || err.message}`);
  }
  const png = fs.readFileSync(pngPath);
  if (png.length < 128) throw new Error(`${name}: sips produced a suspiciously empty PNG`);
  // PNG magic — proves sips wrote an image rather than passing the SVG through.
  if (png.readUInt32BE(0) !== 0x89504e47) throw new Error(`${name}: output is not a PNG`);
  return png;
}

// ---------------------------------------------------------------------------
// Asset catalog
// ---------------------------------------------------------------------------

const json = (value) => `${JSON.stringify(value, null, 2)}\n`;

const CATALOG_ROOT_CONTENTS = json({ info: { author: 'xcode', version: 1 } });

const GROUP_CONTENTS = json({
  info: { author: 'xcode', version: 1 },
  properties: { 'provides-namespace': true },
});

const imagesetContents = (slug) =>
  json({
    images: SCALES.map((scale) => ({
      filename: `${slug}@${scale}x.png`,
      idiom: 'universal',
      scale: `${scale}x`,
    })),
    info: { author: 'xcode', version: 1 },
    // The card tints the silhouette to match its foreground; only the alpha is
    // used, so the white fill above never reaches the screen.
    properties: { 'template-rendering-intent': 'template' },
  });

/** Write only when the bytes differ, so a re-run leaves git clean. */
function writeIfChanged(file, data) {
  const buf = Buffer.isBuffer(data) ? data : Buffer.from(data, 'utf8');
  if (fs.existsSync(file) && fs.readFileSync(file).equals(buf)) return false;
  fs.writeFileSync(file, buf);
  return true;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function main() {
  const t0 = Date.now();
  log(`build-widget-art${DRY_RUN ? ' (dry run)' : ''} — frame ${FRAME} of 3`);

  const slugs = Object.keys(ART_FRAMES).sort();
  if (slugs.length === 0) fail('ART_FRAMES is empty — run scripts/build-exercise-art.mjs first');
  log(`  slugs: ${slugs.length}, viewBox ${ART_VIEWBOX}`);

  if (DRY_RUN) {
    log(`  would write ${slugs.length * SCALES.length} PNGs into ${path.relative(FRONTEND_DIR, GROUP_DIR)}`);
    return;
  }

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ischys-widget-art-'));
  let bytes = 0;
  let changed = 0;

  try {
    fs.mkdirSync(GROUP_DIR, { recursive: true });
    writeIfChanged(path.join(CATALOG_DIR, 'Contents.json'), CATALOG_ROOT_CONTENTS);
    writeIfChanged(path.join(GROUP_DIR, 'Contents.json'), GROUP_CONTENTS);

    for (const slug of slugs) {
      const frames = ART_FRAMES[slug];
      const d = frames[FRAME - 1] ?? frames[0];
      if (!d) throw new Error(`${slug}: no path data for frame ${FRAME}`);

      const dir = path.join(GROUP_DIR, `${slug}.imageset`);
      fs.mkdirSync(dir, { recursive: true });
      if (writeIfChanged(path.join(dir, 'Contents.json'), imagesetContents(slug))) changed++;

      for (const scale of SCALES) {
        const png = rasterise(d, SLOT_PT * scale, tmpDir, `${slug}@${scale}x`);
        bytes += png.length;
        if (writeIfChanged(path.join(dir, `${slug}@${scale}x.png`), png)) changed++;
      }
    }

    // Drop imagesets for slugs the art no longer covers, so a shrunk catalog
    // does not leave orphans shipping in the bundle forever.
    const keep = new Set(slugs.map((s) => `${s}.imageset`));
    let pruned = 0;
    for (const entry of fs.readdirSync(GROUP_DIR)) {
      if (entry === 'Contents.json' || entry === '.DS_Store') continue;
      if (keep.has(entry)) continue;
      fs.rmSync(path.join(GROUP_DIR, entry), { recursive: true, force: true });
      pruned++;
    }

    log('');
    log(`  imagesets:   ${slugs.length}`);
    log(`  PNGs:        ${slugs.length * SCALES.length} (${SCALES.map((s) => `${SLOT_PT * s}px`).join(', ')})`);
    log(`  PNG bytes:   ${(bytes / 1024).toFixed(1)} KB`);
    log(`  files rewritten: ${changed}${pruned ? `, pruned ${pruned} stale imageset(s)` : ''}`);
    log(`  written to:  ${path.relative(FRONTEND_DIR, GROUP_DIR)}`);
    log(`  done in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
}

try {
  main();
} catch (err) {
  fail(err.message, err);
}
