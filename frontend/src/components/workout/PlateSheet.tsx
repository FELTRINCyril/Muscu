/**
 * Plate calculator sheet (#64) — what to hang on the bar for the focused set.
 *
 * Barbell only; the caller decides whether to offer it at all. The maths lives
 * in `domain/plateMath`, so this file is only presentation and the choice
 * between two neighbouring weights when the target can't be loaded exactly.
 */
import { useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

import { DraggableSheet } from '../DraggableSheet';
import { PressableScale } from '../PressableScale';
import { color, font } from '../../theme/tokens';
import {
  solvePlates,
  type BarSetup,
  type PlateLoad,
  type PlateStack,
} from '../../domain/plateMath';

type Props = {
  visible: boolean;
  /** The weight currently typed into the set, in kg. NaN/0 when the field is empty. */
  targetKg: number;
  setup: BarSetup;
  /** Commits the chosen weight to the focused input. Does NOT tick the set. */
  onUse: (kg: number) => void;
  /** Opens the bar & plates settings, via the bar chip or "Switch bar". */
  onEditSetup: () => void;
  onClose: () => void;
};

/** Trim a weight for display: 102.5 stays, 100.0 becomes 100. */
const fmtKg = (n: number): string => String(Math.round(n * 100) / 100);

/** "25 + 15 + 1.25" — the stack read out the way a lifter would say it. */
const stackLabel = (plates: PlateStack): string =>
  plates.length === 0
    ? 'bar only'
    : plates.flatMap((p) => Array<number>(p.n).fill(p.kg)).map(fmtKg).join(' + ');

/**
 * Plate size on screen. A 25 and a 1.25 differ by 20x in weight but nothing like
 * that on a real bar, so this is a flattened curve between a floor and a ceiling
 * rather than a true proportion — it reads as "big plate, small plate" at a
 * glance, which is all the drawing is for.
 */
const plateHeight = (kg: number): number => Math.round(Math.min(92, Math.max(34, 92 * (kg / 25) ** 0.42)));
const plateWidth = (kg: number): number => Math.round(Math.min(18, Math.max(7, 18 * (kg / 25) ** 0.45)));

function PlateDrawing({ plates }: { plates: PlateStack }) {
  const each = plates.flatMap((p) => Array<number>(p.n).fill(p.kg));
  if (each.length === 0) return null;
  return (
    <View style={styles.drawing} accessibilityRole="image" accessibilityLabel={stackLabel(plates)}>
      <View style={styles.sleeve} />
      {each.map((kg, i) => (
        <View
          key={`${kg}-${i}`}
          style={[styles.plate, { width: plateWidth(kg), height: plateHeight(kg) }]}
        />
      ))}
    </View>
  );
}

function LoadDetail({ load }: { load: PlateLoad }) {
  return (
    <>
      <View style={styles.eachSideRow}>
        <Text style={styles.eachSideLabel}>EACH SIDE</Text>
        <Text style={styles.eachSideValue}>{fmtKg(load.perSideKg)} kg</Text>
      </View>
      <PlateDrawing plates={load.plates} />
      <View style={styles.plateList}>
        {load.plates.length === 0 ? (
          <Text style={styles.plateRow}>Just the bar</Text>
        ) : (
          load.plates.map((p) => (
            <Text key={p.kg} style={styles.plateRow}>
              {fmtKg(p.kg)} kg × {p.n}
            </Text>
          ))
        )}
      </View>
    </>
  );
}

export function PlateSheet({ visible, targetKg, setup, onUse, onEditSetup, onClose }: Props) {
  const solution = useMemo(
    () => (Number.isFinite(targetKg) && targetKg > 0 ? solvePlates(targetKg, setup) : null),
    [targetKg, setup],
  );

  // Which neighbour is chosen when the target isn't loadable. The lighter one
  // leads: the user asked for a weight, and handing them MORE than they asked
  // for without a tap is the one rounding they can't undo mid-set.
  const [pickHeavier, setPickHeavier] = useState(false);
  useEffect(() => {
    if (visible) setPickHeavier(false);
  }, [visible, targetKg]);

  const rounded = solution?.kind === 'rounded' ? solution : null;
  const chosen: PlateLoad | null =
    solution?.kind === 'exact'
      ? solution.load
      : rounded
        ? ((pickHeavier ? rounded.above : rounded.below) ?? rounded.above ?? rounded.below)
        : null;

  return (
    <DraggableSheet visible={visible} onClose={onClose} sheetStyle={styles.sheet}>
      <View style={styles.grabberWrap}>
        <View style={styles.grabber} />
      </View>

      <View style={styles.header}>
        <Text style={styles.title}>Plates</Text>
        <Pressable onPress={onEditSetup} hitSlop={8} accessibilityRole="button">
          <Text style={styles.barChip}>{fmtKg(setup.barKg)} kg bar</Text>
        </Pressable>
      </View>

      <ScrollView style={styles.body} contentContainerStyle={styles.bodyContent}>
        {solution?.kind === 'below-bar' && (
          <View style={styles.belowBar}>
            <Text style={styles.belowBarTitle}>Lighter than the bar</Text>
            <Text style={styles.belowBarBody}>
              The bar alone is {fmtKg(setup.barKg)} kg.
            </Text>
            <Pressable onPress={onEditSetup} hitSlop={8} accessibilityRole="button">
              <Text style={styles.switchBar}>Switch bar</Text>
            </Pressable>
          </View>
        )}

        {rounded && (
          <>
            <Text style={styles.warning}>
              {`${fmtKg(targetKg)} kg can't be loaded exactly. `}
              {rounded.stepKg > 0
                ? `The smallest plate is ${fmtKg(rounded.stepKg / 2)} kg, so the weight goes up in ${fmtKg(rounded.stepKg)} kg steps.`
                : 'There are no plates set up yet.'}
            </Text>
            <View style={styles.options}>
              {([
                { load: rounded.below, heavier: false, tag: 'LIGHTER' },
                { load: rounded.above, heavier: true, tag: 'HEAVIER' },
              ] as const).map(({ load, heavier, tag }) =>
                load ? (
                  <Pressable
                    key={tag}
                    onPress={() => setPickHeavier(heavier)}
                    style={[styles.option, chosen === load && styles.optionSelected]}
                    accessibilityRole="button"
                    accessibilityState={{ selected: chosen === load }}
                  >
                    <Text style={styles.optionTag}>
                      {chosen === load ? `${tag} · SELECTED` : tag}
                    </Text>
                    <Text style={styles.optionKg}>{fmtKg(load.totalKg)} kg</Text>
                    <Text style={styles.optionDetail}>{stackLabel(load.plates)}</Text>
                  </Pressable>
                ) : null,
              )}
            </View>
          </>
        )}

        {chosen && <LoadDetail load={chosen} />}
      </ScrollView>

      {chosen && (
        <PressableScale
          style={styles.use}
          onPress={() => onUse(chosen.totalKg)}
          accessibilityRole="button"
        >
          <Text style={styles.useText}>Use {fmtKg(chosen.totalKg)} kg</Text>
        </PressableScale>
      )}
    </DraggableSheet>
  );
}

const styles = StyleSheet.create({
  sheet: {
    backgroundColor: color.surface1,
    borderTopLeftRadius: 22,
    borderTopRightRadius: 22,
    paddingBottom: 16,
  },
  grabberWrap: { alignItems: 'center', paddingTop: 8, paddingBottom: 4 },
  grabber: { width: 36, height: 4, borderRadius: 2, backgroundColor: color.surface3 },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  title: { fontFamily: font.titleSemi, fontSize: 20, color: color.text1 },
  barChip: {
    fontFamily: font.monoMedium,
    fontSize: 11,
    letterSpacing: 0.5,
    color: color.text2,
    backgroundColor: color.surface2,
    borderWidth: 1,
    borderColor: color.border,
    borderRadius: 999,
    paddingHorizontal: 10,
    paddingVertical: 5,
    overflow: 'hidden',
  },
  body: { maxHeight: 420 },
  bodyContent: { paddingHorizontal: 16, paddingBottom: 8 },

  warning: { fontFamily: font.bodyRegular, fontSize: 13, lineHeight: 19, color: color.text2 },

  options: { flexDirection: 'row', gap: 10, marginTop: 12 },
  option: {
    flex: 1,
    backgroundColor: color.surface2,
    borderWidth: 1,
    borderColor: color.border,
    borderRadius: 12,
    padding: 12,
  },
  // Selection is a lighter surface and a brighter edge, not accent — the accent
  // in this sheet belongs to Use, which is the action that changes the set.
  optionSelected: { backgroundColor: color.surface3, borderColor: color.text2 },
  optionTag: { fontFamily: font.monoMedium, fontSize: 9, letterSpacing: 0.5, color: color.text3 },
  optionKg: { fontFamily: font.monoSemi, fontSize: 22, color: color.text1, marginTop: 4 },
  optionDetail: { fontFamily: font.monoRegular, fontSize: 11, color: color.text2, marginTop: 2 },

  eachSideRow: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    marginTop: 20,
  },
  eachSideLabel: { fontFamily: font.monoMedium, fontSize: 11, letterSpacing: 0.5, color: color.text3 },
  eachSideValue: { fontFamily: font.monoSemi, fontSize: 20, color: color.text1 },

  drawing: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 100,
    marginTop: 10,
    gap: 3,
  },
  sleeve: { width: 28, height: 6, borderRadius: 3, backgroundColor: color.surface3 },
  plate: { borderRadius: 2, backgroundColor: color.text2 },

  plateList: { marginTop: 10, gap: 2 },
  plateRow: { fontFamily: font.monoRegular, fontSize: 13, color: color.text2 },

  belowBar: { paddingVertical: 8, gap: 6 },
  belowBarTitle: { fontFamily: font.titleSemi, fontSize: 16, color: color.text1 },
  belowBarBody: { fontFamily: font.bodyRegular, fontSize: 13, color: color.text2 },
  switchBar: { fontFamily: font.bodyMedium, fontSize: 14, color: color.text1, marginTop: 4 },

  use: {
    marginHorizontal: 16,
    marginTop: 12,
    height: 50,
    borderRadius: 14,
    backgroundColor: color.accent,
    alignItems: 'center',
    justifyContent: 'center',
  },
  useText: { fontFamily: font.titleSemi, fontSize: 16, color: color.accentFg },
});
