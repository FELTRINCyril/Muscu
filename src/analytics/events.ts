export type AnalyticsEventProperties = Record<
    string,
    string | number | boolean | null | undefined | readonly string[] | readonly number[]
>;

type ReviewPromptProperties = {
    promptId: string;
    promptKey: string;
    cycleIndex: number;
    workoutId?: string;
    completionSource?: 'phone' | 'watch';
    response?: 'bad' | 'not_bad' | 'good';
    eligibleWorkoutCount: number;
};

type CampaignProperties = {
    campaignSource?: string;
    campaignMedium?: string;
    campaignName?: string;
};

type WorkoutStatus = 'planned' | 'in_progress' | 'completed' | 'cancelled';

type WorkoutEditorProperties = {
    mode: 'create' | 'edit';
    status: WorkoutStatus;
};

type WorkoutCompositionProperties = {
    totalExerciseCount: number | null;
    totalSetCount: number | null;
    averageSetsPerExercise: number | null;
};

type WorkoutProgressProperties = WorkoutCompositionProperties & {
    completedSetCount: number | null;
    setCompletionPercentage: number | null;
};

type ExerciseLibraryProperties = {
    exerciseLibraryTotalCount: number | null;
    exerciseLibrarySkulptCount: number | null;
    exerciseLibraryUserCreatedCount: number | null;
};

type WorkoutDiagnosticProperties = WorkoutProgressProperties & ExerciseLibraryProperties;

