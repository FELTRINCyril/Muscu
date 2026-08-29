/**
 * Settings screen — user preferences (units, timer, haptics), export/import, and
 * about links. Pushed onto the root Stack from Profile.
 * Source of truth: export/ischys-app/Settings.dc.html.
 */
import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { cacheDirectory, writeAsStringAsync } from 'expo-file-system/legacy';
import * as Sharing from 'expo-sharing';
import Svg, { Circle, Path } from 'react-native-svg';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { SettingsOut, SettingsUpdate, Unit } from '../src/api/types';
import {
  countDuplicateGroups,
  exportData,
  getSettings,
  updateSettings,
} from '../src/api/workouts';
import { DraggableSheet } from '../src/components/DraggableSheet';
import { toDisplay, toKg } from '../src/domain/units';
import { getBodyweightKg, setBodyweightKg } from '../src/lib/bodyweight';
import { getCountWarmups, setCountWarmups } from '../src/lib/warmupVolume';
import { setHapticsEnabled } from '../src/lib/haptics';
import { isAvailable as isHealthAvailable, readBodyMass, requestAuthorization as requestHealthAuth } from '../modules/health';
import {
  BellIcon,
  ChevronRightIcon,
  ClockRowIcon,
  CodeIcon,
  DownloadIcon,
  HapticIcon,
  HeartFilledIcon,
  InfoIcon,
  ShieldIcon,
  UnitsIcon,
  UploadIcon,
} from '../src/components/icons';
import { color, font } from '../src/theme/tokens';

const DEFAULT_SETTINGS: SettingsOut = {
  unit: 'kg',
  auto_start_rest_timer: true,
  rest_timer_alerts: true,
  haptic_feedback: true,
};

type SegmentOption<T extends string> = { label: string; value: T };

const UNIT_OPTIONS: SegmentOption<Unit>[] = [
  { label: 'KG', value: 'kg' },
  { label: 'LB', value: 'lb' },
];

/** Merge glyph: two overlapping circles (icons.tsx is owned by another stream). */
function MergeIcon({ size = 19, color: strokeColor, strokeWidth = 2 }: { size?: number; color: string; strokeWidth?: number }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Circle cx={8} cy={8} r={5} stroke={strokeColor} strokeWidth={strokeWidth} fill="none" />
      <Circle cx={16} cy={16} r={5} stroke={strokeColor} strokeWidth={strokeWidth} fill="none" />
    </Svg>
  );
}

/** Slim chevron-left glyph matching the design (viewBox 0 0 9 15). */
function BackChevronLeftIcon({ color: strokeColor }: { color: string }) {
  return (
    <Svg width={9} height={15} viewBox="0 0 9 15">
      <Path
        d="M7 2L2 7.5 7 13"
        stroke={strokeColor}
        strokeWidth={2.2}
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </Svg>
  );
}

