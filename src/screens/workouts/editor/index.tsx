import { FC, useEffect, useRef, useState } from 'react';
import { StyleSheet } from 'react-native-unistyles';
import { useTranslation } from 'react-i18next';
import { router } from 'expo-router';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useMutation } from '@tanstack/react-query';

import { Container } from '@/screens/editor/components';
import { Box } from '@/components/primitives/box';
import { VStack } from '@/components/primitives/vstack';
import { Input } from '@/components/forms/fields/input';
import { useUser } from '@/hooks/use-user';
import { createWorkout } from '@/crud/workout';
import { getExerciseLibrarySnapshot } from '@/crud/exercise';
import { queryClient } from '@/queries';
import { Label } from '@/components/forms/label';
import { Choices } from '@/components/forms/fields/choices';
import { Separator } from '@/components/layout/separator';
import { Datetime } from '@/components/forms/fields/datetime';
import { Switch } from '@/components/forms/fields/base/switch';
import { SheetChoices } from '@/components/forms/fields/sheet/choices';
import { useRunningWorkoutStatic } from '@/hooks/use-running-workout';
import { useUpdateWorkout, useWorkout } from '@/hooks/use-workouts';
import { useAnalytics } from '@/hooks/use-analytics';
import {
    getAnalyticsErrorType,
    getExerciseLibraryProperties,
    getWorkoutProgressProperties,
} from '@/analytics/helpers';
import { WorkoutSelect } from '@/db/schema';
import { reportError, runInBackground } from '@/services/error-reporting';

interface WorkoutEditorProps {
    workoutId?: string;
}

const category = [
    {
        value: 'planned' as const,
    },
    {
        value: 'in_progress' as const,
    },
    {
        value: 'completed' as const,
    },
];

const remind = [
    { value: 'start' },
    { value: '5m' },
    { value: '10m' },
    { value: '15m' },
    { value: '30m' },
    { value: '1h' },
    { value: '2h' },
];

const createWorkoutSchema = z.object({
    name: z.string().optional(),
    status: z.enum(['planned', 'in_progress', 'completed', 'cancelled']),
    startAt: z.date().nullable(),
    startedAt: z.date().nullable(),
    completedAt: z.date().nullable(),
    remind: z.enum(['start', '5m', '10m', '15m', '30m', '1h', '2h']).nullable(),
});

type CreateWorkoutFormData = z.infer<typeof createWorkoutSchema>;

const styles = StyleSheet.create((theme) => ({
    fieldsContainer: {
        paddingHorizontal: theme.space(4),
        gap: theme.space(5),
    },
    fieldContainer: {
        gap: theme.space(3),
    },
    fieldWrapper: {
        backgroundColor: theme.colors.background,
        borderRadius: theme.radius['4xl'],
        paddingVertical: theme.space(2),
    },
    fieldSeparator: {
        marginHorizontal: theme.space(5),
    },
    weightAssisted: {
        borderRadius: 0,
        borderTopWidth: 0,
    },
}));

// Wrapper that waits for data to load before mounting the form.
// This eliminates the race condition between reset() and status useEffect.
const Editor: FC<WorkoutEditorProps> = ({ workoutId }) => {
    const isEdit = Boolean(workoutId);
    const { data: existingWorkout, isLoading } = useWorkout(workoutId || '');

    if (isEdit && (isLoading || !existingWorkout)) {
        return null;
    }

    return <EditorForm existingWorkout={isEdit ? existingWorkout : undefined} />;
};

interface EditorFormProps {
    existingWorkout?: WorkoutSelect | null;
}

const toDate = (v: Date | null) => {
    if (!v) return null;
    return v instanceof Date ? v : new Date(v);
};

