/**
 * Exercise-name conventions used by other trackers' exports. Pure — no DB or
 * native imports, so `node --test` can run it.
 */
import type { ExerciseEquipment } from '../api/workouts.ts';

/**
 * Equipment words other exports put in a trailing parenthetical, mapped onto our
 * own vocabulary. Deliberately conservative: an unlisted suffix yields null rather
 * than a guess, because a wrong equipment label changes warm-up rounding and the
 * bar rung, and blocks a legitimate duplicate merge.
 */
const EQUIPMENT_BY_SUFFIX: Record<string, ExerciseEquipment> = {
  barbell: 'barbell',
  dumbbell: 'dumbbell',
  dumbbells: 'dumbbell',
  machine: 'machine',
  'smith machine': 'machine',
  'machine or cable': 'machine',
  cable: 'cable',
  bodyweight: 'bodyweight',
  'body weight': 'bodyweight',
  kettlebell: 'kettlebell',
  band: 'band',
  'resistance band': 'band',
};

/**
 * Equipment encoded as a trailing parenthetical — "Deadlift (Barbell)" — or null.
 *
 * Imported exercises used to be stamped `equipment: 'other'` wholesale. That left
 * them unfilterable, and it silently suppressed the duplicate-merge flow, which
 * requires equipment to match before it will offer a name-based merge: an imported
 * "Deadlift (Barbell)" could never be paired with the catalog's "Barbell Deadlift".
 * The name itself is left untouched — it is the user's own history.
 */
export function equipmentFromNameSuffix(name: string): ExerciseEquipment | null {
  const m = /\(([^()]+)\)$/.exec(name.trim());
  if (!m) return null;
  const key = m[1].trim().toLowerCase().replace(/\s+/g, ' ');
  return EQUIPMENT_BY_SUFFIX[key] ?? null;
}