export default function Settings() {
  const router = useRouter();
  const insets = useSafeAreaInsets();

  const [settings, setSettings] = useState<SettingsOut>(DEFAULT_SETTINGS);
  const [dupCount, setDupCount] = useState(0);
  const [toast, setToast] = useState<string | null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Bodyweight (kg): counts toward volume for bodyweight movements. Entered in the
  // user's unit; stored + used in kg. `bwOpen`/`bwInput` drive the entry sheet.
  const [bwKg, setBwKg] = useState<number | null>(null);
  const [bwOpen, setBwOpen] = useState(false);
  const [bwInput, setBwInput] = useState('');
  useEffect(() => {
    void getBodyweightKg().then(setBwKg);
  }, []);

  // Warmups-in-volume flag: SecureStore-backed (not a DB `patch()` toggle), loaded
  // once on mount. When on, warmup sets contribute to volume and the best_volume PR.
  const [countWarmups, setCountWarmupsState] = useState(false);
  useEffect(() => {
    void getCountWarmups().then(setCountWarmupsState);
  }, []);

  useEffect(() => {
    let cancelled = false;
    getSettings()
      .then((s) => {
        if (!cancelled) setSettings(s);
        setHapticsEnabled(s.haptic_feedback);
      })
      .catch(() => {
        // Stick with the sensible defaults.
      });
    return () => {
      cancelled = true;
      if (toastTimer.current) clearTimeout(toastTimer.current);
    };
  }, []);

  // Refresh the duplicate count on focus — it changes after a merge lands.
  useFocusEffect(
    useCallback(() => {
      let cancelled = false;
      countDuplicateGroups()
        .then((n) => {
          if (!cancelled) setDupCount(n);
        })
        .catch(() => {});
      return () => {
        cancelled = true;
      };
    }, []),
  );

  /** Local optimistic update + fire-and-forget PATCH; failures are silently ignored. */
  const patch = (delta: SettingsUpdate) => {
    setSettings((s) => ({ ...s, ...delta }));
    if (delta.haptic_feedback !== undefined) setHapticsEnabled(delta.haptic_feedback);
    updateSettings(delta).catch(() => {});
  };

  const showToast = (msg: string) => {
    if (toastTimer.current) clearTimeout(toastTimer.current);
    setToast(msg);
    toastTimer.current = setTimeout(() => setToast(null), 2000);
  };

  const doExport = async (fmt: 'json' | 'csv') => {
    try {
      const content = await exportData(fmt);
      const uri = `${cacheDirectory ?? ''}ischys-export.${fmt}`;
      await writeAsStringAsync(uri, content);
      if (await Sharing.isAvailableAsync()) {
        await Sharing.shareAsync(uri, {
          mimeType: fmt === 'csv' ? 'text/csv' : 'application/json',
          UTI: fmt === 'csv' ? 'public.comma-separated-values-text' : 'public.json',
        });
      } else {
        showToast('Sharing unavailable');
      }
    } catch {
      showToast('Export failed');
    }
  };

  const onExport = () => {
    Alert.alert('Export data', 'Choose a format', [
      { text: 'JSON', onPress: () => doExport('json') },
      { text: 'CSV', onPress: () => doExport('csv') },
      { text: 'Cancel', style: 'cancel' },
    ]);
  };

  const onImport = () => {
    router.push('/import');
  };

  // Bodyweight entry (in the user's unit). Blank input clears it.
  const bwUnitLabel = settings.unit;
  const bwDisplay = bwKg != null ? toDisplay(bwKg, settings.unit) : null;
  const openBw = () => {
    setBwInput(bwDisplay != null ? String(bwDisplay) : '');
    setBwOpen(true);
  };
  const saveBw = async () => {
    const trimmed = bwInput.trim();
    if (trimmed === '') {
      await setBodyweightKg(null);
      setBwKg(null);
      setBwOpen(false);
      return;
    }
    const n = parseFloat(trimmed.replace(',', '.'));
    if (!Number.isFinite(n)) {
      setBwOpen(false);
      return;
    }
    const kg = toKg(n, settings.unit);
    await setBodyweightKg(kg);
    setBwKg(await getBodyweightKg()); // re-read: rejects out-of-range, so UI mirrors what's stored
    setBwOpen(false);
  };
  const pullBwFromHealth = async () => {
    // Ensure the bodyweight read is offered — a user who connected Health before
    // this existed won't have granted it, and iOS only prompts for undecided types.
    await requestHealthAuth();
    const kg = await readBodyMass();
    if (kg == null) {
      showToast('No bodyweight in Apple Health');
      return;
    }
    const disp = toDisplay(kg, settings.unit);
    setBwInput(disp != null ? String(Math.round(disp * 10) / 10) : '');
  };

  return (
    <View style={styles.root}>
      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={[
          styles.scrollContent,
          { paddingTop: 116 + insets.top },
        ]}
      >
        {/* TRAINING */}
        <Section title="TRAINING">
          <SegmentRow
            icon={<UnitsIcon size={20} color={color.text2} />}
            label="Units"
            options={UNIT_OPTIONS}
            value={settings.unit}
            onChange={(v) => patch({ unit: v })}
            isLast={false}
          />
          <ToggleRow
            icon={<ClockRowIcon size={20} color={color.text2} strokeWidth={2} />}
            label="Auto-start rest timer"
            value={settings.auto_start_rest_timer}
            onChange={(v) => patch({ auto_start_rest_timer: v })}
            isLast={false}
          />
          <ToggleRow
            icon={<BellIcon size={20} color={color.text2} />}
            label="Rest timer alerts"
            value={settings.rest_timer_alerts}
            onChange={(v) => patch({ rest_timer_alerts: v })}
            isLast={false}
          />
          <ToggleRow
            icon={<HapticIcon size={20} color={color.text2} />}
            label="Haptic feedback"
            value={settings.haptic_feedback}
            onChange={(v) => patch({ haptic_feedback: v })}
            isLast={false}
          />
          <ToggleRow
            icon={<WarmupIcon size={20} color={color.text2} />}
            label="Count warmups in volume"
            value={countWarmups}
            onChange={(v) => {
              setCountWarmupsState(v);
              void setCountWarmups(v);
            }}
            isLast={false}
          />
          <LinkRow
            icon={<BodyweightIcon size={20} color={color.text2} />}
            label="Bodyweight"
            sub="Counts toward volume for bodyweight moves"
            value={bwDisplay != null ? `${bwDisplay} ${bwUnitLabel}` : 'Not set'}
            onPress={openBw}
            isLast
          />
        </Section>

        {/* SERVER */}
        <Section title="DEVICE">
          <LinkRow
            icon={<HeartFilledIcon size={20} color={color.text2} />}
            label="Apple Health"
            sub="Save finished workouts to Fitness"
            onPress={() => router.push('/health')}
            isLast
          />
        </Section>

        <Section title="DATA">
          <LinkRow
            icon={<UploadIcon size={20} color={color.text2} />}
            label="Export data"
            value="CSV / JSON"
            onPress={onExport}
            isLast={false}
          />
          <LinkRow
            icon={<DownloadIcon size={20} color={color.text2} />}
            label="Import workout"
            value="CSV / JSON"
            onPress={onImport}
            isLast={false}
          />
          <MergeRow count={dupCount} onPress={() => router.push('/merge-duplicates')} />
        </Section>

        {/* ABOUT */}
        <Section title="ABOUT">
          <LinkRow
            icon={<ShieldIcon size={20} color={color.text2} />}
            label="Privacy"
            value="On-device"
            onPress={() => {
              Alert.alert(
                'Privacy',
                'All your workout data lives on this device only. Nothing is sent to any server or third party. It backs up with your device (iCloud) like any other app.',
              );
            }}
            isLast={false}
          />
          <LinkRow
            icon={<CodeIcon size={20} color={color.text2} />}
            label="Source code"
            value="GitHub"
            onPress={() => {
              Linking.openURL('https://github.com/ischys-app/Ischys').catch(() => {});
            }}
            isLast={false}
          />
          <LinkRow
            icon={<InfoIcon size={20} color={color.text2} />}
            label="About Ischys"
            value="v0.1"
            onPress={() => {
              Alert.alert(
                'Ischys · ΙΣΧΥΣ',
                'Self-hosted, privacy-first workout tracker.\n\nversion 0.1.0\n\nΙσχύς — strength.',
              );
            }}
            isLast
          />
        </Section>

        <Text style={styles.footer}>Ischys · ΙΣΧΥΣ · v0.1.0</Text>
      </ScrollView>

      {/* Header (absolute, blurred solid) */}
      <View style={[styles.header, { paddingTop: 54 + insets.top }]}>
        <Pressable
          onPress={() => router.back()}
          style={({ pressed }) => [styles.backBtn, pressed && styles.backBtnPressed]}
          hitSlop={8}
          accessibilityLabel="Back"
          accessibilityRole="button"
        >
          <BackChevronLeftIcon color={color.text2} />
        </Pressable>
        <Text style={styles.title}>Settings</Text>
      </View>

      {toast && (
        <View
          style={[
            styles.toast,
            { bottom: 24 + insets.bottom },
          ]}
          pointerEvents="none"
        >
          <Text style={styles.toastText}>{toast}</Text>
        </View>
      )}

      <DraggableSheet
        visible={bwOpen}
        onClose={() => setBwOpen(false)}
        sheetStyle={[styles.bwSheet, { paddingBottom: Math.max(insets.bottom, 16) }]}
      >
        <View style={styles.bwGrabberWrap}>
          <View style={styles.bwGrabber} />
        </View>
        <View style={styles.bwBody}>
          <Text style={styles.bwTitle}>Bodyweight</Text>
          <Text style={styles.bwText}>
            Used to count bodyweight movements — pull-ups, dips, push-ups — toward your volume.
            It&apos;s snapshotted onto each workout, so changing it never rewrites past sessions.
          </Text>
          <View style={styles.bwInputRow}>
            <TextInput
              style={styles.bwInput}
              value={bwInput}
              onChangeText={setBwInput}
              keyboardType="decimal-pad"
              placeholder="—"
              placeholderTextColor={color.text3}
              autoFocus
              returnKeyType="done"
              onSubmitEditing={saveBw}
              accessibilityLabel="Bodyweight value"
            />
            <Text style={styles.bwUnit}>{bwUnitLabel}</Text>
          </View>
          {isHealthAvailable() && (
            <Pressable
              onPress={pullBwFromHealth}
              style={({ pressed }) => [styles.bwHealth, pressed && styles.bwHealthPressed]}
              accessibilityRole="button"
            >
              <HeartFilledIcon size={14} color={color.drop} />
              <Text style={styles.bwHealthText}>Use Apple Health</Text>
            </Pressable>
          )}
          <Pressable
            onPress={saveBw}
            style={({ pressed }) => [styles.bwSave, pressed && styles.bwSavePressed]}
            accessibilityRole="button"
          >
            <Text style={styles.bwSaveText}>Save</Text>
          </Pressable>
        </View>
      </DraggableSheet>
    </View>
  );
}

