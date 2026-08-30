#!/usr/bin/env node
/**
 * build-exercise-art.mjs
 *
 * Fetches CC BY-SA 4.0 exercise line-art from bryllim/workout-guide, matches it
 * strictly against our exercise catalog, and emits a single generated TypeScript
 * module containing the raw SVG path data for each matched movement.
 *
 * Usage:
 *   node scripts/build-exercise-art.mjs [--dry-run] [--latest] [--commit=<sha>]
 *
 *   --dry-run       report what would happen; write nothing
 *   --latest        re-resolve the upstream `main` branch to its current SHA
 *   --commit=<sha>  pin to an explicit commit SHA
 *
 * Without --latest/--commit the script reuses the SHA already recorded in the
 * generated file (so re-runs are reproducible), falling back to resolving
 * `main` on a first run.
 *
 * No dependencies: plain Node ESM, global fetch, node:fs.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const FRONTEND_DIR = path.resolve(SCRIPT_DIR, '..');

const CATALOG_PATH = path.join(FRONTEND_DIR, 'assets', 'catalog', 'catalog.json');
const OVERRIDES_PATH = path.join(SCRIPT_DIR, 'exercise-art-overrides.json');
const OUT_PATH = path.join(FRONTEND_DIR, 'src', 'data', 'exerciseArt.generated.ts');

const REPO = 'bryllim/workout-guide';
const ASSET_PREFIX = 'packages/workout-guide/assets';
const FRAME_COUNT = 3;
const LICENSE = 'CC-BY-SA-4.0';
const LICENSE_URL = 'https://creativecommons.org/licenses/by-sa/4.0/';
const UPSTREAM = 'Everkinetic (CC BY-SA 4.0)';

const CONCURRENCY = 8;
const FETCH_RETRIES = 3;

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const argv = process.argv.slice(2);
const DRY_RUN = argv.includes('--dry-run');
const WANT_LATEST = argv.includes('--latest');
const COMMIT_ARG = (argv.find((a) => a.startsWith('--commit=')) || '').slice('--commit='.length);

for (const arg of argv) {
  if (!['--dry-run', '--latest'].includes(arg) && !arg.startsWith('--commit=')) {
    fail(`unknown argument: ${arg}`);
  }
}
if (COMMIT_ARG && !/^[0-9a-f]{40}$/.test(COMMIT_ARG)) {
  fail(`--commit must be a full 40-character SHA, got: ${COMMIT_ARG}`);
}

function fail(message, cause) {
  process.stderr.write(`\nbuild-exercise-art: ${message}\n`);
  if (cause) process.stderr.write(`${cause.stack || cause}\n`);
  process.exit(1);
}

const log = (...args) => console.log(...args);

// ---------------------------------------------------------------------------
// Matching algorithm
// ---------------------------------------------------------------------------

const STOPWORDS = new Set(['the', 'a', 'with', 'and', 'to', 'on', 'of', 'off', 'for', 'in', 'up', 'your']);

/** Words that change WHICH movement is performed. Never allowed as extras. */
const MOVEMENT_WORDS = new Set([
  'romanian', 'stiff', 'sumo', 'hack', 'split', 'bulgarian', 'front', 'overhead', 'incline',
  'decline', 'reverse', 'behind', 'neck', 'deficit', 'rack', 'pause', 'jump', 'pistol', 'cossack',
  'goblet', 'zercher', 'landmine', 'snatch', 'clean', 'jerk', 'push', 'press', 'hang', 'power',
  'box', 'pin', 'floor', 'spider', 'preacher', 'concentration', 'skull', 'drag', 'pendlay',
  'yates', 'meadows', 'sissy', 'nordic', 'glute', 'calf', 'wrist', 'neutral', 'hammer', 'zottman',
  'pronated', 'supinated',
]);

/** Equipment/grip words that may appear as extras without changing the movement. */
const ALLOWED_EXTRAS = new Set([
  'barbell', 'dumbbell', 'cable', 'machine', 'smith', 'band', 'banded', 'kettlebell', 'ez', 'bar',
  'lever', 'bodyweight', 'weighted', 'assisted', 'alternate', 'alternating', 'one', 'arm', 'single',
  'two', 'close', 'wide', 'medium', 'grip', 'version', 'style', 'standing', 'seated',
]);

