/**
 * Ischys design tokens — verbatim from the Design System export (:root vars).
 * The React Native equivalent of the web design tokens. See the
 * ischys-design-handoff skill for the source-of-truth mapping.
 */
import type { TextStyle } from 'react-native';
import * as SecureStore from 'expo-secure-store';

import { accentAlpha, paletteById } from './palettes';

/**
 * The chosen accent, resolved SYNCHRONOUSLY at module load (#72).
 *
 * It has to be synchronous. Every screen builds its styles with
 * `StyleSheet.create` at import time, which captures colour values once — so an
 * accent that arrived later would reach none of them, and the 164 existing
 * `color.accent` sites would each need rewriting to read a context instead.
 * Reading the preference before the first stylesheet exists themes all of them
 * without touching one.
 *
 * The cost is that switching theme applies from the next launch rather than
 * instantly. The design already accepts that shape for the Live Activity, whose
 * accent is fixed for the life of an activity.
 */
function storedPalette() {
  try {
    return paletteById(SecureStore.getItem('ischys.themeId'));
  } catch {
    // Storage unavailable this early — the default accent is a fine answer.
    return paletteById(null);
  }
}

const palette = storedPalette();

export const color = {
  bg: '#0A0A0B', // base
  surface1: '#111113',
  surface2: '#17171A',
  surface3: '#212127',
  /** Set-row backgrounds (Active Workout): completed, and the next set up. */
  setRowDone: '#191920',
  setRowActive: '#151519',
  border: '#26262C',
  hair: '#1D1D22', // subtle divider
  text1: '#F4F4F5', // primary
  text2: '#97979E', // secondary
  text3: '#5B5B63', // tertiary
  accent: palette.accent, // THE action color (complete a set) — reserve it
  accentFg: palette.accentFg, // text/icon on accent
  success: '#2DD881', // PR, target hit
  warning: '#FFC24B', // deload, missed
  error: '#FF4D4D', // failed lift, delete
  // set-type accents
  warmup: '#FFC24B',
  drop: '#4C8DFF',
  failure: '#FF4D4D',
} as const;

/** 4px base grid. */
export const space = {
  xxs: 4,
  xs: 8,
  sm: 12,
  md: 16,
  lg: 24,
  xl: 32,
  xxl: 48,
} as const;

export const radius = {
  sm: 4,
  md: 8,
  lg: 12,
  pill: 999,
} as const;

/**
 * Space Grotesk = interface; JetBrains Mono = ALL data (weights, reps, timers,
 * dates) with tabular figures so digits never shift.
 */
export const font = {
  // interface (Space Grotesk)
  displayBold: 'SpaceGrotesk_700Bold',
  titleSemi: 'SpaceGrotesk_600SemiBold',
  bodyMedium: 'SpaceGrotesk_500Medium',
  bodyRegular: 'SpaceGrotesk_400Regular',
  // data (JetBrains Mono)
  monoRegular: 'JetBrainsMono_400Regular',
  monoMedium: 'JetBrainsMono_500Medium',
  monoSemi: 'JetBrainsMono_600SemiBold',
  monoBold: 'JetBrainsMono_700Bold',
} as const;

/** Type scale from the Design System (family / size / weight). */
const tabular: TextStyle['fontVariant'] = ['tabular-nums'];
export const type = {
  display: { fontFamily: font.displayBold, fontSize: 44 },
  title: { fontFamily: font.titleSemi, fontSize: 30 },
  heading: { fontFamily: font.titleSemi, fontSize: 20 },
  body: { fontFamily: font.bodyRegular, fontSize: 16 },
  label: { fontFamily: font.monoMedium, fontSize: 11, letterSpacing: 0.5 }, // SET · PREV · KG · REPS
  data: { fontFamily: font.monoMedium, fontSize: 28, fontVariant: tabular }, // 82.5 × 8
} satisfies Record<string, TextStyle>;

/** Minimum thumb-safe tap target (Design System principle). */
export const TAP_TARGET = 44;

/**
 * The current accent at an opacity — the replacement for the hardcoded
 * `rgba(255,74,28,…)` tints, which theming could not see. Without this the tab
 * pill would stay orange under any other palette.
 */
export function accentA(alpha: number): string {
  return accentAlpha(palette.accent, alpha);
}
