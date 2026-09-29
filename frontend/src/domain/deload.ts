/**
 * The stall / deload advisory (#70).
 *
 * Two triggers — a lift that has stopped moving, and a muscle group whose
 * weekly volume jumped — and a long list of reasons to stay quiet. The design
 * budgets roughly one card every 6–10 weeks, so the restraint lives here rather
 * than in the user's willingness to dismiss things: a banner people learn to
 * swipe away has already failed.
 *
 * Advice only. Nothing here writes a weight; `progression.ts` reflects an
 * accepted deload once it is running.
 */

export type DeloadReason = 'stall' | 'volume-ramp';

export type DeloadAdvice = {
  reason: DeloadReason;
  exerciseId: string;
  /** Multiplier on working weight — 0.9 to back off, 1 to hold. */
  factor: number;
  /** How many days it runs for. It ends by date, not by session count. */
  days: number;
};

/** One session of one lift: when, and the best Epley 1RM in it. */
export type ExerciseSession = { at: number; best1rm: number };

export type ExerciseHistory = {
  exerciseId: string;
  /** Every session of this lift, oldest first. */
  sessions: ExerciseSession[];
  /** Working sets per week for this lift's muscle group, oldest first. */
  weeklyVolumes: number[];
  /** When "Not now" was last tapped for this lift; null = never. */
  dismissedAt: number | null;
};

export type AdvisoryInput = {
  /** Settings → TRAINING → Deload advice. */
  enabled: boolean;
  now: number;
  /** The user's very first session; null = no history yet. */
  historyStartedAt: number | null;
  /** When any advisory card was last shown, for any lift; null = never. */
  lastShownAt: number | null;
  /** A PR was set in the session that just ended. */
  prThisSession: boolean;
  exercises: ExerciseHistory[];
};

const DAY = 86400000;

/** Consecutive sessions that must fail to beat the standing best. */
const STALL_SESSIONS = 3;

/**
 * Three sessions can happen in four days on a push/pull/legs split, and three
 * flat sessions in four days is a bad week, not a stall.
 */
const STALL_MIN_DAYS = 14;

/** Weekly volume at or above this multiple of the baseline is a ramp. */
const RAMP_MULTIPLE = 1.4;
const RAMP_BASELINE_WEEKS = 4;
const RAMP_WEEKS = 2;

/** Fraction of working weight a deload runs at, and for how long. */
export const DELOAD_FACTOR = 0.9;
export const DELOAD_DAYS = 7;

/** A ramp asks for a pause, not a back-off: same weight, no more volume. */
const HOLD_FACTOR = 1;

/**
 * Sessions of the lift before a stall may be reported. The three-session rule
 * can technically fire on the fourth-ever session, when "the standing best" is
 * really just the novice's first week.
 */
const MIN_STALL_SESSIONS = 6;

/** One card per fortnight, across every lift and both triggers. */
const CARD_GAP_DAYS = 14;

/** "Not now" is a real answer, and this is what makes it one. */
const DISMISS_SILENCE_DAYS = 42;

/** Early training moves too fast for a flat run to mean anything. */
const MIN_HISTORY_DAYS = 28;

/**
 * How long the lift has been flat, or null if it has not stalled.
 *
 * Measured to `now` rather than to the last session, because the card appears
 * on the Summary of the session that confirms the stall — the two are the same
 * moment, and the span is what the card prints ("· 19 days").
 */
export function stallSpanDays(sessions: ExerciseSession[], now: number): number | null {
  // A stall is failing to beat a best, so a best has to exist before the run.
  if (sessions.length <= STALL_SESSIONS) return null;

  const flat = sessions.slice(-STALL_SESSIONS);
  const previousBest = Math.max(...sessions.slice(0, -STALL_SESSIONS).map((s) => s.best1rm));
  // Matching the old best is not beating it: the lift has not moved.
  if (flat.some((s) => s.best1rm > previousBest)) return null;

  const days = (now - flat[0].at) / DAY;
  return days >= STALL_MIN_DAYS ? days : null;
}

export function detectStall(sessions: ExerciseSession[], now: number): boolean {
  return stallSpanDays(sessions, now) !== null;
}

/**
 * Two weeks running at 40% or more above the four-week average before them.
 *
 * The baseline is fixed at the four weeks preceding both ramp weeks, not
 * recomputed per week — a rolling average absorbs the first spike into its own
 * baseline, so a genuine two-week climb would hide inside it.
 */
export function detectVolumeRamp(weeklyVolumes: number[]): boolean {
  const weeks = RAMP_BASELINE_WEEKS + RAMP_WEEKS;
  if (weeklyVolumes.length < weeks) return false;

  const window = weeklyVolumes.slice(-weeks);
  const baseline =
    window.slice(0, RAMP_BASELINE_WEEKS).reduce((sum, v) => sum + v, 0) / RAMP_BASELINE_WEEKS;
  // Nothing to ramp from. Starting a muscle group from zero is new training,
  // not a ramp, and any ratio against zero is infinite.
  if (baseline <= 0) return false;

  // Compared as a ratio, so a value exactly on the threshold isn't lost to the
  // float error in `baseline * 1.4`.
  return window.slice(RAMP_BASELINE_WEEKS).every((v) => v / baseline >= RAMP_MULTIPLE);
}

export function shouldShowAdvisory({
  enabled,
  now,
  historyStartedAt,
  lastShownAt,
  prThisSession,
  exercises,
}: AdvisoryInput): DeloadAdvice | null {
  if (!enabled) return null;
  // A PR proves the lift isn't stalled, and the Summary belongs to the PR.
  if (prThisSession) return null;
  if (historyStartedAt === null || (now - historyStartedAt) / DAY < MIN_HISTORY_DAYS) return null;
  if (lastShownAt !== null && (now - lastShownAt) / DAY < CARD_GAP_DAYS) return null;

  // Ranked so the card can name one lift: the longest-standing evidence wins,
  // and every stall outranks a ramp (a stall is about this lift; a ramp is
  // about a whole muscle group, and holding is the milder ask).
  let best: { advice: DeloadAdvice; rank: number } | null = null;
  for (const ex of exercises) {
    if (ex.dismissedAt !== null && (now - ex.dismissedAt) / DAY < DISMISS_SILENCE_DAYS) continue;

    const span = ex.sessions.length >= MIN_STALL_SESSIONS ? stallSpanDays(ex.sessions, now) : null;
    const candidate: { advice: DeloadAdvice; rank: number } | null =
      span !== null
        ? {
            advice: { reason: 'stall', exerciseId: ex.exerciseId, factor: DELOAD_FACTOR, days: DELOAD_DAYS },
            rank: span,
          }
        : detectVolumeRamp(ex.weeklyVolumes)
          ? {
              advice: { reason: 'volume-ramp', exerciseId: ex.exerciseId, factor: HOLD_FACTOR, days: DELOAD_DAYS },
              rank: -1,
            }
          : null;

    if (candidate && (best === null || candidate.rank > best.rank)) best = candidate;
  }

  return best?.advice ?? null;
}