/**
 * Gym names write these as one word about as often as two ("Pullups" vs
 * "Pull-Up"), and the upstream art always uses the hyphenated form — so without
 * splitting them, popular movements silently missed their illustration.
 */
const COMPOUNDS = new Map([
  ['pullup', 'pull up'],
  ['pushup', 'push up'],
  ['chinup', 'chin up'],
  ['situp', 'sit up'],
  ['stepup', 'step up'],
  ['signup', 'signup'], // guard: never split a non-movement word
]);

/**
 * Reduce a plural to its singular so "Leg Extensions" reaches `leg-extension`.
 * Deliberately conservative: words ending in a double `s` (press) are left
 * alone, and short words are untouched.
 */
function singularize(w) {
  if (w.length <= 3 || w.endsWith('ss')) return w;
  if (w.endsWith('ies')) return `${w.slice(0, -3)}y`; // flies -> fly
  // crunches -> crunch, presses -> press. The stem must end in a sibilant
  // cluster, NOT a single `s`: "raises" ends in "ses" but is raise + s, and
  // stripping "es" there gave "rais" and lost the match.
  if (/(ch|sh|x|z|ss)es$/.test(w)) return w.slice(0, -2);
  if (w.endsWith('s')) return w.slice(0, -1);
  return w;
}

function tokenize(name) {
  return String(name)
    .toLowerCase()
    .replace(/\([^)]*\)/g, ' ') // strip parenthesised text
    .replace(/[-/]/g, ' ')
    .split(/\s+/)
    .map((w) => w.replace(/[^a-z0-9]/g, ''))
    .map(singularize)
    .flatMap((w) => (COMPOUNDS.get(w) ?? w).split(' '))
    .filter((w) => w.length > 0 && !STOPWORDS.has(w));
}

/**
 * Naming differences token matching cannot bridge: the catalog and the artwork
 * call the same movement different things ("Barbell Curl" / `bicep-curl`,
 * "Hyperextensions" / `back-extension`).
 *
 * Each entry asserts *the same movement*, not merely a similar one — the rule
 * everywhere else here is that a wrong illustration is worse than none. Ordered:
 * the first pattern that matches wins, so put the specific ones first. Only
 * consulted after strict token matching finds nothing.
 */
const ALIASES = [
  // Pulls
  [/\bbent[- ]over\b.*\brow\b/i, 'barbell-row'],
  [/\bt[- ]bar row\b/i, 't-bar-row'],
  [/\bpendlay\b/i, 'pendlay-row'],
  [/\bseated cable row\b/i, 'single-arm-cable-row'],
  [/\bhyperextension/i, 'back-extension'],
  [/\bchin[- ]?up/i, 'chin-up'],
  // Presses
  [/\bbehind the neck\b/i, null], // a different movement; leave it unillustrated
  [/\b(shoulder|military|overhead) press\b/i, 'overhead-press'],
  [/\bpush press\b/i, 'overhead-press'],
  [/\bchest press\b/i, 'machine-chest-press'],
  // Flyes / pec. Rear-delt work is a different movement from a chest fly, so it
  // is matched first and the chest patterns explicitly exclude it.
  [/\b(rear|back)\b.*\bfly(e)?s?\b/i, 'rear-delt-fly'],
  [/\brear delt\b/i, 'rear-delt-fly'],
  [/\bpec deck\b|\bbutterfly\b/i, 'pec-deck'],
  [/\bcable crossover\b/i, 'cable-fly'],
  [/\bfly(e)?s?\b/i, 'dumbbell-fly'],
  // Arms. An overhead extension and a pushdown are different movements.
  [/\boverhead\b.*\btricep(s)? extension\b/i, 'dumbbell-overhead-tricep-extension'],
  [/\bpushdown\b/i, 'rope-tricep-pushdown'],
  [/\bskull ?crusher\b/i, 'dumbbell-skull-crusher'],
  [/\b(barbell|dumbbell|standing|seated) curl\b/i, 'bicep-curl'],
  // Legs. A reverse/rear lunge is not a forward lunge.
  [/\b(reverse|rear)\b.*\blunge\b/i, 'reverse-lunge'],
  [/\b(walking|forward|barbell|dumbbell|bodyweight)\b.*\blunge\b|^lunge/i, 'forward-lunge'],
  // "Dips - Chest Version", "Parallel Bar Dip", "Ring Dips". Excludes the jerk
  // dip, which is a squat-pattern lift that merely shares the word.
  [/\bdips?\b(?!.*squat)/i, 'dip'],
  [/\bstep[- ]ups?\b/i, 'step-up'],
  [/\bwall sit\b/i, 'wall-sit'],
  [/\bglute bridge\b/i, 'glute-bridge'],
  // Core / conditioning
  [/\bbicycle\b.*\b(crunch|kick)/i, 'bicycle-crunch'],
  [/\b(lying|flat bench|hanging)\b.*\bleg raise\b/i, 'lying-leg-raise'],
  [/\bhanging\b.*\bknee raise\b|\bcaptain.?s chair\b/i, 'hanging-knee-raise'],
  [/\bsuperman\b/i, 'superman'],
  [/\bburpee\b/i, 'burpee'],
  [/\bjump rope\b|\brope jump/i, 'jump-rope'],
  [/\bjumping jack\b/i, 'jumping-jack'],
  [/\bmountain climber\b/i, 'high-knees'],
];

