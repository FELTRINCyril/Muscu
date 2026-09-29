/**
 * The bar and plates this user's gym has, for the plate calculator.
 *
 * Kept in SecureStore as one JSON blob, mirroring `lib/bodyweight.ts` and
 * `lib/warmupVolume.ts`. It belongs here rather than in the `settings` table
 * because it describes a *place*, not the account: it never syncs, has no
 * history, and changes when the user changes gym. That also keeps it out of a
 * migration.
 *
 * As with those two, resolve it BEFORE any expo-sqlite transaction — awaiting
 * SecureStore inside one hangs it (see recordStore.ts).
 */
import * as SecureStore from 'expo-secure-store';

import { DEFAULT_BAR_SETUP, parseBarSetup, type BarSetup } from '../domain/plateMath';

const KEY = 'ischys.plateSetup';

/** The stored setup, or the default commercial kg set. Never throws. */
export async function getPlateSetup(): Promise<BarSetup> {
  try {
    return parseBarSetup(await SecureStore.getItemAsync(KEY));
  } catch {
    return DEFAULT_BAR_SETUP;
  }
}

/** Persist the setup. Storage being unavailable costs the edit, not the app. */
export async function setPlateSetup(setup: BarSetup): Promise<void> {
  try {
    await SecureStore.setItemAsync(KEY, JSON.stringify(setup));
  } catch {
    // as above
  }
}
