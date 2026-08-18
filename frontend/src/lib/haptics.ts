/**
 * Haptic feedback — fired on the *causal* event and reserved for moments that
 * earn it (a set logged, a PR, a snap, a destructive confirm). See the
 * apple-design skill §13: causality, harmony (same frame as the visual), and
 * utility (over-feedback trains people to ignore all of it).
 *
 * There is no settings context, and haptics fire in hot paths (every set
 * completion), so the user's `haptic_feedback` preference is cached here: loaded
 * once at startup and updated when the toggle changes. `impactAsync` etc. are
 * fire-and-forget — never awaited on the interaction path.
 */
import * as Haptics from 'expo-haptics';

let enabled = true;

/** Keep the cached preference in sync (call on settings load + on toggle). */
export function setHapticsEnabled(value: boolean): void {
  enabled = value;
}

const impact = (style: Haptics.ImpactFeedbackStyle) => {
  if (enabled) void Haptics.impactAsync(style).catch(() => {});
};
const notify = (type: Haptics.NotificationFeedbackType) => {
  if (enabled) void Haptics.notificationAsync(type).catch(() => {});
};

export const haptics = {
  /** A committing tap — completing a set, a swipe snapping to delete. */
  commit: () => impact(Haptics.ImpactFeedbackStyle.Medium),
  /** A lighter tap — a swipe crossing its threshold, a minor commit. */
  light: () => impact(Haptics.ImpactFeedbackStyle.Light),
  /** A crisp selection tick — cycling set type, switching a segment/tab. */
  select: () => {
    if (enabled) void Haptics.selectionAsync().catch(() => {});
  },
  /** Achievement — a personal record, finishing a workout. */
  success: () => notify(Haptics.NotificationFeedbackType.Success),
  /** About to do something destructive/irreversible. */
  warning: () => notify(Haptics.NotificationFeedbackType.Warning),
  /** Something failed. */
  error: () => notify(Haptics.NotificationFeedbackType.Error),
};
