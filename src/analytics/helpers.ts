export const ANALYTICS_FIRST_SESSION_WINDOW_MS = 10 * 60 * 1000;

const CAMPAIGN_KEYS = {
    utm_source: 'campaignSource',
    utm_medium: 'campaignMedium',
    utm_campaign: 'campaignName',
} as const;

const trimCampaignValue = (value: unknown): string | undefined => {
    const candidate = Array.isArray(value) ? value[0] : value;
    if (typeof candidate !== 'string') return undefined;
    const trimmed = candidate.trim();
    return trimmed ? trimmed.slice(0, 100) : undefined;
};

export const isFirstAnalyticsSession = ({
    hasStartedSession,
    userCreatedAtMs,
    nowMs = Date.now(),
}: {
    hasStartedSession: boolean;
    userCreatedAtMs: number;
    nowMs?: number;
}): boolean => {
    const userAgeMs = nowMs - userCreatedAtMs;
    return (
        !hasStartedSession &&
        Number.isFinite(userAgeMs) &&
        userAgeMs >= 0 &&
        userAgeMs <= ANALYTICS_FIRST_SESSION_WINDOW_MS
    );
};

export const getCampaignProperties = (queryParams?: Record<string, unknown>) => {
    if (!queryParams) return {};

    return Object.entries(CAMPAIGN_KEYS).reduce<Record<string, string>>(
        (properties, [queryKey, propertyKey]) => {
            const value = trimCampaignValue(queryParams[queryKey]);
            if (value) properties[propertyKey] = value;
            return properties;
        },
        {},
    );
};

export const getSearchScriptGroup = (
    query: string,
): 'han' | 'latin' | 'cyrillic' | 'devanagari' | 'mixed' | 'other' => {
    const scripts = new Set<string>();

    for (const character of query) {
        if (/\p{Script=Han}/u.test(character)) scripts.add('han');
        else if (/\p{Script=Latin}/u.test(character)) scripts.add('latin');
        else if (/\p{Script=Cyrillic}/u.test(character)) scripts.add('cyrillic');
        else if (/\p{Script=Devanagari}/u.test(character)) scripts.add('devanagari');
        else if (/\p{L}|\p{N}/u.test(character)) scripts.add('other');
    }

    if (scripts.size === 0) return 'other';
    if (scripts.size > 1) return 'mixed';
    return Array.from(scripts)[0] as 'han' | 'latin' | 'cyrillic' | 'devanagari' | 'other';
};

export const getSearchRankBucket = (rank: number): '1' | '2_3' | '4_10' | '11_plus' => {
    if (rank <= 1) return '1';
    if (rank <= 3) return '2_3';
    if (rank <= 10) return '4_10';
    return '11_plus';
};

export const getWorkoutCompositionProperties = (
    totalExerciseCount: number | null,
    totalSetCount: number | null,
) => ({
    totalExerciseCount,
    totalSetCount,
    averageSetsPerExercise:
        totalExerciseCount == null || totalSetCount == null
            ? null
            : totalExerciseCount === 0
              ? 0
              : Math.round((totalSetCount / totalExerciseCount) * 100) / 100,
});

export const getWorkoutProgressProperties = (
    totalExerciseCount: number | null,
    totalSetCount: number | null,
    completedSetCount: number | null,
) => ({
    ...getWorkoutCompositionProperties(totalExerciseCount, totalSetCount),
    completedSetCount,
    setCompletionPercentage:
        totalSetCount == null || completedSetCount == null
            ? null
            : totalSetCount === 0
              ? 0
              : Math.round((completedSetCount / totalSetCount) * 10_000) / 100,
});

export const getExerciseLibraryProperties = (
    exerciseLibraryTotalCount: number | null,
    exerciseLibrarySkulptCount: number | null,
    exerciseLibraryUserCreatedCount: number | null,
) => ({
    exerciseLibraryTotalCount,
    exerciseLibrarySkulptCount,
    exerciseLibraryUserCreatedCount,
});

/** Returns a bounded, non-sensitive error class for analytics properties. */
export const getAnalyticsErrorType = (error: unknown): string => {
    if (!(error instanceof Error)) return 'unknown';

    const name = error.name.trim();
    return name ? name.slice(0, 64) : 'Error';
};