/** Flame glyph for the Count-warmups-in-volume row. */
function WarmupIcon({ size = 20, color: c }: { size?: number; color: string }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
      <Path
        d="M12 3c1 3-1.5 4.5-1.5 7A3.5 3.5 0 0 0 14 13c.3-.7.3-1.5 0-2 2 1 3.5 3 3.5 5.5a5.5 5.5 0 1 1-11 0C6.5 8.5 12 8 12 3Z"
        stroke={c}
        strokeWidth={1.8}
        strokeLinejoin="round"
      />
    </Svg>
  );
}

/** Bathroom-scale glyph for the Bodyweight row. */
function BodyweightIcon({ size = 20, color: c }: { size?: number; color: string }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
      <Path
        d="M4 5h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z"
        stroke={c}
        strokeWidth={1.8}
      />
      <Path d="M12 8v2.5M9.5 8.5l2 2M14.5 8.5l-2 2" stroke={c} strokeWidth={1.8} strokeLinecap="round" />
      <Circle cx={12} cy={11.5} r={1.2} fill={c} />
    </Svg>
  );
}

// --- Section + Rows -------------------------------------------------------

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      <View style={styles.card}>{children}</View>
    </View>
  );
}

function RowShell({
  icon,
  label,
  sub,
  danger,
  isLast,
  right,
  onPress,
}: {
  icon: React.ReactNode;
  label: string;
  sub?: string;
  danger?: boolean;
  isLast: boolean;
  right?: React.ReactNode;
  onPress?: () => void;
}) {
  const content = (
    <View style={[styles.row, !isLast && styles.rowDivider]}>
      <View style={styles.rowIcon}>{icon}</View>
      <View style={styles.rowLabelCol}>
        <Text
          style={[
            styles.rowLabel,
            danger && { color: color.error },
          ]}
          numberOfLines={1}
        >
          {label}
        </Text>
        {!!sub && <Text style={styles.rowSub}>{sub}</Text>}
      </View>
      {right}
    </View>
  );
  if (onPress) {
    return (
      <Pressable
        onPress={onPress}
        style={({ pressed }) => [pressed && styles.rowPressed]}
        accessibilityRole="button"
        accessibilityLabel={label}
      >
        {content}
      </Pressable>
    );
  }
  return content;
}

