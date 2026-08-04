import { FC, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { Plus } from 'lucide-react-native';
import { router } from 'expo-router';

import { Text } from '@/components/primitives/text';
import { VStack } from '@/components/primitives/vstack';
import { Box } from '@/components/primitives/box';
import { Pressable } from '@/components/primitives/pressable';
import { WorkoutSelect } from '@/db/schema';
import { useAnalytics } from '@/hooks/use-analytics';
import { getExerciseLibrarySnapshot } from '@/crud/exercise';
import { getExerciseLibraryProperties } from '@/analytics/helpers';

interface EmptyStateProps {
    workout?: WorkoutSelect;
}

const styles = StyleSheet.create((theme, rt) => ({
    container: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        paddingHorizontal: theme.space(8),
        paddingTop: rt.insets.bottom,
        gap: theme.space(6),
    },
    emptyContainer: {
        alignItems: 'center',
        gap: theme.space(2),
    },
    emptyTitle: {
        fontSize: theme.fontSize.xl.fontSize,
        fontWeight: theme.fontWeight.bold.fontWeight,
        color: theme.colors.typography,
    },
    emptyDescription: {
        color: theme.colors.typography,
        opacity: 0.6,
        textAlign: 'center',
    },
    buttonContainer: {
        justifyContent: 'center',
        alignItems: 'center',
    },
    button: {
        backgroundColor: rt.themeName === 'dark' ? theme.colors.white : theme.colors.neutral[950],
        borderRadius: theme.radius.full,
        height: theme.space(16),
        width: theme.space(16),
        justifyContent: 'center',
        alignItems: 'center',
    },
    icon: {},
}));
const EmptyState: FC<EmptyStateProps> = ({ workout }) => {
    const { t } = useTranslation(['screens']);
    const { theme, rt } = useUnistyles();
    const { track } = useAnalytics();

    const title = useMemo(() => {
        if (workout?.status) return t(`workout.empty.title.${workout.status}`, { ns: 'screens' });
        return t('workout.empty.title.planned', { ns: 'screens' });
    }, [t, workout]);

    const description = useMemo(() => {
        if (workout?.status)
            return t(`workout.empty.description.${workout.status}`, { ns: 'screens' });
        return t('workout.empty.description.planned', { ns: 'screens' });
    }, [t, workout]);

    const handleExerciseAdd = async () => {
        if (workout) {
            const exerciseLibrary = await getExerciseLibrarySnapshot();
            track('workout:exercise_add_requested', {
                workoutId: workout.id,
                surface: 'empty_state',
                status: workout.status,
                ...getExerciseLibraryProperties(
                    exerciseLibrary?.exerciseLibraryTotalCount ?? null,
                    exerciseLibrary?.exerciseLibrarySkulptCount ?? null,
                    exerciseLibrary?.exerciseLibraryUserCreatedCount ?? null,
                ),
            });
            router.navigate(`/select?workoutId=${workout.id}`);
        } else {
            router.navigate('/select');
        }
    };

    return (
        <VStack style={styles.container}>
            <Pressable
                style={styles.emptyContainer}
                onPress={handleExerciseAdd}
                accessibilityRole="button"
                accessibilityLabel={description}
            >
                <Text style={styles.emptyTitle}>{title}</Text>
                <Text style={styles.emptyDescription}>{description}</Text>
            </Pressable>
            <Box style={styles.buttonContainer}>
                <Pressable style={styles.button} onPress={handleExerciseAdd}>
                    <Box style={styles.buttonContainer}>
                        <Plus
                            style={styles.icon}
                            size={theme.space(8)}
                            color={
                                rt.themeName === 'dark'
                                    ? theme.colors.neutral[950]
                                    : theme.colors.white
                            }
                        />
                    </Box>
                </Pressable>
            </Box>
        </VStack>
    );
};

export { EmptyState };