/**
 * The aliased slug for a name, when we actually ship that artwork.
 * A `null` slug is a veto: the pattern claims the name and deliberately leaves
 * it unillustrated, stopping a looser pattern below from mismatching it.
 */
function aliasSlug(name, available) {
  for (const [pattern, slug] of ALIASES) {
    if (!pattern.test(name)) continue;
    if (slug === null) return null;
    if (available.has(slug)) return slug;
  }
  return null;
}

/**
 * A candidate matches only when the upstream name's tokens are a subset of ours
 * and every leftover token of ours is a harmless equipment/grip word.
 */
function isSafeMatch(ourTokens, theirTokens) {
  if (theirTokens.length === 0) return false;
  const ourSet = new Set(ourTokens);
  if (!theirTokens.every((t) => ourSet.has(t))) return false;

  const theirSet = new Set(theirTokens);
  const extra = ourTokens.filter((t) => !theirSet.has(t));

  if (extra.some((t) => MOVEMENT_WORDS.has(t))) return false;
  if (extra.some((t) => !ALLOWED_EXTRAS.has(t))) return false;
  return true;
}

// ---------------------------------------------------------------------------
// Network
// ---------------------------------------------------------------------------

async function httpGet(url, { json = false } = {}) {
  let lastError;
  for (let attempt = 1; attempt <= FETCH_RETRIES; attempt++) {
    try {
      const res = await fetch(url, {
        headers: {
          'user-agent': 'ischys-build-exercise-art',
          accept: json ? 'application/vnd.github+json' : 'text/plain,*/*',
        },
      });
      if (!res.ok) {
        const body = (await res.text().catch(() => '')).slice(0, 200);
        throw new Error(`HTTP ${res.status} ${res.statusText} for ${url}${body ? ` — ${body}` : ''}`);
      }
      return json ? await res.json() : await res.text();
    } catch (err) {
      lastError = err;
      if (attempt < FETCH_RETRIES) {
        await new Promise((r) => setTimeout(r, 400 * attempt));
      }
    }
  }
  throw new Error(`failed after ${FETCH_RETRIES} attempts: ${lastError.message}`);
}

async function mapLimit(items, limit, worker) {
  const results = new Array(items.length);
  let cursor = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (true) {
      const i = cursor++;
      if (i >= items.length) return;
      results[i] = await worker(items[i], i);
    }
  });
  await Promise.all(runners);
  return results;
}

// ---------------------------------------------------------------------------
// SVG path extraction + rounding
// ---------------------------------------------------------------------------

function stripNoise(svg) {
  return svg
    .replace(/<\?xml[\s\S]*?\?>/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<!DOCTYPE[\s\S]*?>/gi, '')
    .replace(/<title\b[\s\S]*?<\/title>/gi, '')
    .replace(/<desc\b[\s\S]*?<\/desc>/gi, '');
}

function extractViewBox(svg, label) {
  const m = svg.match(/<svg\b[^>]*\bviewBox\s*=\s*"([^"]+)"/i);
  if (!m) throw new Error(`${label}: no viewBox on <svg>`);
  return m[1].trim().replace(/\s+/g, ' ');
}

function extractPathData(svg, label) {
  const ds = [];
  const pathRe = /<path\b([^>]*)\/?>/gi;
  let m;
  while ((m = pathRe.exec(svg)) !== null) {
    const attrs = m[1];
    const d = attrs.match(/\bd\s*=\s*"([^"]*)"/i);
    if (!d) continue;
    const value = d[1].trim();
    if (value) ds.push(value);
  }
  if (ds.length === 0) throw new Error(`${label}: no <path d="…"> found`);
  return ds;
}

