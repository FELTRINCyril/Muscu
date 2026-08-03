import { CreateButton } from '@/components/buttons/create';
import { useEditor } from '@/hooks/use-editor';
import { useAnalytics } from '@/hooks/use-analytics';
import { useScreen } from '@/hooks/use-screen';

const useHomeTab = () => {
    const { options } = useScreen();
    const { navigate } = useEditor();
    const { track } = useAnalytics();

    const handleWorkoutCreate = () => {
        track('workout:create_requested', { surface: 'home_header' });
        navigate({ type: 'workout__create' });
    };

    return {
        name: 'index',
        options: {
            headerTransparent: true,
            headerStyle: {
                ...options.headerStyle,
                backgroundColor: 'transparent',
            },
            headerRight: () => <CreateButton onPressHandler={handleWorkoutCreate} />,
        },
    };
};

export { useHomeTab };