// Keep user-entered and sensitive data out of this catalog. Do not add workout/exercise
// names, notes, search text, measurement values, health samples, or raw deep-link URLs.
export type AnalyticsEventMap = {
    'app:session_start': CampaignProperties &
        ExerciseLibraryProperties & {
            source: 'cold_start' | 'foreground' | 'deep_link' | 'notification';
            isFirstSession: boolean;
        };
    'app:deep_link_opened': CampaignProperties;
    'app:share_requested': {
        surface: 'settings';
    };
    'app_review:manual_request': {
        surface: 'settings';
        storeReviewAvailable: boolean;
        storeReviewHasAction: boolean;
    };
    'workout:create_requested': {
        surface: 'home_empty_state' | 'home_header';
    };
    'workout:editor_opened': WorkoutEditorProperties;
    'workout:editor_submitted': WorkoutEditorProperties & {
        hasStartDate: boolean;
        hasReminder: boolean;
    };
    'workout:create': WorkoutDiagnosticProperties & {
        workoutId: string;
        status: WorkoutStatus;
        hasStartDate: boolean;
        hasReminder: boolean;
    };
    'workout:update': {
        workoutId: string;
        status: WorkoutStatus;
        scheduleChanged: boolean;
        reminderChanged: boolean;
        timingChanged: boolean;
    };
    'workout:duplicate': WorkoutDiagnosticProperties & {
        sourceWorkoutId: string;
        workoutId: string;
        mode: 'now' | 'planned' | 'completed';
    };
    'workout:start': WorkoutDiagnosticProperties & {
        workoutId: string;
        source: 'new' | 'planned' | 'repeat';
        $insert_id?: string;
    };
    'workout:complete': WorkoutDiagnosticProperties & {
        workoutId: string;
        duration: number | null;
        wallDurationSec: number;
        activeDurationSec: number;
        exerciseCount: number;
        completionSource: 'phone' | 'watch';
        watchUsed: boolean;
        liveActivityUsed: boolean;
        $insert_id: string;
    };
    'workout:delete': WorkoutDiagnosticProperties & {
        workoutId: string;
        status: WorkoutStatus;
    };
    'workout:reminder_configured': {
        workoutId: string;
        leadTime: 'start' | '5m' | '10m' | '15m' | '30m' | '1h' | '2h';
        source: 'create' | 'update';
    };
    'workout:operation_failed': {
        operation:
            'create' | 'update' | 'start' | 'complete' | 'delete' | 'duplicate' | 'exercise_add';
        workoutId?: string;
        errorType: string;
    };
    'workout:exercise_add_requested': ExerciseLibraryProperties & {
        workoutId: string;
        surface: 'empty_state' | 'actions';
        status: WorkoutStatus;
    };
    'workout:exercise_selected': {
        workoutId: string;
        exerciseId: string;
        discoveryMethod: 'browse' | 'search';
        ownership: 'system' | 'custom';
        category: string;
        selectedCount: number;
        activeFilterCount: number;
    };
    'workout:exercise_add': WorkoutDiagnosticProperties & {
        workoutId: string;
        exerciseCount: number;
        addedExerciseCount: number;
    };
    'workout:exercise_remove': WorkoutDiagnosticProperties & {
        workoutId: string;
    };
    'workout:exercise_set_add': WorkoutDiagnosticProperties & {
        workoutId: string;
        workoutExerciseId: string;
        setType: string;
        source: 'manual' | 'exercise_seed' | 'copied';
    };
    'workout:exercise_set_remove': WorkoutDiagnosticProperties & {
        workoutId: string;
        workoutExerciseId: string;
    };
    'workout:exercise_set_complete': WorkoutDiagnosticProperties & {
        workoutId: string;
        workoutExerciseId: string;
        setType: string;
        source: 'phone' | 'watch' | 'auto_timer';
        $insert_id: string;
    };
    'exercise:create': ExerciseLibraryProperties & {
        category: string;
    };
    'exercise:delete': ExerciseLibraryProperties;
    'exercise_search:completed': ExerciseLibraryProperties & {
        context: 'library' | 'workout_select';
        workoutId?: string;
        queryLength: number;
        scriptGroup: 'han' | 'latin' | 'cyrillic' | 'devanagari' | 'mixed' | 'other';
        resultCount: number;
        hasResults: boolean;
        activeFilterCount: number;
    };
    'exercise_search:result_selected': {
        context: 'library' | 'workout_select';
        workoutId?: string;
        rankBucket: '1' | '2_3' | '4_10' | '11_plus';
        ownership: 'system' | 'custom';
        category: string;
    };
    'exercise:guide_viewed': {
        surface: 'active_workout' | 'exercise_detail';
        ownership: 'system' | 'custom';
        category: string;
    };
    'exercise:statistics_viewed': {
        ownership: 'system' | 'custom';
        category: string;
        hasHistory: boolean;
    };
    'exercise:preview_opened': {
        surface: 'exercise_library' | 'workout_select' | 'active_workout';
        workoutId?: string;
    };
    'watch:workout_started': {
        supported: boolean;
        paired: boolean;
    };
    'watch:availability_checked': {
        supported: boolean;
        paired: boolean;
    };
    'live_activity:started': {
        result: 'started' | 'recovered' | 'unavailable';
    };
    'health:permission_result': {
        platform: 'ios' | 'android';
        trigger: 'workout_start';
        granted: boolean;
        hasResolvedMhr: boolean;
    };
    'health:workout_export_result': {
        platform: 'ios' | 'android';
        outcome: 'saved' | 'skipped_watch' | 'permission_missing' | 'service_unavailable' | 'error';
    };
    'health:measurement_import_summary': {
        platform: 'ios' | 'android';
        permissionGranted: boolean;
        importedCount: number;
        skippedCount: number;
        sampledCount: number;
        metricTypes: readonly string[];
    };
    'notification:permission_result': {
        trigger: 'initial_check' | 'request' | 'settings_change';
        status: string;
        granted: boolean;
    };
    'notification:opened': {
        kind: 'workout_reminder' | 'rest_timer' | 'work_timer' | 'other';
    };
    'measurement:created': {
        metric: string;
        source: 'manual' | 'health';
        count: number;
    };
    'progress:period_changed': {
        surface: 'workout_calendar' | 'activity_summary';
        direction: 'previous' | 'next';
    };
    'progress:day_opened': {
        daysAgo: number;
    };
    'sync:first_success': ExerciseLibraryProperties & {
        trigger: 'initial' | 'scheduled' | 'deferred' | 'manual';
        durationMs: number;
        pendingBefore: number;
        pendingAfter: number;
    };
    'sync:state_changed': ExerciseLibraryProperties & {
        outcome: 'success' | 'failure';
        trigger: 'initial' | 'scheduled' | 'deferred' | 'manual';
        durationMs: number;
        pendingBefore: number;
        pendingAfter: number;
        failureKind?: 'returned_false' | 'exception';
        retryCount: number;
    };
    'app_review_prompt:eligible': ReviewPromptProperties;
    'app_review_prompt:deferred': ReviewPromptProperties;
    'app_review_prompt:shown': ReviewPromptProperties;
    'app_review_prompt:submitted': ReviewPromptProperties;
    'app_review_prompt:dismissed': ReviewPromptProperties;
    'app_review_prompt:store_review_requested': ReviewPromptProperties & {
        storeReviewAvailable: boolean;
        storeReviewHasAction: boolean;
    };
};

export type AnalyticsEventName = keyof AnalyticsEventMap;

export type AnalyticsScreenName =
    | 'home'
    | 'progress'
    | 'exercise_library'
    | 'settings'
    | 'workout_editor'
    | 'exercise_editor'
    | 'exercise_select'
    | 'exercise_preview'
    | 'exercise_guide'
    | 'app_review'
    | 'results_day'
    | 'exercise_filter'
    | 'workout'
    | 'active_exercise'
    | 'exercise_detail'
    | 'measurement_editor'
    | 'settings_autolock'
    | 'settings_datetime'
    | 'settings_heart_rate'
    | 'settings_language'
    | 'settings_notifications'
    | 'settings_sound'
    | 'settings_theme'
    | 'settings_units'
    | 'not_found';