function ToggleRow({
  icon,
  label,
  value,
  onChange,
  isLast,
}: {
  icon: React.ReactNode;
  label: string;
  value: boolean;
  onChange: (next: boolean) => void;
  isLast: boolean;
}) {
  return (
    <RowShell
      icon={icon}
      label={label}
      isLast={isLast}
      onPress={() => onChange(!value)}
      right={
        <View
          style={[
            styles.toggleTrack,
            { backgroundColor: value ? color.accent : color.surface3 },
          ]}
        >
          <View
            style={[
              styles.toggleKnob,
              { left: value ? 21 : 3 },
            ]}
          />
        </View>
      }
    />
  );
}

function SegmentRow<T extends string>({
  icon,
  label,
  options,
  value,
  onChange,
  isLast,
}: {
  icon: React.ReactNode;
  label: string;
  options: SegmentOption<T>[];
  value: T;
  onChange: (next: T) => void;
  isLast: boolean;
}) {
  return (
    <RowShell
      icon={icon}
      label={label}
      isLast={isLast}
      right={
        <View style={styles.segment}>
          {options.map((opt) => {
            const selected = opt.value === value;
            return (
              <Pressable
                key={opt.value}
                onPress={() => onChange(opt.value)}
                style={[
                  styles.segmentOption,
                  selected && styles.segmentOptionSelected,
                ]}
                accessibilityRole="button"
                accessibilityLabel={opt.label}
              >
                <Text
                  style={[
                    styles.segmentText,
                    selected && styles.segmentTextSelected,
                  ]}
                >
                  {opt.label}
                </Text>
              </Pressable>
            );
          })}
        </View>
      }
    />
  );
}

