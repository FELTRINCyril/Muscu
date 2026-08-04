import { FC } from 'react';
import { useTranslation } from 'react-i18next';
import { Plus } from 'lucide-react-native';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';

import { Text } from '@/components/primitives/text';
import { VStack } from '@/components/primitives/vstack';
import { Box } from '@/components/primitives/box';
import { Pressable } from '@/components/primitives/pressable';
import { useEditor } from '@/hooks/use-editor';

const styles = StyleSheet.create((theme, rt) => ({
    container: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        paddingHorizontal: theme.space(8),
        paddingBottom: rt.insets.bottom + theme.space(25),
        gap: theme.space(6),
    },
    emptyContainer: {
        alignItems: 'center',
        gap: theme.space(2),
    },
    emptyTitle: {
        color: theme.colors.typography,
        fontSize: theme.fontSize.xl.fontSize,
        fontWeight: theme.fontWeight.bold.fontWeight,
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
}));
const EmptyState: FC = () => {
    const { t } = useTranslation(['screens']);
    const { theme, rt } = useUnistyles();
    const { navigate } = useEditor();

    const title = t('exercises.empty.title', { ns: 'screens' });
    const description = t('exercises.empty.description', { ns: 'screens' });

    const handleExerciseCreate = () => {
        navigate({ type: 'exercise__create' });
    };

    return (
        <VStack style={styles.container}>
            <Pressable
                style={styles.emptyContainer}
                onPress={handleExerciseCreate}
                accessibilityRole="button"
                accessibilityLabel={description}
            >
                <Text style={styles.emptyTitle}>{title}</Text>
                <Text style={styles.emptyDescription}>{description}</Text>
            </Pressable>
            <Box style={styles.buttonContainer}>
                <Pressable
                    style={styles.button}
                    onPress={handleExerciseCreate}
                    accessibilityRole="button"
                    accessibilityLabel={title}
                >
                    <Plus
                        size={theme.space(8)}
                        color={
                            rt.themeName === 'dark' ? theme.colors.neutral[950] : theme.colors.white
                        }
                    />
                </Pressable>
            </Box>
        </VStack>
    );
};

export { EmptyState };