const EditorForm: FC<EditorFormProps> = ({ existingWorkout }) => {
    const { user } = useUser();
    const { t } = useTranslation(['common', 'screens']);
    const [startDate, setStartDate] = useState(Boolean(existingWorkout?.startAt));
    const { track } = useAnalytics();
    const { startWorkout } = useRunningWorkoutStatic();

    const updateWorkoutMutation = useUpdateWorkout();

    const isEdit = Boolean(existingWorkout);
    const editorOpenTrackedRef = useRef(false);

    useEffect(() => {
        if (editorOpenTrackedRef.current) return;
        editorOpenTrackedRef.current = true;
        track('workout:editor_opened', {
            mode: isEdit ? 'edit' : 'create',
            status: existingWorkout?.status ?? 'planned',
        });
    }, [existingWorkout?.status, isEdit, track]);

    const {
        control,
        handleSubmit,
        setValue,
        watch,
        formState: { errors, isSubmitting },
    } = useForm<CreateWorkoutFormData>({
        resolver: zodResolver(createWorkoutSchema),
        defaultValues: {
            name: existingWorkout?.name ?? '',
            status: existingWorkout?.status ?? 'planned',
            startAt: toDate(existingWorkout?.startAt ?? null),
            startedAt: toDate(existingWorkout?.startedAt ?? null),
            completedAt: toDate(existingWorkout?.completedAt ?? null),
            remind: existingWorkout?.remind ?? null,
        },
    });

    /* eslint-disable react-hooks/incompatible-library -- Render-time watch keeps RHF controlled fields updating reliably. */
    const selectedStatus = watch('status');
    const watchedStartedAt = watch('startedAt');
    const watchedCompletedAt = watch('completedAt');
    const watchedStartAt = watch('startAt');
    /* eslint-enable react-hooks/incompatible-library */

    // Skip the first run in edit mode — defaultValues already have the correct data
    const isFirstRun = useRef(isEdit);

    useEffect(() => {
        if (isFirstRun.current) {
            isFirstRun.current = false;
            return;
        }

        // Planned schedule toggling (allowed both in create and edit)
        if (selectedStatus === 'planned') {
            if (startDate) {
                const nextHour = new Date();
                nextHour.setMinutes(0, 0, 0);
                nextHour.setHours(nextHour.getHours() + 1);
                setValue('startAt', nextHour, { shouldValidate: true, shouldDirty: true });
                setValue('remind', '30m', { shouldValidate: true, shouldDirty: true });
            } else {
                setValue('startAt', null, { shouldValidate: true, shouldDirty: true });
                setValue('remind', null, { shouldValidate: true, shouldDirty: true });
            }
        } else {
            setValue('startAt', null, { shouldValidate: true, shouldDirty: true });
            setValue('remind', null, { shouldValidate: true, shouldDirty: true });
        }

        // Auto-fill duration window only in create mode
        if (!isEdit) {
            if (selectedStatus === 'completed') {
                const now = new Date();
                const oneHourLater = new Date(now.getTime());
                oneHourLater.setHours(oneHourLater.getHours() + 1);
                setValue('startedAt', now, { shouldValidate: true, shouldDirty: true });
                setValue('completedAt', oneHourLater, { shouldValidate: true, shouldDirty: true });
            } else {
                setValue('startedAt', null, { shouldValidate: true, shouldDirty: true });
                setValue('completedAt', null, { shouldValidate: true, shouldDirty: true });
            }
        }
    }, [selectedStatus, startDate, setValue, isEdit]);

    const createWorkoutMutation = useMutation({
        mutationFn: async (data: Parameters<typeof createWorkout>[0]) => {
            const [created, exerciseLibrary] = await Promise.all([
                createWorkout(data),
                getExerciseLibrarySnapshot(),
            ]);
            return { created, exerciseLibrary };
        },
        onSuccess: ({ created, exerciseLibrary }) => {
            queryClient.invalidateQueries({ queryKey: ['workouts', user?.id] });
            track('workout:create', {
                workoutId: created.id,
                status: created.status,
                hasStartDate: Boolean(created.startAt),
                hasReminder: Boolean(created.remind),
                ...getWorkoutProgressProperties(0, 0, 0),
                ...getExerciseLibraryProperties(
                    exerciseLibrary?.exerciseLibraryTotalCount ?? null,
                    exerciseLibrary?.exerciseLibrarySkulptCount ?? null,
                    exerciseLibrary?.exerciseLibraryUserCreatedCount ?? null,
                ),
            });
            if (created.remind) {
                track('workout:reminder_configured', {
                    workoutId: created.id,
                    leadTime: created.remind,
                    source: 'create',
                });
            }
            if (created && created.status === 'in_progress') {
                runInBackground(
                    () => startWorkout(created.id, 'new'),
                    'Failed to auto-start newly created workout:',
                );
            }
            router.replace(`/workout/${created.id}`);
        },
        onError: (error) => {
            track('workout:operation_failed', {
                operation: 'create',
                errorType: getAnalyticsErrorType(error),
            });
            reportError(error, 'Failed to create workout:');
        },
    });

    const onSubmit = handleSubmit(async (payload: CreateWorkoutFormData) => {
        if (!user) {
            return;
        }

        track('workout:editor_submitted', {
            mode: isEdit ? 'edit' : 'create',
            status: payload.status,
            hasStartDate: Boolean(payload.startAt),
            hasReminder: Boolean(payload.remind),
        });

        const workoutName =
            payload.name?.trim() || t('workout-editor.namePlaceholder', { ns: 'screens' });

        if (isEdit && existingWorkout) {
            updateWorkoutMutation.mutate(
                {
                    id: existingWorkout.id,
                    updates: {
                        name: workoutName,
                        // Keep status unchanged in edit mode
                        startAt: payload.startAt,
                        startedAt: payload.startedAt,
                        completedAt: payload.completedAt,
                        remind: payload.remind,
                    },
                },
                {
                    onSuccess: (updated) => {
                        const previousStartAt = existingWorkout.startAt?.getTime() ?? null;
                        const updatedStartAt = updated.startAt?.getTime() ?? null;
                        const previousStartedAt = existingWorkout.startedAt?.getTime() ?? null;
                        const updatedStartedAt = updated.startedAt?.getTime() ?? null;
                        const previousCompletedAt = existingWorkout.completedAt?.getTime() ?? null;
                        const updatedCompletedAt = updated.completedAt?.getTime() ?? null;
                        const reminderChanged =
                            existingWorkout.remind !== updated.remind ||
                            previousStartAt !== updatedStartAt;
                        track('workout:update', {
                            workoutId: updated.id,
                            status: updated.status,
                            scheduleChanged: previousStartAt !== updatedStartAt,
                            reminderChanged: existingWorkout.remind !== updated.remind,
                            timingChanged:
                                previousStartedAt !== updatedStartedAt ||
                                previousCompletedAt !== updatedCompletedAt,
                        });
                        if (updated.remind && reminderChanged) {
                            track('workout:reminder_configured', {
                                workoutId: updated.id,
                                leadTime: updated.remind,
                                source: 'update',
                            });
                        }
                        router.back();
                    },
                },
            );
            return;
        }

        createWorkoutMutation.mutate({
            userId: user.id,
            ...payload,
            name: workoutName,
        });
    });

    const handleClose = () => router.back();

    return (
        <Container
            title={t(isEdit ? 'edit' : 'create', {
                ns: 'common',
            })}
            handleSubmit={onSubmit}
            handleClose={handleClose}
            loading={isSubmitting}
            submitDisabled={isSubmitting}
        >
            <Box style={styles.fieldsContainer}>
                <VStack style={styles.fieldContainer}>
                    <Label>{t('workout-editor.name', { ns: 'screens' })}</Label>
                    <Input
                        placeholder={t('workout-editor.namePlaceholder', { ns: 'screens' })}
                        control={control}
                        name="name"
                        valueType="text"
                        error={errors.name}
                    />
                </VStack>
                {!isEdit && (
                    <VStack style={styles.fieldContainer}>
                        <Label>{t('workout-editor.status', { ns: 'screens' })}</Label>
                        <Choices
                            control={control}
                            name="status"
                            choices={category.map((v) => ({
                                value: v.value,
                                title: t(`workoutStatus.${v.value}`, { ns: 'common' }),
                            }))}
                            error={errors.status}
                        />
                    </VStack>
                )}
                {selectedStatus === 'planned' && (
                    <VStack style={styles.fieldContainer}>
                        <Label>{t('workout-editor.startDate', { ns: 'screens' })}</Label>
                        <VStack style={styles.fieldWrapper}>
                            <Switch
                                value={startDate}
                                onChange={setStartDate}
                                title={t('workout-editor.setStartDate', { ns: 'screens' })}
                                containerStyle={styles.weightAssisted}
                            />
                            {startDate && watchedStartAt && (
                                <>
                                    <Separator style={styles.fieldSeparator} />
                                    <Datetime
                                        title={t('workout-editor.start', { ns: 'screens' })}
                                        name="startAt"
                                        control={control}
                                        error={errors.startAt}
                                    />
                                    <Separator style={styles.fieldSeparator} />
                                    <SheetChoices
                                        control={control}
                                        name="remind"
                                        title={t('workout-editor.remind', { ns: 'screens' })}
                                        error={errors.remind}
                                        choices={remind.map((v) => ({
                                            value: v.value,
                                            title: t(`workoutRemind.${v.value}`, { ns: 'common' }),
                                        }))}
                                    />
                                </>
                            )}
                        </VStack>
                    </VStack>
                )}
                {selectedStatus === 'completed' && watchedStartedAt && watchedCompletedAt && (
                    <VStack style={styles.fieldContainer}>
                        <Label>{t('workout-editor.duration', { ns: 'screens' })}</Label>
                        <VStack style={styles.fieldWrapper}>
                            <Datetime
                                title={t('workout-editor.start', { ns: 'screens' })}
                                name="startedAt"
                                control={control}
                                error={errors.startedAt}
                            />
                            <Separator style={styles.fieldSeparator} />
                            <Datetime
                                title={t('workout-editor.end', { ns: 'screens' })}
                                name="completedAt"
                                control={control}
                                error={errors.completedAt}
                            />
                        </VStack>
                    </VStack>
                )}
            </Box>
        </Container>
    );
};

export default Editor;
