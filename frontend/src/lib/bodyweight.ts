/**
 * The user's current bodyweight, in kilograms — the mass that bodyweight
 * movements (push-ups, pull-ups, dips…) move, so it can count toward volume.
 *
 * Kept in SecureStore as a single value the user sets manually or pulls from
 * Apple Health. Stored in kg to match the volume math and the schema (all
 * weights are kg internally; the UI converts for display). At finish the current
 * value is snapshotted onto the workout (`workouts.bodyweight_kg`) so past
 * sessions keep the mass they were actually performed at; live and recomputed
 * views fall back to this current value when a workout has no snapshot.
 */
import * as SecureStore from 'expo-secure-store';

const KEY = 'ischys.bodyweightKg';

/** Plausible human bodyweight bounds (kg). Outside this, treat as unset. */
const BW_MIN = 20;
const BW_MAX = 500;

const inRange = (n: number): boolean => Number.isFinite(n) && n >= BW_MIN && n <= BW_MAX;

/** The stored bodyweight in kg, or null when unset (or stored out of range). */
export async function getBodyweightKg(): Promise<number | null> {
  const raw = await SecureStore.getItemAsync(KEY);
  if (raw == null) return null;
  const n = Number(raw);
  return inRange(n) ? n : null;
}

/** Persist a bodyweight (kg), or clear it with null. Out-of-range values are ignored. */
export async function setBodyweightKg(kg: number | null): Promise<void> {
  if (kg == null) {
    await SecureStore.deleteItemAsync(KEY);
    return;
  }
  if (!inRange(kg)) return;
  // One decimal is plenty for bodyweight; avoids float noise in the stored string.
  await SecureStore.setItemAsync(KEY, String(Math.round(kg * 10) / 10));
}

/**
 * The bodyweight to use for one workout's volume: its snapshot if it has one,
 * else the current setting, else 0 (bodyweight then contributes nothing — the
 * pre-feature behaviour, so nothing changes until the user sets a bodyweight).
 */
export function resolveWorkoutBodyweight(
  snapshotKg: number | null | undefined,
  currentKg: number | null | undefined,
): number {
  return snapshotKg ?? currentKg ?? 0;
}
