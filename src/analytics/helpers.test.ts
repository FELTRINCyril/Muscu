import { describe, expect, test } from '@jest/globals';

import {
    getAnalyticsErrorType,
    getCampaignProperties,
    getExerciseLibraryProperties,
    getSearchRankBucket,
    getSearchScriptGroup,
    getWorkoutCompositionProperties,
    getWorkoutProgressProperties,
    isFirstAnalyticsSession,
} from './helpers';

describe('analytics helpers', () => {
    test('keeps only supported campaign fields and normalizes their values', () => {
        expect(
            getCampaignProperties({
                utm_source: '  reddit  ',
                utm_medium: ['social', 'ignored'],
                utm_campaign: 'x'.repeat(120),
                query: 'private search text',
                token: 'secret',
            }),
        ).toEqual({
            campaignSource: 'reddit',
            campaignMedium: 'social',
            campaignName: 'x'.repeat(100),
        });
    });

    test('does not classify an existing user as new when analytics is first introduced', () => {
        const nowMs = Date.parse('2026-07-16T12:00:00.000Z');

        expect(
            isFirstAnalyticsSession({
                hasStartedSession: false,
                userCreatedAtMs: nowMs - 60_000,
                nowMs,
            }),
        ).toBe(true);
        expect(
            isFirstAnalyticsSession({
                hasStartedSession: false,
                userCreatedAtMs: nowMs - 24 * 60 * 60 * 1000,
                nowMs,
            }),
        ).toBe(false);
        expect(
            isFirstAnalyticsSession({
                hasStartedSession: true,
                userCreatedAtMs: nowMs - 60_000,
                nowMs,
            }),
        ).toBe(false);
    });

    const scriptCases: [string, ReturnType<typeof getSearchScriptGroup>][] = [
        ['bench press', 'latin'],
        ['жим лежа', 'cyrillic'],
        ['卧推', 'han'],
        ['बेंच प्रेस', 'devanagari'],
        ['жим press', 'mixed'],
        ['123', 'other'],
    ];

    test.each(scriptCases)('classifies search script for %s', (query, expected) => {
        expect(getSearchScriptGroup(query)).toBe(expected);
    });

    const rankCases: [number, ReturnType<typeof getSearchRankBucket>][] = [
        [1, '1'],
        [2, '2_3'],
        [3, '2_3'],
        [4, '4_10'],
        [10, '4_10'],
        [11, '11_plus'],
    ];

    test.each(rankCases)('buckets result rank %s', (rank, expected) => {
        expect(getSearchRankBucket(rank)).toBe(expected);
    });

    test('builds a workout composition snapshot for analytics', () => {
        expect(getWorkoutCompositionProperties(3, 10)).toEqual({
            totalExerciseCount: 3,
            totalSetCount: 10,
            averageSetsPerExercise: 3.33,
        });
        expect(getWorkoutCompositionProperties(0, 0)).toEqual({
            totalExerciseCount: 0,
            totalSetCount: 0,
            averageSetsPerExercise: 0,
        });
        expect(getWorkoutCompositionProperties(null, null)).toEqual({
            totalExerciseCount: null,
            totalSetCount: null,
            averageSetsPerExercise: null,
        });
    });

    test('builds workout progress without inventing unavailable values', () => {
        expect(getWorkoutProgressProperties(4, 12, 5)).toEqual({
            totalExerciseCount: 4,
            totalSetCount: 12,
            averageSetsPerExercise: 3,
            completedSetCount: 5,
            setCompletionPercentage: 41.67,
        });
        expect(getWorkoutProgressProperties(0, 0, 0)).toEqual({
            totalExerciseCount: 0,
            totalSetCount: 0,
            averageSetsPerExercise: 0,
            completedSetCount: 0,
            setCompletionPercentage: 0,
        });
        expect(getWorkoutProgressProperties(null, null, null)).toEqual({
            totalExerciseCount: null,
            totalSetCount: null,
            averageSetsPerExercise: null,
            completedSetCount: null,
            setCompletionPercentage: null,
        });
    });

    test('keeps exercise library counts explicit when the snapshot is unavailable', () => {
        expect(getExerciseLibraryProperties(250, 240, 10)).toEqual({
            exerciseLibraryTotalCount: 250,
            exerciseLibrarySkulptCount: 240,
            exerciseLibraryUserCreatedCount: 10,
        });
        expect(getExerciseLibraryProperties(null, null, null)).toEqual({
            exerciseLibraryTotalCount: null,
            exerciseLibrarySkulptCount: null,
            exerciseLibraryUserCreatedCount: null,
        });
    });

    test('keeps analytics errors useful without sending messages', () => {
        const error = new Error('private workout data must not be sent');
        error.name = 'DatabaseError';

        expect(getAnalyticsErrorType(error)).toBe('DatabaseError');
        expect(getAnalyticsErrorType('private workout data')).toBe('unknown');
    });
});