/** Command letters + count of numeric tokens — a fingerprint that rounding must preserve. */
function pathFingerprint(d) {
  const commands = (d.match(/[MmLlHhVvCcSsQqTtAaZz]/g) || []).join('');
  const numbers = (d.match(/-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g) || []).length;
  return `${commands}|${numbers}`;
}

const NUMBER_RE = /-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g;

/**
 * Coordinate precision, in decimal places.
 *
 * The artwork's viewBox is 512 wide and it renders at ~170px on a phone, so one
 * viewBox unit is about a third of a pixel — sub-pixel precision is invisible and
 * costs real bundle size. Integers cut the generated module by ~40%.
 */
const DECIMALS = 0;
const PRECISION = 10 ** DECIMALS;

/** Round every coordinate to `DECIMALS` places, preserving token boundaries. */
function roundPathData(d) {
  let out = '';
  let last = 0;
  let m;
  NUMBER_RE.lastIndex = 0;
  while ((m = NUMBER_RE.exec(d)) !== null) {
    const raw = m[0];
    const start = m.index;
    const end = start + raw.length;

    let text = raw;
    const value = Number(raw);
    if (Number.isFinite(value)) {
      let rounded = String(Math.round(value * PRECISION) / PRECISION);
      if (rounded.includes('e') || rounded.includes('E')) rounded = value.toFixed(DECIMALS);
      // Compact forms: 0.5 -> .5, -0.5 -> -.5
      if (rounded.startsWith('0.')) rounded = rounded.slice(1);
      else if (rounded.startsWith('-0.')) rounded = `-${rounded.slice(2)}`;
      if (rounded === '-0') rounded = '0';
      text = rounded;
    }

    const gap = d.slice(last, start);
    out += gap;

    // In compact path data the '-' or '.' that starts a number doubles as the
    // separator from the previous one. Rounding can drop it (-0.04 -> 0,
    // 1.04 -> 1), which would fuse two numbers into one. Re-separate.
    if (gap === '' && /\d$/.test(out) && /^[\d.]/.test(text)) out += ' ';

    out += text;
    last = end;
  }
  out += d.slice(last);
  return out.trim();
}

function validateRounded(original, rounded, label) {
  if (!/^[Mm]/.test(rounded)) {
    throw new Error(`${label}: rounded path does not start with a moveto command`);
  }
  if (/[MmLlHhVvCcSsQqTtAa]\s*(?=[MmLlHhVvCcSsQqTtAaZz]|$)/.test(rounded)) {
    throw new Error(`${label}: rounded path contains an empty segment`);
  }
  const before = pathFingerprint(original);
  const after = pathFingerprint(rounded);
  if (before !== after) {
    throw new Error(`${label}: rounding changed path structure (${before} -> ${after})`);
  }
}

// ---------------------------------------------------------------------------
// Codegen
// ---------------------------------------------------------------------------

