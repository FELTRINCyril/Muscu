/**
 * Apple Health screen — Settings-adjacent surface that manages the Apple Health
 * integration. Two visual states driven by a local `connected` boolean persisted
 * in SecureStore under `ischys.healthConnected`.
 *
 * Source of truth: design-handoff/design_handoff_release2/boards/Health
 * Permissions.dc.html (board 5a).
 *
 * The core move (Release 2, Need 4): infer from data, never from permission.
 * HealthKit hides read authorisation, so a read switch states *intent* ("what
 * Ischys asks for") and a *receipt* states reality (whether data actually
 * arrived). Writes are the opposite — share auth IS exposed — so the single card
 * splits into two sections: ISCHYS WRITES (real Allowed/Denied) and ISCHYS ASKS
 * HEALTH FOR (the reads, with receipts). Green now lives only on receipts.
 *
 * The real HealthKit binding is guarded behind a dynamic import so this screen
 * renders (and toggles work) on Android / simulators / dev clients that don't
 * ship a native HealthKit module.
 */
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  Alert,
  Linking,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import Animated, { FadeIn, FadeOut, LinearTransition } from 'react-native-reanimated';
import Svg, { Path } from 'react-native-svg';
import * as SecureStore from 'expo-secure-store';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { BackChevronIcon, HeartFilledIcon, ShieldIcon } from '../src/components/icons';
import { fmtAgo, parseIso } from '../src/lib/format';
import { connectHealth, isHealthAvailable } from '../src/lib/healthSync';
import {
  clearReadReceipts,
  getReadReceipt,
  getWriteStatus,
  receiptKind,
  type ReadPref,
  type Receipt,
  type WriteStatus,
} from '../src/lib/healthReceipts';
import { color, font } from '../src/theme/tokens';

// DECISION · HOW MUCH TO SAY ABOUT READS — Option A (recommended): intent switch
// + data receipt. The switch is what Ischys ASKS for; the receipt is what
// arrived. It never claims a grant iOS won't reveal, yet still answers the only
// question the user has ("is this working?"). Option B (switch only) leaves a
// user with no Watch unable to tell why HR is blank; Option C (status + caveat)
// is today's misleading screen with extra words. See board 5a decision block.

// SecureStore keys
const K_CONNECTED = 'ischys.healthConnected';
const K_LAST_SYNC = 'ischys.healthLastSync';
const K_WRITTEN = 'ischys.healthWorkoutsWritten';
const K_PREF = {
  writeWorkouts: 'ischys.healthPref.writeWorkouts',
  readHR: 'ischys.healthPref.readHR',
  readEnergy: 'ischys.healthPref.readEnergy',
} as const;

type PrefKey = keyof typeof K_PREF;

// `readBody` is intentionally gone: body measurements are genuinely not built,
// so the row is omitted rather than shown dead (board 5a behaviour note).
const DEFAULT_PREFS: Record<PrefKey, boolean> = {
  writeWorkouts: true,
  readHR: true,
  readEnergy: true,
};