function LinkRow({
  icon,
  label,
  value,
  sub,
  onPress,
  isLast,
  danger,
}: {
  icon: React.ReactNode;
  label: string;
  /** Optional trailing value; rows like Apple Health show only a chevron. */
  value?: string;
  sub?: string;
  onPress: () => void;
  isLast: boolean;
  danger?: boolean;
}) {
  return (
    <RowShell
      icon={icon}
      label={label}
      sub={sub}
      danger={danger}
      isLast={isLast}
      onPress={onPress}
      right={
        <View style={styles.linkRight}>
          {!!value && <Text style={styles.linkValue}>{value}</Text>}
          <ChevronRightIcon size={15} color={color.text3} strokeWidth={2.2} />
        </View>
      }
    />
  );
}

/**
 * Merge-duplicates row (board M1): sub-labelled, with an accent count pill that
 * appears only when duplicates were detected, plus a chevron. Last in DATA.
 */
function MergeRow({ count, onPress }: { count: number; onPress: () => void }) {
  return (
    <RowShell
      icon={<MergeIcon size={19} color={color.text2} />}
      label="Merge duplicates"
      sub="Same lift saved twice"
      isLast
      onPress={onPress}
      right={
        <View style={styles.linkRight}>
          {count > 0 && (
            <View style={styles.countPill}>
              <Text style={styles.countPillText}>{count}</Text>
            </View>
          )}
          <ChevronRightIcon size={15} color={color.text3} strokeWidth={2.2} />
        </View>
      }
    />
  );
}