const tsString = (s) => `'${s.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;

function renderModule({ commit, viewBox, perSlugViewBox, frames, byExerciseId }) {
  const slugs = Object.keys(frames).sort();
  const ids = Object.keys(byExerciseId).sort();

  const lines = [];
  lines.push('/** GENERATED by scripts/build-exercise-art.mjs — do not edit by hand.');
  lines.push(` *  Artwork: ${REPO} @ ${commit}, CC BY-SA 4.0 (upstream: Everkinetic).`);
  lines.push(` *  ${LICENSE_URL}`);
  lines.push(' *  Changes: extracted silhouette path data, recolored to currentColor by the');
  lines.push(' *  consumer, coordinates rounded to 1dp.');
  lines.push(' */');
  lines.push('');
  lines.push('export const ART_SOURCE = {');
  lines.push(`  repo: ${tsString(REPO)},`);
  lines.push(`  commit: ${tsString(commit)},`);
  lines.push(`  license: ${tsString(LICENSE)},`);
  lines.push(`  licenseUrl: ${tsString(LICENSE_URL)},`);
  lines.push(`  upstream: ${tsString(UPSTREAM)},`);
  lines.push('} as const;');
  lines.push('');
  lines.push('/** viewBox shared by all frames. */');
  lines.push(`export const ART_VIEWBOX = ${tsString(viewBox)};`);
  lines.push('');

  if (perSlugViewBox) {
    lines.push('/** Frames whose viewBox differs from ART_VIEWBOX. */');
    lines.push('export const ART_VIEWBOX_BY_SLUG: Record<string, string> = {');
    for (const slug of Object.keys(perSlugViewBox).sort()) {
      lines.push(`  ${tsString(slug)}: ${tsString(perSlugViewBox[slug])},`);
    }
    lines.push('};');
    lines.push('');
  }

  lines.push('/** slug -> the `d` attribute of each of the 3 frames, in order. */');
  lines.push('export const ART_FRAMES: Record<string, readonly string[]> = {');
  for (const slug of slugs) {
    lines.push(`  ${tsString(slug)}: [`);
    for (const d of frames[slug]) lines.push(`    ${tsString(d)},`);
    lines.push('  ],');
  }
  lines.push('};');
  lines.push('');
  lines.push('/** catalog exercise id -> slug. */');
  lines.push('export const ART_BY_EXERCISE_ID: Record<string, string> = {');
  for (const id of ids) {
    lines.push(`  ${tsString(id)}: ${tsString(byExerciseId[id])},`);
  }
  lines.push('};');
  lines.push('');

  return lines.join('\n');
}

function readPinnedCommit() {
  if (!fs.existsSync(OUT_PATH)) return null;
  const m = fs.readFileSync(OUT_PATH, 'utf8').match(/commit:\s*'([0-9a-f]{40})'/);
  return m ? m[1] : null;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const t0 = Date.now();
  log(`build-exercise-art${DRY_RUN ? ' (dry run)' : ''}`);

  // --- catalog -------------------------------------------------------------
  if (!fs.existsSync(CATALOG_PATH)) fail(`catalog not found at ${CATALOG_PATH}`);
  let catalog;
  try {
    catalog = JSON.parse(fs.readFileSync(CATALOG_PATH, 'utf8'));
  } catch (err) {
    fail(`catalog.json is not valid JSON`, err);
  }
  const exercises = catalog.exercises;
  if (!Array.isArray(exercises) || exercises.length === 0) fail('catalog.exercises is empty or missing');
  log(`  catalog: ${exercises.length} exercises`);

  // --- overrides -----------------------------------------------------------
  let overrides = {};
  if (fs.existsSync(OVERRIDES_PATH)) {
    try {
      overrides = JSON.parse(fs.readFileSync(OVERRIDES_PATH, 'utf8'));
    } catch (err) {
      fail(`exercise-art-overrides.json is not valid JSON`, err);
    }
  }
  const overrideEntries = Object.entries(overrides).filter(([k]) => !k.startsWith('_'));
  log(`  overrides: ${overrideEntries.length}`);

  // --- resolve commit ------------------------------------------------------
  let commit = COMMIT_ARG || null;
  if (!commit && !WANT_LATEST) commit = readPinnedCommit();
  if (!commit) {
    const head = await httpGet(`https://api.github.com/repos/${REPO}/commits/main`, { json: true });
    commit = head.sha;
    if (!/^[0-9a-f]{40}$/.test(commit || '')) throw new Error(`unexpected SHA from GitHub: ${commit}`);
  }
  log(`  commit: ${commit}`);

  const rawUrl = (p) => `https://raw.githubusercontent.com/${REPO}/${commit}/${p}`;

  // --- upstream slug list (tree API) ---------------------------------------
  const tree = await httpGet(
    `https://api.github.com/repos/${REPO}/git/trees/${commit}?recursive=1`,
    { json: true },
  );
  if (tree.truncated) throw new Error('GitHub tree response was truncated; cannot enumerate slugs reliably');

  const frameRe = new RegExp(`^${ASSET_PREFIX.replace(/\//g, '\\/')}\\/([^/]+)\\/frame-(\\d+)\\.svg$`);
  const framesBySlug = new Map();
  for (const entry of tree.tree) {
    if (entry.type !== 'blob') continue;
    const m = entry.path.match(frameRe);
    if (!m) continue;
    if (!framesBySlug.has(m[1])) framesBySlug.set(m[1], new Set());
    framesBySlug.get(m[1]).add(Number(m[2]));
  }
  const upstreamSlugs = [...framesBySlug.keys()].filter((slug) => {
    const set = framesBySlug.get(slug);
    for (let i = 1; i <= FRAME_COUNT; i++) if (!set.has(i)) return false;
    return true;
  }).sort();
  if (upstreamSlugs.length === 0) throw new Error(`no complete ${FRAME_COUNT}-frame slugs found under ${ASSET_PREFIX}`);
  log(`  upstream slugs fetched: ${upstreamSlugs.length} (${framesBySlug.size} total, complete ${FRAME_COUNT}-frame sets only)`);

  // --- upstream display names (their manifest, falling back to the slug) ----
  const nameBySlug = new Map();
  try {
    const wgManifest = await httpGet(rawUrl('packages/workout-guide/manifest.json'), { json: true });
    for (const item of Array.isArray(wgManifest) ? wgManifest : []) {
      if (item && typeof item.slug === 'string' && typeof item.name === 'string') {
        nameBySlug.set(item.slug, item.name);
      }
    }
  } catch {
    log('  note: upstream manifest.json unavailable — deriving names from slugs');
  }
  const displayName = (slug) => nameBySlug.get(slug) || slug.replace(/-/g, ' ');

  // --- match ---------------------------------------------------------------
  const upstreamTokens = new Map(upstreamSlugs.map((s) => [s, tokenize(displayName(s))]));
  const upstreamSet = new Set(upstreamSlugs);

  const byExerciseId = {};
  const pairs = [];
  let exactlyOne = 0;
  let ambiguous = 0;
  let overrideAdds = 0;
  let aliasAdds = 0;
  let overrideExcludes = 0;
  const overridesSeen = new Set();

  for (const ex of exercises) {
    if (!ex || typeof ex.id !== 'string' || typeof ex.name !== 'string') continue;

    if (Object.prototype.hasOwnProperty.call(overrides, ex.name)) {
      overridesSeen.add(ex.name);
      const forced = overrides[ex.name];
      if (forced === null) {
        overrideExcludes++;
        continue;
      }
      if (typeof forced !== 'string' || !upstreamSet.has(forced)) {
        throw new Error(`override for "${ex.name}" points at unknown upstream slug: ${JSON.stringify(forced)}`);
      }
      byExerciseId[ex.id] = forced;
      pairs.push([ex.name, forced, 'override']);
      overrideAdds++;
      continue;
    }

    const ourTokens = tokenize(ex.name);
    const candidates = upstreamSlugs.filter((slug) => isSafeMatch(ourTokens, upstreamTokens.get(slug)));
    if (candidates.length === 0) {
      // Token matching can't bridge a naming difference — our catalog says
      // "Barbell Curl" where the artwork says "bicep-curl". These are the same
      // movement under a different name, so match on the phrase instead.
      const alias = aliasSlug(ex.name, upstreamSet);
      if (alias) {
        byExerciseId[ex.id] = alias;
        pairs.push([ex.name, alias, 'alias']);
        aliasAdds++;
      }
      continue;
    }

    if (candidates.length === 1) exactlyOne++;
    else ambiguous++;

    // Deterministic tie-break: prefer the most specific (most tokens) candidate,
    // then alphabetical. Every candidate already passed the strict safety rule.
    candidates.sort((a, b) => {
      const d = upstreamTokens.get(b).length - upstreamTokens.get(a).length;
      return d !== 0 ? d : a.localeCompare(b);
    });
    byExerciseId[ex.id] = candidates[0];
    pairs.push([ex.name, candidates[0], candidates.length > 1 ? 'most-specific' : 'unique']);
  }

  for (const [key] of overrideEntries) {
    if (!overridesSeen.has(key)) {
      throw new Error(`override key "${key}" does not match any exercise name in catalog.json`);
    }
  }

  const matchedSlugs = [...new Set(Object.values(byExerciseId))].sort();
  log(
    `  matched: ${Object.keys(byExerciseId).length} exercises -> ${matchedSlugs.length} slugs ` +
    `(${exactlyOne} unique, ${ambiguous} ambiguous resolved to most specific, ` +
    `${overrideAdds} forced by override, ${overrideExcludes} excluded by override)`,
  );

  if (matchedSlugs.length === 0) throw new Error('no exercises matched — refusing to write an empty module');

  if (DRY_RUN) {
    log('\n  sample matches:');
    for (const [name, slug, how] of pairs.slice(0, 15)) log(`    ${name}  ->  ${slug}  [${how}]`);
    log(`\n  would fetch ${matchedSlugs.length * FRAME_COUNT} SVGs and write ${path.relative(FRONTEND_DIR, OUT_PATH)}`);
    log(`  dry run: nothing written (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
    return;
  }

  // --- fetch + extract -----------------------------------------------------
  const jobs = [];
  for (const slug of matchedSlugs) {
    for (let i = 1; i <= FRAME_COUNT; i++) jobs.push({ slug, index: i });
  }
  log(`  fetching ${jobs.length} SVGs…`);

  let downloadedBytes = 0;
  let multiPathFrames = 0;
  const viewBoxes = new Map(); // slug -> viewBox
  const frames = {};

  const fetched = await mapLimit(jobs, CONCURRENCY, async (job) => {
    const p = `${ASSET_PREFIX}/${job.slug}/frame-${job.index}.svg`;
    const svg = await httpGet(rawUrl(p));
    return { ...job, svg, bytes: Buffer.byteLength(svg, 'utf8') };
  });

  for (const item of fetched) {
    const label = `${item.slug}/frame-${item.index}`;
    downloadedBytes += item.bytes;
    const clean = stripNoise(item.svg);

    const viewBox = extractViewBox(clean, label);
    const prior = viewBoxes.get(item.slug);
    if (prior && prior !== viewBox) {
      throw new Error(`${item.slug}: frames disagree on viewBox ("${prior}" vs "${viewBox}")`);
    }
    viewBoxes.set(item.slug, viewBox);

    const ds = extractPathData(clean, label);
    if (ds.length > 1) multiPathFrames++;
    const joined = ds.join(' ');
    const rounded = roundPathData(joined);
    validateRounded(joined, rounded, label);

    if (!frames[item.slug]) frames[item.slug] = [];
    frames[item.slug][item.index - 1] = rounded;
  }

  for (const slug of matchedSlugs) {
    const list = frames[slug];
    if (!list || list.length !== FRAME_COUNT || list.some((d) => !d)) {
      throw new Error(`${slug}: expected ${FRAME_COUNT} non-empty frames, got ${list ? list.filter(Boolean).length : 0}`);
    }
  }

  // --- viewBox consistency across every slug -------------------------------
  const distinct = [...new Set(viewBoxes.values())];
  const counts = new Map();
  for (const vb of viewBoxes.values()) counts.set(vb, (counts.get(vb) || 0) + 1);
  const dominant = [...counts.entries()].sort((a, b) => b[1] - a[1])[0][0];
  let perSlugViewBox = null;
  if (distinct.length > 1) {
    perSlugViewBox = {};
    for (const [slug, vb] of viewBoxes) if (vb !== dominant) perSlugViewBox[slug] = vb;
    log(`  WARNING: ${distinct.length} distinct viewBoxes; ${Object.keys(perSlugViewBox).length} slugs emitted in ART_VIEWBOX_BY_SLUG`);
  }

  // --- write (atomically, only after everything succeeded) -----------------
  const source = renderModule({
    commit,
    viewBox: dominant,
    perSlugViewBox,
    frames,
    byExerciseId,
  });

  fs.mkdirSync(path.dirname(OUT_PATH), { recursive: true });
  const tmp = `${OUT_PATH}.tmp`;
  fs.writeFileSync(tmp, source, 'utf8');
  fs.renameSync(tmp, OUT_PATH);

  const outBytes = Buffer.byteLength(source, 'utf8');

  // --- summary -------------------------------------------------------------
  log('\n  sample matches:');
  for (const [name, slug, how] of pairs.slice(0, 10)) log(`    ${name}  ->  ${slug}  [${how}]`);

  log('');
  log(`  slugs fetched (upstream):   ${upstreamSlugs.length}`);
  log(`  exercises matched:          ${Object.keys(byExerciseId).length}`);
  log(`  slugs emitted:              ${matchedSlugs.length}`);
  log(`  SVGs downloaded:            ${jobs.length} (${(downloadedBytes / 1024).toFixed(1)} KB raw)`);
  log(`  frames with >1 <path>:      ${multiPathFrames}`);
  log(`  viewBox:                    ${dominant}${perSlugViewBox ? ' (+ per-slug overrides)' : ''}`);
  log(`  written:                    ${path.relative(FRONTEND_DIR, OUT_PATH)} (${(outBytes / 1024).toFixed(1)} KB)`);
  log(`  done in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
}

main().catch((err) => fail(err.message, err));