// A read row's static copy. `offDesc` shows (no status colour) when the switch
// is off; `explainer` is the in-place box revealed on an uncertain row.
const READ_ROWS: {
  pref: ReadPref;
  label: string;
  offDesc: string;
  explainer: string;
}[] = [
  {
    pref: 'readHR',
    label: 'Heart rate',
    offDesc: 'Live BPM from an Apple Watch',
    explainer:
      "This means one of two things, and iOS won't say which: Health is holding the data back, or nothing has recorded any yet. Heart rate needs an Apple Watch worn during the session.",
  },
  {
    pref: 'readEnergy',
    label: 'Active energy',
    offDesc: 'Calories burned per session',
    explainer:
      "This means one of two things, and iOS won't say which: Health is holding the data back, or nothing has recorded any yet. Active energy needs an Apple Watch worn during the session.",
  },
];

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "12 Jun" — the date the user asked (went through the connect prompt). */
function fmtAsked(iso: string | null): string {
  if (!iso) return 'recently';
  const d = parseIso(iso);
  if (Number.isNaN(d.getTime())) return 'recently';
  return `${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

/** iOS can't deep-link a specific Health page; this at least opens the app. */
function openHealthApp() {
  Linking.openURL('x-apple-health://').catch(() => {
    // Best-effort — Health may be unavailable (simulator / Android).
  });
}

export default function Health() {
  const router = useRouter();
  const insets = useSafeAreaInsets();

  const [loaded, setLoaded] = useState(false);
  const [connected, setConnectedState] = useState(false);
  const [prefs, setPrefsState] = useState<Record<PrefKey, boolean>>(DEFAULT_PREFS);
  const [receipts, setReceipts] = useState<Record<ReadPref, Receipt | null>>({
    readHR: null,
    readEnergy: null,
  });
  const [writeStatus, setWriteStatus] = useState<WriteStatus>('allowed');
  const [workoutsWritten, setWorkoutsWritten] = useState<number>(0);
  const [lastSyncIso, setLastSyncIso] = useState<string | null>(null);

  // Load persisted state on mount.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [c, w, ls, ww, rh, re, recHR, recEnergy, ws] = await Promise.all([
        SecureStore.getItemAsync(K_CONNECTED),
        SecureStore.getItemAsync(K_WRITTEN),
        SecureStore.getItemAsync(K_LAST_SYNC),
        SecureStore.getItemAsync(K_PREF.writeWorkouts),
        SecureStore.getItemAsync(K_PREF.readHR),
        SecureStore.getItemAsync(K_PREF.readEnergy),
        getReadReceipt('readHR'),
        getReadReceipt('readEnergy'),
        getWriteStatus(),
      ]);
      if (cancelled) return;
      setConnectedState(c === '1');
      setWorkoutsWritten(w ? Number(w) || 0 : 0);
      setLastSyncIso(ls);
      setPrefsState({
        writeWorkouts: ww == null ? DEFAULT_PREFS.writeWorkouts : ww === '1',
        readHR: rh == null ? DEFAULT_PREFS.readHR : rh === '1',
        readEnergy: re == null ? DEFAULT_PREFS.readEnergy : re === '1',
      });
      setReceipts({ readHR: recHR, readEnergy: recEnergy });
      setWriteStatus(ws);
      setLoaded(true);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const persistConnected = async (v: boolean) => {
    setConnectedState(v);
    if (v) {
      const now = new Date().toISOString();
      await SecureStore.setItemAsync(K_CONNECTED, '1');
      await SecureStore.setItemAsync(K_LAST_SYNC, now);
      setLastSyncIso(now);
    } else {
      await SecureStore.deleteItemAsync(K_CONNECTED);
    }
  };

  const setPref = async (key: PrefKey, next: boolean) => {
    // Turning a read off = Ischys stops asking. iOS keeps its own grant either
    // way — this never "revokes" anything.
    setPrefsState((p) => ({ ...p, [key]: next }));
    await SecureStore.setItemAsync(K_PREF[key], next ? '1' : '0');
  };

  const clearPrefs = async () => {
    await Promise.all([
      SecureStore.deleteItemAsync(K_PREF.writeWorkouts),
      SecureStore.deleteItemAsync(K_PREF.readHR),
      SecureStore.deleteItemAsync(K_PREF.readEnergy),
      SecureStore.deleteItemAsync(K_LAST_SYNC),
      SecureStore.deleteItemAsync(K_WRITTEN),
      clearReadReceipts(),
    ]);
    setPrefsState(DEFAULT_PREFS);
    setReceipts({ readHR: null, readEnergy: null });
    setWriteStatus('allowed');
    setWorkoutsWritten(0);
    setLastSyncIso(null);
  };

  const onConnect = async () => {
    if (!isHealthAvailable()) {
      Alert.alert(
        'Not available',
        'Apple Health needs a device build with HealthKit — it is not available on the simulator or on Android.',
      );
      return;
    }
    // Real HealthKit prompt. The user answering does not tell us what they
    // granted for reads (HealthKit hides read grants), so afterwards the screen
    // shows what data actually arrives instead of a permission list.
    const ok = await connectHealth();
    if (ok) {
      setConnectedState(true);
      setLastSyncIso(new Date().toISOString());
    }
  };

  const onDisconnect = () => {
    Alert.alert(
      'Disconnect Apple Health',
      'Ischys will stop reading and writing Health data. Any records already written stay in Health.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Disconnect',
          style: 'destructive',
          onPress: () => {
            void (async () => {
              await persistConnected(false);
              await clearPrefs();
            })();
          },
        },
      ],
    );
  };

  const lastAgo = fmtAgo(lastSyncIso) || 'just now';

  return (
    <View style={styles.root}>
      {/* Header */}
      <View style={[styles.header, { paddingTop: 54 + insets.top }]}>
        <Pressable
          onPress={() => router.back()}
          style={({ pressed }) => [styles.backBtn, pressed && styles.backBtnPressed]}
          hitSlop={8}
          accessibilityLabel="Back"
          accessibilityRole="button"
        >
          <BackChevronIcon color={color.text2} strokeWidth={2.2} />
        </Pressable>
        <Text style={styles.title} numberOfLines={1}>Apple Health</Text>
      </View>

      <ScrollView
        style={styles.flex}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={[
          styles.scrollContent,
          { paddingTop: 116 + insets.top },
        ]}
      >
        {loaded && !connected && <Disconnected onConnect={onConnect} />}

        {loaded && connected && (
          <Connected
            askedLabel={fmtAsked(lastSyncIso)}
            lastAgo={lastAgo}
            workoutsWritten={workoutsWritten}
            prefs={prefs}
            receipts={receipts}
            writeStatus={writeStatus}
            onTogglePref={setPref}
            onDisconnect={onDisconnect}
          />
        )}
      </ScrollView>
    </View>
  );
}

// --- Inline glyph ---------------------------------------------------------

/** Up-and-out arrow (external link). Path lifted from board 5a. */
function ExternalLinkIcon({ size = 12, color: stroke }: { size?: number; color: string }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" fill="none">
      <Path
        d="M7 17L17 7M9 7h8v8"
        stroke={stroke}
        strokeWidth={2.4}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </Svg>
  );
}

// --- Disconnected state (H4 · before connecting) --------------------------

function Disconnected({ onConnect }: { onConnect: () => void }) {
  return (
    <View style={styles.discRoot}>
      <View style={styles.discHero}>
        <HeartFilledIcon size={34} color={color.error} />
      </View>
      <Text style={styles.discTitle}>Apple Health</Text>
      <Text style={styles.discCopy}>
        Save finished workouts as Traditional Strength Training, and read heart
        rate and calories live from your Apple Watch.
      </Text>

      {/* Sets the expectation before iOS takes over the permission sheet. */}
      <View style={styles.nextCard}>
        <Text style={styles.nextLabel}>WHAT HAPPENS NEXT</Text>
        <Text style={styles.nextBody}>
          iOS asks you, not us. Ischys is told whether it may{' '}
          <Text style={styles.nextEmph}>write</Text>, but never whether it may{' '}
          <Text style={styles.nextEmph}>read</Text> — so afterwards this screen
          shows what data actually arrives instead of a permission list.
        </Text>
      </View>

      <Pressable
        onPress={onConnect}
        style={({ pressed }) => [styles.connectBtn, pressed && styles.connectBtnPressed]}
        accessibilityRole="button"
        accessibilityLabel="Connect Apple Health"
      >
        <HeartFilledIcon size={17} color={color.accentFg} />
        <Text style={styles.connectBtnText}>Connect Apple Health</Text>
      </Pressable>

      <View style={styles.privacyRow}>
        <ShieldIcon size={15} color={color.text3} />
        <Text style={styles.privacyNote}>Health data never leaves your device.</Text>
      </View>
    </View>
  );
}

// --- Connected state (H1 / H2 / H3, all data-driven) ----------------------

function Connected({
  askedLabel,
  lastAgo,
  workoutsWritten,
  prefs,
  receipts,
  writeStatus,
  onTogglePref,
  onDisconnect,
}: {
  askedLabel: string;
  lastAgo: string;
  workoutsWritten: number;
  prefs: Record<PrefKey, boolean>;
  receipts: Record<ReadPref, Receipt | null>;
  writeStatus: WriteStatus;
  onTogglePref: (k: PrefKey, next: boolean) => void;
  onDisconnect: () => void;
}) {
  // Only 'nothing received' rows can expand their explainer.
  const [expanded, setExpanded] = useState<Record<ReadPref, boolean>>({
    readHR: false,
    readEnergy: false,
  });
  const denied = writeStatus === 'denied';

  return (
    <View style={styles.connRoot}>
      {/* Neutral status card — no green tint, no dot, no halo. */}
      <View style={styles.statusCard}>
        <View style={styles.statusTile}>
          <HeartFilledIcon size={17} color={color.error} />
        </View>
        <View style={styles.statusTextCol}>
          <Text style={styles.statusTitle}>Linked to Apple Health</Text>
          <Text style={styles.statusSub}>This iPhone · asked {askedLabel}</Text>
        </View>
      </View>

      {/* ISCHYS WRITES — share auth IS exposed, so state it plainly. */}
      <Text style={styles.sectionLabel}>ISCHYS WRITES</Text>
      <View style={[styles.card, denied && styles.cardDenied]}>
        <View style={styles.writeRow}>
          <View style={styles.rowTextCol}>
            <Text style={styles.rowLabel}>Save finished workouts</Text>
            <View style={styles.statusLine}>
              <View style={[styles.statusDot, { backgroundColor: denied ? color.error : color.success }]} />
              <Text style={[styles.statusText, { color: denied ? color.error : color.success }]}>
                {denied ? 'Denied in Health' : 'Allowed in Health'}
              </Text>
            </View>
          </View>
          {/* Denied → toggle is disabled. Leaving it flippable would imply
              Ischys can grant itself access. */}
          <Toggle value={!denied && prefs.writeWorkouts} disabled={denied} onPress={() => onTogglePref('writeWorkouts', !prefs.writeWorkouts)} />
        </View>
        {denied && (
          <View style={styles.explainerBlockLast}>
            <View style={styles.explainerBox}>
              <Text style={styles.explainerText}>
                Health is blocking writes, so finished workouts aren't being
                saved there. Only you can change this — Ischys can't ask again.
              </Text>
              <Pressable
                onPress={openHealthApp}
                style={({ pressed }) => [styles.explainerCta, pressed && styles.pressedDim]}
                accessibilityRole="link"
              >
                <Text style={styles.explainerCtaText}>Open Health → Sharing → Ischys</Text>
                <ExternalLinkIcon size={12} color={color.accent} />
              </Pressable>
            </View>
          </View>
        )}
      </View>
      {denied && (
        <Text style={styles.reassure}>Your workouts are still saved in Ischys. Nothing is lost.</Text>
      )}

      {/* ISCHYS ASKS HEALTH FOR — reads, with the plain-words caveat. */}
      <View style={styles.readsHead}>
        <Text style={styles.sectionLabelBare}>ISCHYS ASKS HEALTH FOR</Text>
        <Text style={styles.readsNote}>
          iOS never tells apps whether a read was allowed. These choose what
          Ischys asks for — Health decides what it returns.
        </Text>
      </View>
      <Animated.View style={styles.card} layout={LinearTransition.springify().mass(0.55)}>
        {READ_ROWS.map((r, i) => (
          <ReadRow
            key={r.pref}
            label={r.label}
            offDesc={r.offDesc}
            explainer={r.explainer}
            enabled={prefs[r.pref]}
            receipt={receipts[r.pref]}
            expanded={expanded[r.pref]}
            onToggleExpand={() => setExpanded((e) => ({ ...e, [r.pref]: !e[r.pref] }))}
            onTogglePref={(next) => onTogglePref(r.pref, next)}
            isLast={i === READ_ROWS.length - 1}
          />
        ))}
      </Animated.View>

      {/* Privacy reassurance (H2). */}
      <View style={styles.shieldRow}>
        <ShieldIcon size={15} color={color.text3} />
        <Text style={styles.shieldNote}>
          Health data stays on this device. Ischys reads only what it writes back.
        </Text>
      </View>

      {/* Stats block. */}
      <View style={styles.statsCard}>
        <View style={styles.statCell}>
          <Text style={styles.statCellLabel}>WORKOUTS WRITTEN</Text>
          <Text style={styles.statCellValue}>{String(workoutsWritten)}</Text>
        </View>
        <View style={styles.statCellDivider} />
        <View style={styles.statCell}>
          <Text style={styles.statCellLabel}>LAST SYNCED</Text>
          {/* A stale timestamp is itself the evidence that writing stopped. */}
          <Text style={[styles.statCellValue, denied && { color: color.warning }]}>{lastAgo}</Text>
        </View>
      </View>

      {/* Disconnect */}
      <Pressable
        onPress={onDisconnect}
        style={({ pressed }) => [styles.disconnectBtn, pressed && styles.disconnectBtnPressed]}
        accessibilityRole="button"
        accessibilityLabel="Disconnect Apple Health"
      >
        <Text style={styles.disconnectBtnText}>Disconnect Apple Health</Text>
      </Pressable>
    </View>
  );
}

// --- Read row (intent switch + receipt) -----------------------------------

function ReadRow({
  label,
  offDesc,
  explainer,
  enabled,
  receipt,
  expanded,
  onToggleExpand,
  onTogglePref,
  isLast,
}: {
  label: string;
  offDesc: string;
  explainer: string;
  enabled: boolean;
  receipt: Receipt | null;
  expanded: boolean;
  onToggleExpand: () => void;
  onTogglePref: (next: boolean) => void;
  isLast: boolean;
}) {
  const kind = receiptKind(receipt, enabled);
  const uncertain = kind === 'nothing';

  // The switch always flips intent. Tapping the row body opens the explainer
  // when uncertain (the switch is already on, so the actionable thing is to
  // learn why), and otherwise flips intent too — a large, forgiving target.
  const onBodyPress = uncertain ? onToggleExpand : () => onTogglePref(!enabled);

  let receiptNode: React.ReactNode;
  if (kind === 'off') {
    receiptNode = <Text style={styles.rowDesc}>{offDesc}</Text>;
  } else if (kind === 'receiving') {
    receiptNode = (
      <View style={styles.statusLine}>
        <View style={[styles.statusDot, { backgroundColor: color.success }]} />
        <Text style={[styles.statusText, { color: color.success }]}>
          Receiving · {receipt?.value} last session
        </Text>
      </View>
    );
  } else {
    receiptNode = (
      <View style={styles.statusLine}>
        <View style={[styles.statusDot, { backgroundColor: color.warning }]} />
        <Text style={[styles.statusText, { color: color.warning }]}>Nothing received yet</Text>
      </View>
    );
  }

  return (
    <View>
      <View style={[styles.readRow, !isLast && styles.rowDivider]}>
        <Pressable
          style={styles.rowTextCol}
          onPress={onBodyPress}
          accessibilityRole={uncertain ? 'button' : 'switch'}
          accessibilityLabel={label}
          accessibilityState={uncertain ? { expanded } : { checked: enabled }}
        >
          <Text style={[styles.rowLabel, kind === 'off' && styles.rowLabelOff]}>{label}</Text>
          <View style={styles.receiptWrap}>{receiptNode}</View>
        </Pressable>
        <Toggle value={enabled} onPress={() => onTogglePref(!enabled)} />
      </View>

      {uncertain && expanded && (
        <Animated.View
          entering={FadeIn.duration(160)}
          exiting={FadeOut.duration(120)}
          style={[styles.explainerBlock, !isLast && styles.rowDivider]}
        >
          <View style={styles.explainerBox}>
            <Text style={styles.explainerTextSecondary}>{explainer}</Text>
            <Pressable
              onPress={openHealthApp}
              style={({ pressed }) => [styles.explainerCta, pressed && styles.pressedDim]}
              accessibilityRole="link"
            >
              <Text style={styles.explainerCtaText}>Check in the Health app</Text>
              <ExternalLinkIcon size={12} color={color.accent} />
            </Pressable>
          </View>
        </Animated.View>
      )}
    </View>
  );
}

// --- Toggle ---------------------------------------------------------------

function Toggle({
  value,
  disabled,
  onPress,
}: {
  value: boolean;
  disabled?: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      onPress={disabled ? undefined : onPress}
      disabled={disabled}
      hitSlop={8}
      accessibilityRole="switch"
      accessibilityState={{ checked: value, disabled: !!disabled }}
      style={[
        styles.toggleTrack,
        { backgroundColor: value ? color.accent : color.surface3 },
        disabled && styles.toggleTrackDisabled,
      ]}
    >
      <View style={[styles.toggleKnob, { left: value ? 21 : 3 }]} />
    </Pressable>
  );
}

// --- Styles ---------------------------------------------------------------

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: color.bg },
  flex: { flex: 1 },
  scrollContent: {
    paddingHorizontal: 16,
    paddingBottom: 40,
  },

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

  // --- Disconnected (H4) ---
  discRoot: {
    alignItems: 'center',
    paddingHorizontal: 26,
    paddingTop: 46,
    paddingBottom: 30,
  },
  discHero: {
    width: 74,
    height: 74,
    borderRadius: 20,
    backgroundColor: color.surface1,
    borderWidth: 1,
    borderColor: color.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  discTitle: {
    fontFamily: font.displayBold,
    fontSize: 24,
    fontWeight: '700',
    letterSpacing: -0.48,
    color: color.text1,
    textAlign: 'center',
    marginTop: 22,
  },
  discCopy: {
    fontFamily: font.bodyRegular,
    fontSize: 14.5,
    lineHeight: 22,
    color: color.text2,
    textAlign: 'center',
    marginTop: 10,
    maxWidth: 320,
  },
  nextCard: {
    width: '100%',
    backgroundColor: color.surface1,
    borderWidth: 1,
    borderColor: color.border,
    borderRadius: 14,
    padding: 14,
    marginTop: 22,
  },
  nextLabel: {
    fontFamily: font.monoRegular,
    fontSize: 10,
    letterSpacing: 1.4,
    color: color.text3,
  },
  nextBody: {
    fontFamily: font.bodyRegular,
    fontSize: 12.5,
    lineHeight: 19.5,
    color: color.text2,
    marginTop: 8,
  },
  nextEmph: { color: color.text1 },
  connectBtn: {
    width: '100%',
    height: 52,
    borderRadius: 14,
    backgroundColor: color.accent,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    marginTop: 20,
  },
  connectBtnPressed: { opacity: 0.9 },
  connectBtnText: {
    fontFamily: font.displayBold,
    fontSize: 15,
    fontWeight: '700',
    letterSpacing: -0.15,
    color: color.accentFg,
  },
  privacyRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 8,
    marginTop: 18,
    alignSelf: 'stretch',
  },
  privacyNote: {
    flex: 1,
    fontFamily: font.monoRegular,
    fontSize: 11,
    lineHeight: 17.6,
    color: color.text3,
  },

  // --- Connected ---
  connRoot: {
    paddingTop: 0,
    paddingBottom: 32,
  },

  // Neutral status card
  statusCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    backgroundColor: color.surface1,
    borderWidth: 1,
    borderColor: color.border,
    borderRadius: 14,
    paddingVertical: 13,
    paddingHorizontal: 14,
  },
  statusTile: {
    width: 34,
    height: 34,
    borderRadius: 10,
    backgroundColor: color.surface3,
    borderWidth: 1,
    borderColor: color.border,
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  statusTextCol: { flex: 1, minWidth: 0 },
  statusTitle: {
    fontFamily: font.titleSemi,
    fontSize: 13.5,
    fontWeight: '600',
    color: color.text1,
  },
  statusSub: {
    fontFamily: font.monoRegular,
    fontSize: 11.5,
    color: color.text3,
    marginTop: 2,
  },

  // Section labels
  sectionLabel: {
    fontFamily: font.monoRegular,
    fontSize: 11,
    letterSpacing: 1.54,
    color: color.text3,
    marginTop: 22,
    marginBottom: 10,
    paddingHorizontal: 2,
  },
  sectionLabelBare: {
    fontFamily: font.monoRegular,
    fontSize: 11,
    letterSpacing: 1.54,
    color: color.text3,
  },
  readsHead: {
    marginTop: 22,
    marginBottom: 10,
    paddingHorizontal: 2,
  },
  readsNote: {
    fontFamily: font.bodyRegular,
    fontSize: 12,
    lineHeight: 18,
    color: color.text3,
    marginTop: 6,
  },

  // Section card
  card: {
    backgroundColor: color.surface1,
    borderWidth: 1,
    borderColor: color.border,
    borderRadius: 14,
    overflow: 'hidden',
  },
  cardDenied: { borderColor: 'rgba(255,77,77,0.3)' },

  // Rows
  writeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 13,
    paddingVertical: 14,
    paddingHorizontal: 16,
  },
  readRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 13,
    paddingVertical: 14,
    paddingHorizontal: 16,
  },
  rowDivider: {
    borderBottomWidth: 1,
    borderBottomColor: color.hair,
  },
  rowTextCol: { flex: 1, minWidth: 0 },
  rowLabel: {
    fontFamily: font.bodyMedium,
    fontSize: 14.5,
    fontWeight: '500',
    color: color.text1,
  },
  rowLabelOff: { color: color.text2 },
  rowDesc: {
    fontFamily: font.monoRegular,
    fontSize: 11,
    color: color.text3,
    marginTop: 3,
  },
  receiptWrap: { marginTop: 3 },

  // Receipt / status line
  statusLine: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  statusDot: {
    width: 5,
    height: 5,
    borderRadius: 999,
  },
  statusText: {
    fontFamily: font.monoRegular,
    fontSize: 11,
  },

  // In-place explainer
  explainerBlock: {
    paddingHorizontal: 16,
    paddingBottom: 14,
  },
  explainerBlockLast: {
    paddingHorizontal: 16,
    paddingBottom: 14,
  },
  explainerBox: {
    backgroundColor: color.surface2,
    borderWidth: 1,
    borderColor: color.border,
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 13,
  },
  explainerText: {
    fontFamily: font.bodyRegular,
    fontSize: 12.5,
    lineHeight: 19.4,
    color: color.text2,
  },
  explainerTextSecondary: {
    fontFamily: font.bodyRegular,
    fontSize: 12.5,
    lineHeight: 19.4,
    color: color.text2,
  },
  explainerCta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginTop: 11,
  },
  explainerCtaText: {
    fontFamily: font.titleSemi,
    fontSize: 12.5,
    fontWeight: '600',
    color: color.accent,
  },
  pressedDim: { opacity: 0.6 },

  reassure: {
    fontFamily: font.monoRegular,
    fontSize: 11,
    lineHeight: 17.6,
    color: color.text3,
    paddingTop: 12,
    paddingHorizontal: 2,
  },

  // Toggle
  toggleTrack: {
    width: 44,
    height: 26,
    borderRadius: 999,
    position: 'relative',
    flexShrink: 0,
  },
  toggleTrackDisabled: { opacity: 0.5 },
  toggleKnob: {
    position: 'absolute',
    top: 3,
    width: 20,
    height: 20,
    borderRadius: 999,
    backgroundColor: '#FFFFFF',
  },

  // Privacy shield
  shieldRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 9,
    marginTop: 18,
    paddingHorizontal: 2,
  },
  shieldNote: {
    flex: 1,
    fontFamily: font.monoRegular,
    fontSize: 11,
    lineHeight: 17.6,
    color: color.text3,
  },

  // Stats block
  statsCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    backgroundColor: color.surface1,
    borderWidth: 1,
    borderColor: color.border,
    borderRadius: 14,
    padding: 14,
    marginTop: 18,
  },
  statCell: { flex: 1, minWidth: 0, gap: 3 },
  statCellDivider: {
    width: 1,
    height: 30,
    backgroundColor: color.hair,
  },
  statCellLabel: {
    fontFamily: font.monoRegular,
    fontSize: 9.5,
    letterSpacing: 0.95,
    color: color.text3,
    textTransform: 'uppercase',
  },
  statCellValue: {
    fontFamily: font.monoSemi,
    fontSize: 15,
    fontWeight: '600',
    color: color.text1,
    fontVariant: ['tabular-nums'],
  },

  // Disconnect
  disconnectBtn: {
    alignSelf: 'center',
    marginTop: 6,
    paddingVertical: 12,
    paddingHorizontal: 16,
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
  disconnectBtnPressed: { opacity: 0.7 },
  disconnectBtnText: {
    fontFamily: font.bodyMedium,
    fontSize: 14,
    fontWeight: '500',
    color: color.error,
  },
});
