/**
 * Exercise artwork — a short line-art loop of the movement.
 *
 * The frames are ordered positions (start → mid → end), cross-faded on a slow
 * cycle so the figure reads as one rep rather than a slideshow. Frames are
 * stacked and only their opacity animates, so there is no layout work per tick.
 *
 * Honours Reduce Motion: the loop is replaced by a still of the first frame,
 * which is the position the exercise is normally illustrated at.
 */
import { useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, Animated, StyleSheet, View, type ViewStyle } from 'react-native';
import Svg, { Path } from 'react-native-svg';

import { color } from '../theme/tokens';

/** How long each frame is held before cross-fading to the next. */
const HOLD_MS = 900;
/** Cross-fade duration. Long enough to read as motion, short enough to feel deliberate. */
const FADE_MS = 260;

type Props = {
  /** Path `d` strings, in order. A single frame renders as a still. */
  frames: readonly string[];
  viewBox: string;
  size: number;
  /** Stroke/fill colour. Defaults to primary text so it sits on any dark surface. */
  tint?: string;
  /** Set false to hold the first frame (e.g. in a dense list). */
  animate?: boolean;
  style?: ViewStyle;
};

export function ExerciseArt({
  frames,
  viewBox,
  size,
  tint = color.text1,
  animate = true,
  style,
}: Props) {
  const [reduceMotion, setReduceMotion] = useState(false);
  useEffect(() => {
    let cancelled = false;
    AccessibilityInfo.isReduceMotionEnabled()
      .then((on) => {
        if (!cancelled) setReduceMotion(on);
      })
      .catch(() => {});
    const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => {
      cancelled = true;
      sub.remove();
    };
  }, []);

  const looping = animate && !reduceMotion && frames.length > 1;

  // One opacity per frame; frame 0 starts visible.
  const opacities = useRef<Animated.Value[]>([]);
  if (opacities.current.length !== frames.length) {
    opacities.current = frames.map((_, i) => new Animated.Value(i === 0 ? 1 : 0));
  }

  useEffect(() => {
    if (!looping) {
      // Snap back to the first frame when the loop is off.
      opacities.current.forEach((v, i) => v.setValue(i === 0 ? 1 : 0));
      return;
    }
    let active = 0;
    const timer = setInterval(() => {
      const next = (active + 1) % frames.length;
      Animated.parallel([
        Animated.timing(opacities.current[next], {
          toValue: 1,
          duration: FADE_MS,
          useNativeDriver: true,
        }),
        Animated.timing(opacities.current[active], {
          toValue: 0,
          duration: FADE_MS,
          useNativeDriver: true,
        }),
      ]).start();
      active = next;
    }, HOLD_MS);
    return () => clearInterval(timer);
  }, [looping, frames.length]);

  return (
    <View style={[{ width: size, height: size }, style]} pointerEvents="none">
      {frames.map((d, i) => (
        <Animated.View
          key={i}
          style={[StyleSheet.absoluteFill, { opacity: opacities.current[i] }]}
        >
          <Svg width={size} height={size} viewBox={viewBox}>
            <Path d={d} fill={tint} fillRule="evenodd" />
          </Svg>
        </Animated.View>
      ))}
    </View>
  );
}