// --- Styles ---------------------------------------------------------------

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: color.bg },

  // Header
  header: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 20,
    backgroundColor: 'rgba(10,10,11,0.9)',
    borderBottomWidth: 1,
    borderBottomColor: color.hair,
    paddingHorizontal: 16,
    paddingBottom: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  backBtn: {
    width: 34,
    height: 34,
    borderRadius: 9,
    backgroundColor: color.surface2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  backBtnPressed: { opacity: 0.7 },
  title: {
    fontFamily: font.titleSemi,
    fontSize: 17,
    fontWeight: '600',
    letterSpacing: -0.17,
    color: color.text1,
  },

  // Scroll
  scrollContent: {
    paddingHorizontal: 16,
    paddingBottom: 40,
  },

  // Section
  section: { marginBottom: 24 },
  sectionTitle: {
    fontFamily: font.monoRegular,
    fontSize: 11,
    letterSpacing: 1.54,
    color: color.text3,
    textTransform: 'uppercase',
    paddingLeft: 2,
    paddingRight: 2,
    paddingBottom: 10,
  },
  card: {
    backgroundColor: color.surface1,
    borderWidth: 1,
    borderColor: color.border,
    borderRadius: 16,
    overflow: 'hidden',
  },

  // Row
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 13,
    paddingVertical: 15,
    paddingHorizontal: 16,
  },
  rowDivider: {
    borderBottomWidth: 1,
    borderBottomColor: color.hair,
  },
  rowPressed: { opacity: 0.85 },
  rowIcon: {
    width: 20,
    height: 20,
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  rowLabelCol: { flex: 1, minWidth: 0 },
  rowLabel: {
    fontFamily: font.bodyMedium,
    fontSize: 14.5,
    fontWeight: '500',
    color: color.text1,
  },
  rowSub: {
    fontFamily: font.monoRegular,
    fontSize: 11,
    color: color.text3,
    marginTop: 2,
  },

  // Toggle
  toggleTrack: {
    width: 44,
    height: 26,
    borderRadius: 999,
    position: 'relative',
    flexShrink: 0,
  },
  toggleKnob: {
    position: 'absolute',
    top: 3,
    width: 20,
    height: 20,
    borderRadius: 999,
    backgroundColor: '#FFFFFF',
  },

  // Segment
  segment: {
    flexDirection: 'row',
    backgroundColor: color.surface2,
    borderRadius: 8,
    padding: 3,
    flexShrink: 0,
  },
  segmentOption: {
    height: 26,
    paddingHorizontal: 12,
    borderRadius: 6,
    alignItems: 'center',
    justifyContent: 'center',
  },
  segmentOptionSelected: {
    backgroundColor: color.surface3,
  },
  segmentText: {
    fontFamily: font.monoSemi,
    fontSize: 12,
    fontWeight: '600',
    color: color.text3,
  },
  segmentTextSelected: {
    color: color.text1,
  },

  // Link right
  linkRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    flexShrink: 0,
  },
  linkValue: {
    fontFamily: font.monoRegular,
    fontSize: 12.5,
    color: color.text3,
    fontVariant: ['tabular-nums'],
  },

  // Bodyweight entry sheet
  bwSheet: {
    backgroundColor: color.surface1,
    borderTopLeftRadius: 22,
    borderTopRightRadius: 22,
    borderTopWidth: 1,
    borderTopColor: color.border,
  },
  bwGrabberWrap: { alignItems: 'center', justifyContent: 'center', paddingTop: 12, paddingBottom: 4 },
  bwGrabber: { width: 40, height: 5, borderRadius: 3, backgroundColor: color.surface3 },
  bwBody: { paddingHorizontal: 20, paddingTop: 10 },
  bwTitle: { fontFamily: font.titleSemi, fontSize: 19, letterSpacing: -0.19, color: color.text1 },
  bwText: {
    fontFamily: font.bodyRegular,
    fontSize: 13.5,
    lineHeight: 20,
    color: color.text2,
    marginTop: 8,
    marginBottom: 18,
  },
  bwInputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    backgroundColor: color.surface2,
    borderWidth: 1,
    borderColor: color.border,
    borderRadius: 14,
    paddingHorizontal: 16,
    height: 56,
  },
  bwInput: {
    flex: 1,
    fontFamily: font.monoSemi,
    fontSize: 26,
    color: color.text1,
    fontVariant: ['tabular-nums'],
    padding: 0,
  },
  bwUnit: { fontFamily: font.monoMedium, fontSize: 14, color: color.text3 },
  bwHealth: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 7,
    height: 44,
    borderRadius: 12,
    marginTop: 10,
  },
  bwHealthPressed: { opacity: 0.6 },
  bwHealthText: { fontFamily: font.titleSemi, fontSize: 14, color: color.drop },
  bwSave: {
    height: 52,
    borderRadius: 14,
    backgroundColor: color.accent,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 8,
  },
  bwSavePressed: { opacity: 0.9 },
  bwSaveText: { fontFamily: font.displayBold, fontSize: 15, letterSpacing: -0.15, color: color.accentFg },

  // Accent count pill (Merge duplicates row)
  countPill: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
    backgroundColor: 'rgba(255,74,28,0.12)',
    borderWidth: 1,
    borderColor: 'rgba(255,74,28,0.3)',
  },
  countPillText: {
    fontFamily: font.monoSemi,
    fontSize: 11.5,
    color: color.accent,
    fontVariant: ['tabular-nums'],
  },

  // Footer
  footer: {
    textAlign: 'center',
    fontFamily: font.monoRegular,
    fontSize: 11,
    color: color.text3,
    marginTop: 8,
    paddingTop: 8,
    paddingBottom: 4,
  },

  // Toast
  toast: {
    position: 'absolute',
    left: 24,
    right: 24,
    alignItems: 'center',
  },
  toastText: {
    fontFamily: font.monoMedium,
    fontSize: 12,
    color: color.text1,
    backgroundColor: color.surface2,
    borderWidth: 1,
    borderColor: color.border,
    borderRadius: 999,
    paddingHorizontal: 16,
    paddingVertical: 10,
    overflow: 'hidden',
  },
});
